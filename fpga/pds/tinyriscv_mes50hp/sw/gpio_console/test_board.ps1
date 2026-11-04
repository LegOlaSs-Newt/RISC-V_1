# 模块说明：test_board。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([Parameter(Mandatory = $true)][string]$Port, [Parameter(Mandatory = $true)][string]$Output, [int]$StartupTimeoutSec = 90, [string]$ReadyFile)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Output) {
    throw 'Use a new output path; do not overwrite board evidence.' 
}
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Output) | Out-Null
$serial = [IO.Ports.SerialPort]::new($Port, 115200, [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.ReadTimeout = 100
$serial.WriteTimeout = 3000
$buffer = ''
$script:tests = 0
function Log([string]$Text) {
    Add-Content -LiteralPath $Output -Value $Text -Encoding utf8
    Write-Output $Text 
}
function Next-Line([int]$TimeoutSec) {
    $end = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $end) {
        $script:buffer += $serial.ReadExisting()
        $newline = $script:buffer.IndexOf("`n")
        if ($newline -ge 0) {
            $line = $script:buffer.Substring(0, $newline).TrimEnd("`r")
            $script:buffer = $script:buffer.Substring($newline + 1)
            Add-Content -LiteralPath $Output -Value ('RX ' + $line) -Encoding utf8
            return $line
        }
        Start-Sleep -Milliseconds 10
    }
    if ($script:buffer.Length) {
        Add-Content -LiteralPath $Output -Value ('PARTIAL ' + $script:buffer) -Encoding utf8 
    }
    throw "UART line timeout after $TimeoutSec seconds"
}
function Expect([string]$Expected, [int]$TimeoutSec = 5) {
    $actual = Next-Line $TimeoutSec
    if ($actual -cne $Expected) {
        throw "Expected [$Expected], got [$actual]" 
    }
    $script:tests++
}
function Command([string]$Text, [string]$Expected) {
    Log ('TX ' + $Text)
    $serial.Write($Text + "`n")
    Expect $Expected
}
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    if ($ReadyFile) {
        $readyPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReadyFile)
        if (Test-Path -LiteralPath $readyPath) {
            throw 'ReadyFile exists; choose a new path'
        }
        [ordered]@{ReadyAt = (Get-Date -Format o)
            Port           = $Port
            Output         = $Output
            ProcessId      = $PID
        } | ConvertTo-Json | Set-Content -LiteralPath $readyPath -Encoding utf8
    }
    Log "Listening on $Port, 115200 8N1. Press KEY2 to exit download mode (or KEY1 to restart console)."
    Expect 'RISC-V GPIO CONSOLE V1 115200 8N1' $StartupTimeoutSec
    Expect 'READY CTRL=00000000'
    Command 'READ' 'OK CTRL=00000000 DATA=0000'
    Command 'HELP' 'HELP | MODE <hex32> | WRITE <hex16> | READ | SELFTEST'
    # Eight external loopback pairs remain connected. Only one side drives.
    Command 'MODE AAAA5555' 'OK MODE=AAAA5555'
    Command 'WRITE 0055' 'OK WRITE=0055'
    Command 'READ' 'OK CTRL=AAAA5555 DATA=5555'
    Command 'WRITE 00AA' 'OK WRITE=00AA'
    Command 'READ' 'OK CTRL=AAAA5555 DATA=AAAA'
    Command 'WRITE 10000' 'ERR COMMAND'
    Command 'MODE 100000000' 'ERR COMMAND'
    Command 'READ 1' 'ERR COMMAND'
    Command 'READ' 'OK CTRL=AAAA5555 DATA=AAAA'
    Command ('A' * 70) 'ERR LINE'
    Command 'READ' 'OK CTRL=AAAA5555 DATA=AAAA'
    Command 'MODE 00000000' 'OK MODE=00000000'
    Command 'MODE 5555AAAA' 'OK MODE=5555AAAA'
    Command 'WRITE A500' 'OK WRITE=A500'
    Command 'READ' 'OK CTRL=5555AAAA DATA=A5A5'
    Log 'TX SELFTEST'
    $serial.Write("SELFTEST`n")
    do {
        $response = Next-Line 10
        Write-Output ('RX ' + $response) 
    } while ($response.StartsWith('MISMATCH '))
    if ($response -cne 'OK SELFTEST 40/40 CTRL=00000000') {
        throw "SELFTEST failed: $response" 
    }
    $script:tests++
    Command 'READ' 'OK CTRL=00000000 DATA=7F7F'
    Log "GPIO_BOARD_PASS checks=$script:tests"
    @{CompletedAt = (Get-Date -Format o)
        Port      = $Port
        Passed    = $true
        Checks    = $script:tests
        Note      = 'Requires corresponding sbit/firmware manifest and human wiring record'
    } | ConvertTo-Json | Set-Content -LiteralPath ($Output + '.json')
}
catch {
    # A failure in an early READ must not leave manually selected outputs on.
    if ($serial.IsOpen) {
        try {
            $serial.Write("MODE 00000000`n")
            $cleanup = Next-Line 3
            Log ('CLEANUP ' + $cleanup) 
        }
        catch {
            Log ('CLEANUP_FAILED ' + $_.Exception.Message) 
        }
    }
    Log ('GPIO_BOARD_FAIL ' + $_.Exception.Message)
    @{CompletedAt = (Get-Date -Format o)
        Port      = $Port
        Passed    = $false
        Checks    = $script:tests
        Error     = $_.Exception.Message
    } | ConvertTo-Json | Set-Content -LiteralPath ($Output + '.json')
    throw
}
finally {
    $serial.Dispose() 
}
