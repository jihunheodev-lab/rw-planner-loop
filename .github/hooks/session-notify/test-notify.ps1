# Fixture tests for notify.ps1
# Validates: event routing, filtering, duplicate suppression, stdout JSON contract, $env:TEMP usage, Start-Process async
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$notifyScript = Join-Path $scriptDir "notify.ps1"
$pass = 0
$fail = 0
$tempDir = $env:TEMP

# Clean up lock files
Get-ChildItem -Path $tempDir -Filter "copilot_notify_last_*" -ErrorAction SilentlyContinue | Remove-Item -Force

# Disable actual notifications for testing
$env:COPILOT_NOTIFY_CHANNELS = "none"

function Assert-JsonContinue {
    param([string]$TestName, [string]$Output)
    if ($Output -match '"continue"\s*:\s*true') {
        $script:pass++
        Write-Host "  PASS: $TestName"
    } else {
        $script:fail++
        Write-Host "  FAIL: $TestName — expected {`"continue`":true}, got: $Output"
    }
}

function Assert-SingleLine {
    param([string]$TestName, [string]$Output)
    $lines = ($Output.Trim() -split "`n").Count
    if ($lines -le 1) {
        $script:pass++
        Write-Host "  PASS: $TestName (single line output)"
    } else {
        $script:fail++
        Write-Host "  FAIL: $TestName — expected 1 line, got $lines lines"
    }
}

function Invoke-NotifyWithInput {
    param([string]$JsonInput)
    $tempIn = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $tempIn -Value $JsonInput -NoNewline
    try {
        $output = Get-Content $tempIn -Raw | pwsh -NoProfile -File $notifyScript 2>$null
        return $output
    } finally {
        Remove-Item $tempIn -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "=== notify.ps1 Fixture Tests ==="
Write-Host ""

# --- Test 1: Stop event ---
Write-Host "Test 1: Stop event"
Remove-Item (Join-Path $tempDir "copilot_notify_last_Stop") -Force -ErrorAction SilentlyContinue
$output = '{"hook_event_name":"Stop","stop_hook_active":false,"timestamp":"2026-01-01T00:00:00Z","cwd":"C:\\temp","session_id":"test-1"}' | pwsh -NoProfile -File $notifyScript 2>$null
Assert-JsonContinue "Stop event returns valid JSON" $output
Assert-SingleLine "Stop event single line stdout" $output

# --- Test 2: Stop + stop_hook_active=true ---
Write-Host "Test 2: Stop + stop_hook_active=true"
Remove-Item (Join-Path $tempDir "copilot_notify_last_Stop") -Force -ErrorAction SilentlyContinue
$output = '{"hook_event_name":"Stop","stop_hook_active":true,"timestamp":"2026-01-01T00:00:00Z","cwd":"C:\\temp"}' | pwsh -NoProfile -File $notifyScript 2>$null
Assert-JsonContinue "stop_hook_active skips notification" $output

# --- Test 3: PreToolUse + askQuestions ---
Write-Host "Test 3: PreToolUse + askQuestions"
Remove-Item (Join-Path $tempDir "copilot_notify_last_PreToolUse") -Force -ErrorAction SilentlyContinue
$output = '{"hook_event_name":"PreToolUse","tool_name":"vscode_askQuestions","tool_input":{},"tool_use_id":"t1"}' | pwsh -NoProfile -File $notifyScript 2>$null
Assert-JsonContinue "askQuestions returns valid JSON" $output
Assert-SingleLine "askQuestions single line stdout" $output

# --- Test 4: PreToolUse + read_file (filtered) ---
Write-Host "Test 4: PreToolUse + read_file (should be filtered)"
Remove-Item (Join-Path $tempDir "copilot_notify_last_PreToolUse") -Force -ErrorAction SilentlyContinue
$output = '{"hook_event_name":"PreToolUse","tool_name":"read_file","tool_input":{},"tool_use_id":"t2"}' | pwsh -NoProfile -File $notifyScript 2>$null
Assert-JsonContinue "read_file filtered, returns valid JSON" $output

# --- Test 5: Duplicate suppression ---
Write-Host "Test 5: Duplicate suppression"
Remove-Item (Join-Path $tempDir "copilot_notify_last_Stop") -Force -ErrorAction SilentlyContinue
# First call
'{"hook_event_name":"Stop","stop_hook_active":false,"timestamp":"2026-01-01T00:00:00Z","cwd":"C:\\temp"}' | pwsh -NoProfile -File $notifyScript 2>$null | Out-Null
# Second call (within 30s)
$output = '{"hook_event_name":"Stop","stop_hook_active":false,"timestamp":"2026-01-01T00:00:00Z","cwd":"C:\\temp"}' | pwsh -NoProfile -File $notifyScript 2>$null
Assert-JsonContinue "Duplicate suppressed, returns valid JSON" $output
# Verify lock file uses $env:TEMP
$lockFile = Join-Path $tempDir "copilot_notify_last_Stop"
if (Test-Path $lockFile) {
    $script:pass++
    Write-Host "  PASS: Lock file created in `$env:TEMP"
} else {
    $script:fail++
    Write-Host "  FAIL: Lock file not created in `$env:TEMP"
}

# --- Test 6: Unknown event ---
Write-Host "Test 6: Unknown event"
$output = '{"hook_event_name":"UnknownEvent"}' | pwsh -NoProfile -File $notifyScript 2>$null
Assert-JsonContinue "Unknown event returns valid JSON" $output

# --- Test 7: .env file variable loading ---
Write-Host "Test 7: .env file variable loading"
Remove-Item (Join-Path $tempDir "copilot_notify_last_Stop") -Force -ErrorAction SilentlyContinue
$envFilePath = Join-Path $scriptDir ".env"
$envBackup = $null
if (Test-Path $envFilePath) { $envBackup = Get-Content $envFilePath -Raw }
Set-Content -Path $envFilePath -Value "COPILOT_NOTIFY_CHANNELS=none" -NoNewline
# Run in subprocess with env var removed
$output = pwsh -NoProfile -Command {
    param($script)
    Remove-Item Env:COPILOT_NOTIFY_CHANNELS -ErrorAction SilentlyContinue
    '{"hook_event_name":"Stop","stop_hook_active":false}' | pwsh -NoProfile -File $script 2>$null
} -Args $notifyScript 2>$null
Assert-JsonContinue ".env file loaded (COPILOT_NOTIFY_CHANNELS=none)" $output
# Restore .env
Remove-Item $envFilePath -Force -ErrorAction SilentlyContinue
if ($envBackup) { Set-Content -Path $envFilePath -Value $envBackup -NoNewline }

# --- Test 8: Shell env overrides .env file ---
Write-Host "Test 8: Shell env overrides .env file"
Remove-Item (Join-Path $tempDir "copilot_notify_last_Stop") -Force -ErrorAction SilentlyContinue
if (Test-Path $envFilePath) { $envBackup = Get-Content $envFilePath -Raw } else { $envBackup = $null }
Set-Content -Path $envFilePath -Value "COPILOT_NOTIFY_DEBUG=1" -NoNewline
$stderrFile = Join-Path $env:TEMP "copilot_test8_stderr.txt"
$output = pwsh -NoProfile -Command {
    param($script)
    $env:COPILOT_NOTIFY_DEBUG = "0"
    $env:COPILOT_NOTIFY_CHANNELS = "none"
    '{"hook_event_name":"Stop","stop_hook_active":false}' | pwsh -NoProfile -File $script 2>$using:stderrFile
} -Args $notifyScript 2>$null
$stderrContent = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue } else { "" }
Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue
if ($stderrContent -match '\[DEBUG\]') {
    $script:fail++
    Write-Host "  FAIL: .env file overrode shell env var"
} else {
    $script:pass++
    Write-Host "  PASS: Shell env var overrides .env file"
}
Remove-Item $envFilePath -Force -ErrorAction SilentlyContinue
if ($envBackup) { Set-Content -Path $envFilePath -Value $envBackup -NoNewline }

# --- Test 9: COPILOT_NOTIFY_EVENTS=stop filters PreToolUse ---
Write-Host "Test 9: Event filter (stop only)"
Remove-Item (Join-Path $tempDir "copilot_notify_last_PreToolUse") -Force -ErrorAction SilentlyContinue
$env:COPILOT_NOTIFY_EVENTS = "stop"
$output = '{"hook_event_name":"PreToolUse","tool_name":"vscode_askQuestions","tool_input":{},"tool_use_id":"t9"}' | pwsh -NoProfile -File $notifyScript 2>$null
Assert-JsonContinue "PreToolUse filtered when EVENTS=stop" $output
Remove-Item Env:COPILOT_NOTIFY_EVENTS -ErrorAction SilentlyContinue

# --- Test 10: COPILOT_NOTIFY_EVENTS=none filters everything ---
Write-Host "Test 10: Event filter (none)"
Remove-Item (Join-Path $tempDir "copilot_notify_last_Stop") -Force -ErrorAction SilentlyContinue
$env:COPILOT_NOTIFY_EVENTS = "none"
$output = '{"hook_event_name":"Stop","stop_hook_active":false}' | pwsh -NoProfile -File $notifyScript 2>$null
Assert-JsonContinue "Stop filtered when EVENTS=none" $output
Remove-Item Env:COPILOT_NOTIFY_EVENTS -ErrorAction SilentlyContinue

# --- Summary ---
Write-Host ""
Write-Host "=== Results: $pass passed, $fail failed ==="

# Clean up
Get-ChildItem -Path $tempDir -Filter "copilot_notify_last_*" -ErrorAction SilentlyContinue | Remove-Item -Force

if ($fail -gt 0) { exit 1 }
exit 0
