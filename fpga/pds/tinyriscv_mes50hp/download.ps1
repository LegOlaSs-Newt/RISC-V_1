# 模块说明：download。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param(
    [Parameter(Mandatory = $true)][string]$Port,
    [string]$Binary = (Join-Path $PSScriptRoot 'build_submission_r01/hello.bin')
)
$ErrorActionPreference = 'Stop'
$file = Get-Item -LiteralPath $Binary
$firmware = [IO.File]::ReadAllBytes($file.FullName)
# The reference protocol always sends floor(size/128)+1 data packets.
# Reserve one packet of the 16 KiB memory for padding/loader boundary behavior.
if ($firmware.Length -eq 0 -or $firmware.Length -gt 16255) {
    throw 'This downloader accepts 1..16255 bytes for the 16 KiB reference ROM'
}
$serial = [IO.Ports.SerialPort]::new($Port, 115200, [IO.Ports.Parity]::None, 8, [IO.Ports.StopBits]::One)
$serial.ReadTimeout = 3000
$serial.WriteTimeout = 3000
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
function Send-Packet([byte]$Number, [byte[]]$Payload) {
    if ($Payload.Length -ne 128) {
        throw 'Internal packet length error' 
    }
    $packet = [byte[]]::new(131)
    $packet[0] = $Number
    [Array]::Copy($Payload, 0, $packet, 1, 128)
    $crcValue = 0xffff
    foreach ($value in $Payload) {
        $crcValue = $crcValue -bxor $value
        for ($bit = 0; $bit -lt 8; $bit++) {
            if ($crcValue -band 1) {
                $crcValue = ($crcValue -shr 1) -bxor 0xa001 
            }
            else {
                $crcValue = $crcValue -shr 1 
            }
        }
    }
    $packet[129] = $crcValue -band 255
    $packet[130] = ($crcValue -shr 8) -band 255
    $serial.Write($packet, 0, $packet.Length)
    try {
        $ack = $serial.ReadByte() 
    }
    catch [TimeoutException] {
        throw "Packet $Number timed out. Close the serial terminal and check LED2 is on (KEY2 download mode)." 
    }
    if ($ack -ne 6) {
        throw "Packet $Number rejected (response 0x$($ack.ToString('x2'))). Re-enter download mode before retrying." 
    }
    Write-Output "Packet $Number ACK"
}
try {
    $serial.Open()
    $serial.DiscardInBuffer()
    $header = [byte[]]::new(128)
    $name = [Text.Encoding]::ASCII.GetBytes($file.Name)
    [Array]::Copy($name, $header, [Math]::Min(60, $name.Length))
    $header[60] = ($firmware.Length -shr 24) -band 255
    $header[61] = ($firmware.Length -shr 16) -band 255
    $header[62] = ($firmware.Length -shr 8) -band 255
    $header[63] = $firmware.Length -band 255
    Send-Packet 0 $header
    $dataPacketCount = [int][Math]::Floor($firmware.Length / 128) + 1
    for ($packetIndex = 0; $packetIndex -lt $dataPacketCount; $packetIndex++) {
        $payload = [byte[]]::new(128)
        $offset = $packetIndex * 128
        $count = [Math]::Min(128, $firmware.Length - $offset)
        if ($count -gt 0) {
            [Array]::Copy($firmware, $offset, $payload, 0, $count) 
        }
        Send-Packet ([byte]($packetIndex + 1)) $payload
    }
    Write-Output 'All packets acknowledged. Press KEY2 to leave download mode and restart the CPU. Open the terminal at 115200 8N1; KEY1 repeats execution.'
}
finally {
    if ($serial.IsOpen) {
        $serial.Close() 
    }
    $serial.Dispose()
}
