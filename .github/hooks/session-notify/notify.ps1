# Copilot Chat Agent Notification Hook (Windows)
# Sends notifications on Stop, PreToolUse (askQuestions/approval) events
# Channels: OS native, Telegram (configurable via COPILOT_NOTIFY_CHANNELS)
$ErrorActionPreference = "Stop"

# --- Load .env file (fallback; shell env vars take priority) ---
$envFile = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFile -ErrorAction SilentlyContinue) {
    foreach ($line in (Get-Content $envFile)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
        $eqIdx = $trimmed.IndexOf('=')
        if ($eqIdx -lt 1) { continue }
        $key = $trimmed.Substring(0, $eqIdx)
        $val = $trimmed.Substring($eqIdx + 1)
        # Strip surrounding quotes
        if (($val.StartsWith('"') -and $val.EndsWith('"')) -or ($val.StartsWith("'") -and $val.EndsWith("'"))) {
            $val = $val.Substring(1, $val.Length - 2)
        }
        # Only set if not already defined
        if ([string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($key))) {
            Set-Item -Path "env:$key" -Value $val
        }
    }
}

# --- Read stdin JSON ---
try {
    $rawInput = [Console]::In.ReadToEnd()
    $hookInput = $rawInput | ConvertFrom-Json
} catch {
    Write-Output '{"continue":true}'
    exit 0
}

$event = $hookInput.hook_event_name
$toolName = $hookInput.tool_name
$stopHookActive = $hookInput.stop_hook_active
$transcriptPath = $hookInput.transcript_path
$sessionId = $hookInput.session_id
$cwd = $hookInput.cwd

# --- Detail level: short / normal / verbose ---
$detailLevel = if ($env:COPILOT_NOTIFY_DETAIL) { $env:COPILOT_NOTIFY_DETAIL.ToLower() } else { "normal" }

# --- Debug mode ---
if ($env:COPILOT_NOTIFY_DEBUG -eq "1") {
    [Console]::Error.WriteLine("[DEBUG] hook_event_name=$event tool_name=$toolName stop_hook_active=$stopHookActive detailLevel=$detailLevel")
}

# --- Event filter (COPILOT_NOTIFY_EVENTS) ---
$notifyEvents = if ($env:COPILOT_NOTIFY_EVENTS) { $env:COPILOT_NOTIFY_EVENTS.ToLower() } else { "all" }
if ($notifyEvents -eq "none") {
    Write-Output '{"continue":true}'
    exit 0
}
if ($notifyEvents -ne "all") {
    $allowed = $notifyEvents -split ','
    if ($event.ToLower() -notin $allowed) {
        Write-Output '{"continue":true}'
        exit 0
    }
}

# --- Determine notification message ---
$msg = $null

switch ($event) {
    "Stop" {
        # Prevent infinite loop
        if ($stopHookActive -eq $true) {
            Write-Output '{"continue":true}'
            exit 0
        }

        # Try to detect error from transcript (.jsonl — one JSON per line)
        if ($transcriptPath -and (Test-Path $transcriptPath -ErrorAction SilentlyContinue)) {
            try {
                $transcriptLines = [System.IO.File]::ReadAllLines($transcriptPath, [System.Text.Encoding]::UTF8)
                $hasError = $false
                foreach ($line in $transcriptLines) {
                    $trimLine = $line.Trim()
                    if (-not $trimLine) { continue }
                    try {
                        $entry = $trimLine | ConvertFrom-Json
                        if ($entry.type -match 'error') {
                            $hasError = $true
                            break
                        }
                        # Also check for tool execution failures
                        if ($entry.type -eq 'tool.execution_complete' -and $entry.error) {
                            $hasError = $true
                            break
                        }
                    } catch { continue }
                }
                if ($hasError) {
                    $msg = "Copilot: 작업 실패!"
                } else {
                    $msg = "Copilot: 작업 완료!"
                }
            } catch {
                # Fallback on parse failure
                $msg = "Copilot: 세션 종료"
            }
        } else {
            $msg = "Copilot: 세션 종료"
        }
    }
    "PreToolUse" {
        if ($toolName -match "askQuestions|vscode_askQuestions") {
            $msg = "Copilot: 질문을 기다리고 있어요!"
        } else {
            # No notification for other tools
            Write-Output '{"continue":true}'
            exit 0
        }
    }
    default {
        Write-Output '{"continue":true}'
        exit 0
    }
}

# --- Enrich message with context (normal/verbose) ---
if ($detailLevel -ne "short" -and $msg -and $transcriptPath -and (Test-Path $transcriptPath -ErrorAction SilentlyContinue)) {
    try {
        $contextLines = @()
        $projectName = if ($cwd) { Split-Path $cwd -Leaf } else { $null }
        $firstUserMsg = $null
        $lastUserMsg = $null

        foreach ($tl in ([System.IO.File]::ReadAllLines($transcriptPath, [System.Text.Encoding]::UTF8))) {
            $trimTl = $tl.Trim()
            if (-not $trimTl) { continue }
            try {
                $te = $trimTl | ConvertFrom-Json
                if ($te.type -eq 'user.message' -and $te.data -and $te.data.content) {
                    $content = ($te.data.content -replace '\r?\n', ' ').Trim()
                    # Strip markdown formatting
                    $content = $content -replace '\*+', '' -replace '`+', '' -replace '#+\s*', ''
                    $content = ($content -replace '\s+', ' ').Trim()
                    if (-not $firstUserMsg) { $firstUserMsg = $content }
                    $lastUserMsg = $content
                }
            } catch { continue }
        }

        # Try to get AI-generated session title from VS Code state DB (pure PowerShell, no external deps)
        $chatTitle = $null
        try {
            # Derive state.vscdb: transcript is at .../workspaceStorage/<hash>/GitHub.copilot-chat/transcripts/<id>.jsonl
            $stateDb = Join-Path (Split-Path (Split-Path (Split-Path $transcriptPath -Parent) -Parent) -Parent) "state.vscdb"
            if (Test-Path $stateDb -ErrorAction SilentlyContinue) {
                # Read SQLite file as raw bytes (shared read to avoid lock conflicts with VS Code)
                $fs = [System.IO.File]::Open($stateDb, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                $dbBytes = New-Object byte[] $fs.Length
                [void]$fs.Read($dbBytes, 0, $fs.Length)
                $fs.Close()
                $dbText = [System.Text.Encoding]::UTF8.GetString($dbBytes)
                # Extract title + lastMessageDate pairs from ChatSessionStore data
                $titlePattern = '"title"\s*:\s*"([^"]{2,120})"\s*,\s*"lastMessageDate"\s*:\s*(\d+)'
                $titleMatches = [regex]::Matches($dbText, $titlePattern)
                $bestTs = [long]0
                foreach ($tm in $titleMatches) {
                    $t = $tm.Groups[1].Value
                    $ts = [long]$tm.Groups[2].Value
                    if ($t -ne 'New Chat' -and $ts -gt $bestTs) {
                        $bestTs = $ts
                        $chatTitle = $t
                    }
                }
            }
        } catch { $chatTitle = $null }

        if ($projectName) {
            $contextLines += [char]::ConvertFromUtf32(0x1F4C2) + " $projectName"
        }
        if ($chatTitle) {
            $truncTitle = if ($chatTitle.Length -gt 40) { $chatTitle.Substring(0, 40) + '...' } else { $chatTitle }
            $contextLines += [char]::ConvertFromUtf32(0x1F4AC) + " $truncTitle"
        } elseif ($firstUserMsg) {
            $truncFirst = if ($firstUserMsg.Length -gt 30) { $firstUserMsg.Substring(0, 30) + '...' } else { $firstUserMsg }
            $contextLines += [char]::ConvertFromUtf32(0x1F4AC) + " `"$truncFirst`""
        }
        if ($detailLevel -eq 'verbose') {
            if ($sessionId) {
                $shortId = $sessionId.Substring(0, [Math]::Min(8, $sessionId.Length))
                $contextLines += [char]::ConvertFromUtf32(0x1F3F7) + " $shortId"
            }
            if ($lastUserMsg -and $lastUserMsg -ne $firstUserMsg) {
                $truncLast = if ($lastUserMsg.Length -gt 40) { $lastUserMsg.Substring(0, 40) + '...' } else { $lastUserMsg }
                $contextLines += [char]::ConvertFromUtf32(0x1F4DD) + " `"$truncLast`""
            }
        }

        if ($contextLines.Count -gt 0) {
            $msg = $msg + "`n" + ($contextLines -join "`n")
        }
    } catch {
        # Silently ignore enrichment failures
    }
}

# --- Duplicate suppression (30s per eventType) ---
$tempDir = $env:TEMP
$lockFile = Join-Path $tempDir "copilot_notify_last_$event"
$now = [int][double]::Parse((Get-Date -UFormat %s))

if (Test-Path $lockFile -ErrorAction SilentlyContinue) {
    try {
        $lastSent = [int](Get-Content $lockFile -Raw).Trim()
        $diff = $now - $lastSent
        if ($diff -lt 30) {
            Write-Output '{"continue":true}'
            exit 0
        }
    } catch {
        # Ignore parse errors on lock file
    }
}
Set-Content -Path $lockFile -Value $now -NoNewline

# --- Channel selection ---
$channels = if ($env:COPILOT_NOTIFY_CHANNELS) { $env:COPILOT_NOTIFY_CHANNELS } else { "os" }

# --- Send: OS native notification (Windows Balloon) ---
if ($channels -match "os") {
    try {
        $escapedMsg = $msg -replace "'", "''"
        $balloonScript = @"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
`$b = New-Object System.Windows.Forms.NotifyIcon
`$b.Icon = [System.Drawing.SystemIcons]::Information
`$b.BalloonTipTitle = 'GitHub Copilot'
`$b.BalloonTipText = '$escapedMsg'
`$b.BalloonTipIcon = 'Info'
`$b.Visible = `$true
`$b.ShowBalloonTip(5000)
Start-Sleep -Seconds 4
`$b.Dispose()
"@
        $tmpScript = Join-Path $env:TEMP "copilot_balloon.ps1"
        [System.IO.File]::WriteAllText($tmpScript, $balloonScript, [System.Text.UTF8Encoding]::new($true))
        Start-Process -WindowStyle Hidden -FilePath "powershell.exe" `
            -ArgumentList "-NoProfile", "-STA", "-ExecutionPolicy", "Bypass", "-File", $tmpScript `
            -ErrorAction SilentlyContinue
    } catch {
        [Console]::Error.WriteLine("[WARN] OS notification failed: $_")
    }
}

# --- Send: Telegram ---
if ($channels -match "telegram") {
    if ($env:TELEGRAM_BOT_TOKEN -and $env:TELEGRAM_CHAT_ID) {
        $telegramUrl = "https://api.telegram.org/bot$($env:TELEGRAM_BOT_TOKEN)/sendMessage"
        if ($env:COPILOT_NOTIFY_DEBUG -eq "1") {
            [Console]::Error.WriteLine("[DEBUG] Telegram sending: url=$telegramUrl chatId=$($env:TELEGRAM_CHAT_ID) msg=$msg")
        }
        try {
            $body = @{ chat_id = $env:TELEGRAM_CHAT_ID; text = $msg } | ConvertTo-Json -Compress
            Invoke-RestMethod -Uri $telegramUrl -Method Post -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($body)) -TimeoutSec 5 | Out-Null
            if ($env:COPILOT_NOTIFY_DEBUG -eq "1") {
                [Console]::Error.WriteLine("[DEBUG] Telegram sent successfully")
            }
        } catch {
            [Console]::Error.WriteLine("[WARN] Telegram notification failed: $_")
        }
    } else {
        [Console]::Error.WriteLine("[WARN] Telegram credentials not set (TELEGRAM_BOT_TOKEN=$($env:TELEGRAM_BOT_TOKEN) TELEGRAM_CHAT_ID=$($env:TELEGRAM_CHAT_ID))")
    }
}

# --- Always output valid JSON for VS Code ---
Write-Output '{"continue":true}'
exit 0
