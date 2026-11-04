# 模块说明：capture。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [Parameter(Mandatory = $true)][string]$Output,
    [ValidateRange(10, 600)][int]$TimeoutSeconds = 180,
    [string]$ReadyFile,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
if ((Test-Path -LiteralPath $outputPath) -and !$Force) {
    throw 'Log exists; choose a new Output or explicitly use -Force' 
}
New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
$serial = [IO.Ports.SerialPort]::new($Port, 115200, [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$writer = $null
$all = [Text.StringBuilder]::new()
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    $writer = [IO.StreamWriter]::new($outputPath, $false, [Text.Encoding]::ASCII)
    $writer.AutoFlush = $true
    if ($ReadyFile) {
        $readyPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReadyFile)
        if (Test-Path -LiteralPath $readyPath) {
            throw 'ReadyFile exists; choose a new path' 
        }
        [ordered]@{ ReadyAt = (Get-Date).ToString('o')
            Port            = $Port
            Output          = $outputPath
            ProcessId       = $PID 
        } |
            ConvertTo-Json | Set-Content -LiteralPath $readyPath -Encoding utf8
    }
    Write-Host "Listening on $Port, 115200 8N1. Now press KEY2 to leave download mode, or KEY1 to rerun."
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $chunk = $serial.ReadExisting()
        if ($chunk.Length -gt 0) {
            $writer.Write($chunk)
            [void]$all.Append($chunk)
            Write-Host -NoNewline $chunk
            if ($all.ToString() -match '(?m)^(COREMARK_FORMAL_VALID|COREMARK_CHECK_FAILED|COREMARK_SMOKE_CRC_PASS[^\r\n]*)\r?\n') {
                Write-Host "Saved UART log: $outputPath"
                return
            }
        }
        Start-Sleep -Milliseconds 20
    }
    throw "Capture timed out; partial UART log retained at $outputPath"
}
finally {
    if ($null -ne $writer) {
        $writer.Dispose() 
    }
    if ($serial.IsOpen) {
        $serial.Close() 
    }
    $serial.Dispose()
}
