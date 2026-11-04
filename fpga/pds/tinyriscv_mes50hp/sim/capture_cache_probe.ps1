# 模块说明：capture_cache_probe。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([string]$Port = 'COM7', [Parameter(Mandatory = $true)][string]$Output, [string]$ReadyFile = '',
    [ValidateRange(10, 600)][int]$TimeoutSeconds = 180)
$ErrorActionPreference = 'Stop'
$out = [IO.Path]::GetFullPath($Output)
foreach ($path in @($out, "$out.bin", "$out.json")) {
    if (Test-Path -LiteralPath $path) {
        throw 'Preserve previous capture'
    }
}
New-Item -ItemType Directory -Path (Split-Path -Parent $out) -Force | Out-Null
$serial = [IO.Ports.SerialPort]::new($Port, 115200, [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$raw = [IO.MemoryStream]::new()
$all = [Text.StringBuilder]::new()
$passed = $false
$opened = $null
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    $opened = Get-Date -Format o
    if ($ReadyFile) {
        if (Test-Path -LiteralPath $ReadyFile) {
            throw 'ReadyFile exists'
        }
        [ordered]@{Port = $Port
            OpenedAt    = $opened
            ProcessId   = $PID
        } | ConvertTo-Json | Set-Content -LiteralPath $ReadyFile
    }
    Write-Host "Listening for V3 cache probe on $Port"
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $buffer = [byte[]]::new(4096)
    while ([DateTime]::UtcNow -lt $deadline) {
        $count = $serial.BytesToRead
        if ($count) {
            $n = $serial.Read($buffer, 0, [Math]::Min($buffer.Length, $count))
            $raw.Write($buffer, 0, $n)
            $chunk = [Text.Encoding]::ASCII.GetString($buffer, 0, $n)
            [void]$all.Append($chunk)
            [IO.File]::WriteAllText($out, $all.ToString(), [Text.Encoding]::ASCII)
            if ($all.ToString() -match '(?m)^V3_CACHE_PROBE_(PASS|FAIL)\r?\n') {
                $passed = $Matches[1] -eq 'PASS'
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
    [IO.File]::WriteAllBytes("$out.bin", $raw.ToArray())
    $raw.Dispose()
    [IO.File]::WriteAllText($out, $all.ToString(), [Text.Encoding]::ASCII)
    [ordered]@{OpenedAt  = $opened
        CompletedAt      = (Get-Date -Format o)
        Port             = $Port
        Baud             = 115200
        Passed           = $passed
        ReceivedBytes    = (Get-Item -LiteralPath "$out.bin").Length
        TransmittedBytes = 0
        Scope            = 'UART marker only; workload analysis and hardware pairing are separate'
    } | ConvertTo-Json | Set-Content -LiteralPath "$out.json"
}
if (!$passed) {
    throw "Cache probe missing PASS; preserve $out"
}
Write-Host "CACHE_PROBE_UART_PASS $out"
