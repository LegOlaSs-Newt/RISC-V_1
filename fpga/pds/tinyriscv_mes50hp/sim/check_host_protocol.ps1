# 模块说明：check_host_protocol。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
# Exercise the actual host packet function against a mock serial endpoint.
# Does not open a COM port or communicate with hardware.
$ErrorActionPreference = 'Stop'
$sourcePath = Join-Path $PSScriptRoot '../download.ps1'
$tokens = $null
$parseErrors = $null
$tree = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) {
    throw 'Downloader parse error' 
}
$functionNode = $tree.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Send-Packet' }, $true)
if (!$functionNode) {
    throw 'Actual Send-Packet function not found' 
}
Invoke-Expression $functionNode.Extent.Text
$serial = [pscustomobject]@{Packet = [byte[]]@()
    Response                       = 6
}
$serial | Add-Member ScriptMethod Write {
    param([byte[]]$Data, [int]$Offset, [int]$Count)
    $this.Packet = [byte[]]$Data[$Offset..($Offset + $Count - 1)]
}
$serial | Add-Member ScriptMethod ReadByte { return $this.Response }
$payload = [byte[]](0..127)
Send-Packet 7 $payload
if ($serial.Packet.Length -ne 131 -or $serial.Packet[0] -ne 7) {
    throw 'Packet framing differs' 
}
for ($i = 0; $i -lt 128; $i++) {
    if ($serial.Packet[$i + 1] -ne $payload[$i]) {
        throw 'Payload differs' 
    } 
}
# 0x02da comes from the supplied reference downloader's calc_crc16(range(128)).
if ($serial.Packet[129] -ne 0xda -or $serial.Packet[130] -ne 0x02) {
    throw 'Reference CRC16 differs' 
}
$serial.Response = 0x15
$rejected = $false
try {
    Send-Packet 8 $payload 
}
catch {
    $rejected = $true 
}
if (!$rejected) {
    throw 'NAK response was silently accepted' 
}
Write-Output 'HOST_PROTOCOL_PASS: packet length/order, reference CRC16 and NAK handling'
