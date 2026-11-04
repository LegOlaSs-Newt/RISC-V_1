# 模块说明：capture_v2。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param(
    [string]$Port = 'COM7',
    [Parameter(Mandatory = $true)][string]$Output,
    [ValidateRange(10, 600)][int]$TimeoutSeconds = 180,
    [string]$ReadyFile = ''
)
# Passive board diagnostic: opens UART before configuration/reset release.
# It never transmits, changes GPIO, configures FPGA, or writes Flash.
$ErrorActionPreference = 'Stop'
$outPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
foreach ($path in @($outPath, "$outPath.bin", "$outPath.json")) {
    if (Test-Path -LiteralPath $path) {
        throw "Existing capture must be preserved: $path" 
    }
}
New-Item -ItemType Directory -Path (Split-Path -Parent $outPath) -Force | Out-Null
$serial = [IO.Ports.SerialPort]::new($Port, 115200, [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$raw = [IO.MemoryStream]::new()
$all = [Text.StringBuilder]::new()
$passed = $false
$opened = $null
$need = @('TinyRISC-V UART DEMO V2', 'factorial(6)=720 PASS', 'LED3/LED4 alternate every 250 ms', 'V2 alive')
$orderedStartup = 'TinyRISC-V UART DEMO V2\r?\nfactorial\(6\)=720 PASS\r?\nLED3/LED4 alternate every 250 ms\r?\nV2 alive\r?\n'
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    $opened = Get-Date -Format o
    if ($ReadyFile) {
        $readyPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReadyFile)
        if (Test-Path -LiteralPath $readyPath) {
            throw 'ReadyFile already exists; use a new capture record' 
        }
        [ordered]@{Port = $Port
            OpenedAt    = $opened
            ProcessId   = $PID
        } | ConvertTo-Json | Set-Content -LiteralPath $readyPath -Encoding utf8
    }
    Write-Host "Listening passively on $Port, 115200 8N1. Waiting for complete V2 startup."
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $buf = [byte[]]::new(4096)
    while ([DateTime]::UtcNow -lt $deadline) {
        $count = $serial.BytesToRead
        if ($count -gt 0) {
            $n = $serial.Read($buf, 0, [Math]::Min($buf.Length, $count))
            $raw.Write($buf, 0, $n)
            $chunk = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
            [void]$all.Append($chunk)
            # Keep NUL bytes visible without confusing a terminal; .bin is exact.
            Write-Host -NoNewline $chunk.Replace([string][char]0, '<NUL>')
            [IO.File]::WriteAllText($outPath, $all.ToString(), [Text.Encoding]::ASCII)
            $text = $all.ToString()
            # A previous run's "V2 alive" must not satisfy the post-reset heartbeat.
            if ($text -match $orderedStartup) {
                $passed = $true
                break 
            }
        }
        Start-Sleep -Milliseconds 20
    }
}
finally {
    if ($serial.IsOpen) {
        $serial.Close() 
    }
    $serial.Dispose()
    [IO.File]::WriteAllBytes("$outPath.bin", $raw.ToArray())
    [IO.File]::WriteAllText($outPath, $all.ToString(), [Text.Encoding]::ASCII)
    $raw.Dispose()
    [ordered]@{Port      = $Port
        Baud             = 115200
        OpenedAt         = $opened
        CompletedAt      = (Get-Date -Format o)
        Passed           = $passed
        RequiredText     = $need
        Check            = 'Ordered startup with heartbeat after banner'
        ReceivedBytes    = (Get-Item -LiteralPath "$outPath.bin").Length
        TransmittedBytes = 0
        Scope            = 'UART only; pair with configuration/reset and hardware identity records'
    } | ConvertTo-Json | Set-Content -LiteralPath "$outPath.json" -Encoding utf8
}
if (!$passed) {
    throw "V2 startup not verified; partial capture retained at $outPath" 
}
Write-Host "V2_BOARD_BOOT_PASS $outPath"
