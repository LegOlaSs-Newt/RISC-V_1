# 模块说明：configure_sram。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
#requires -Version 7.0
param(
    [Parameter(Mandatory = $true)][string]$Bitstream,
    [string]$OutputRoot = '',
    [string]$PdsRoot = 'D:/pango/PDS_2022.2-SP6.4',
    [string]$JtagHost = '127.0.0.1',
    [ValidateRange(1, 65535)][int]$JtagPort = 65420,
    [switch]$PrepareOnly
)
# PGL50H single-device SRAM configuration. Run only after the documented
# human board/wiring/voltage checks. This does not write configuration Flash.
$ErrorActionPreference = 'Stop'
function TclPath([string]$Path) {
    if ($Path -match '[{}\r\n]') {
        throw 'Braces and newlines in Tcl paths are unsupported' 
    }
    return '{' + $Path.Replace('\', '/') + '}'
}
function RunCfg([string[]]$Lines, [string]$Name) {
    $tcl = "$OutputRoot/$Name.tcl"
    $log = "$OutputRoot/$Name.log"
    [IO.File]::WriteAllLines($tcl, $Lines)
    $Lines | & $cfgExe 2>&1 | Out-File -LiteralPath $log -Encoding utf8
    $code = $LASTEXITCODE
    $text = [IO.File]::ReadAllText($log)
    if ($code -ne 0 -or $text -match '(?m)(?:^|>)E:') {
        throw "Configuration tool failed; inspect $log" 
    }
    return $text
}
$cfgExe = Join-Path $PdsRoot 'bin/cdt_cfg_shell.exe'
if (!(Test-Path -LiteralPath $cfgExe)) {
    throw 'PDS configuration shell not found' 
}
if ($JtagHost -notmatch '^[A-Za-z0-9.-]+$') {
    throw 'Invalid JTAG host' 
}
$inputPath = (Get-Item -LiteralPath $Bitstream).FullName
if ([IO.Path]::GetExtension($inputPath) -ine '.sbit') {
    throw 'Use a PDS SRAM .sbit, not a CPU .bin or Flash image' 
}
$bytes = [IO.File]::ReadAllBytes($inputPath)
if ($bytes.Length -lt 512 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 512) -notmatch 'Logos-PGL50H--6-FBG484') {
    throw 'Expected PGL50H -6 FBG484 bitstream header' 
}
if (!$OutputRoot) {
    $OutputRoot = "$PSScriptRoot/build/configuration_$(Get-Date -Format yyyyMMdd_HHmmss_fff)" 
}
$OutputRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)
if (Test-Path -LiteralPath $OutputRoot) {
    throw 'Preserve the existing record; choose a new OutputRoot' 
}
New-Item -ItemType Directory -Path $OutputRoot | Out-Null
$savedBit = "$OutputRoot/image.sbit"
[IO.File]::WriteAllBytes($savedBit, $bytes)
$mask = [IO.Path]::ChangeExtension($inputPath, '.smsk')
if (Test-Path -LiteralPath $mask) {
    Copy-Item -LiteralPath $mask -Destination "$OutputRoot/image.smsk" 
}
$svf = "$OutputRoot/configure.svf"
# Explicit CRAM mode (bits17:16=00), 1MHz (bits19:18=01), header/SEC flags.
# The default generic SVF mode targets embedded Flash and can yield an empty
# output for this Logos part; always select the documented CRAM mode explicitly.
$null = RunCfg @(
    ('cfg_add_device -file ' + (TclPath $savedBit)),
    ('cfg_one_step_create_svf -sbit ' + (TclPath $savedBit) + ' -svf_file_name ' + (TclPath $svf) + ' -svf_property 4000e -device_index 0 -jtag_chain 0 -not_create_pef true'),
    'exit'
) 'prepare'
if (!(Test-Path -LiteralPath $svf) -or (Get-Item -LiteralPath $svf).Length -eq 0) {
    throw 'SVF is missing/empty; nothing was sent to the board' 
}
$svfText = [IO.File]::ReadAllText($svf)
$instructions = @([regex]::Matches($svfText, '(?m)^SIR\s+(\d+)\s+TDI\s*\(([0-9A-Fa-f]+)\);') | ForEach-Object { $_.Groups[1].Value + ':' + $_.Groups[2].Value.ToUpperInvariant() })
if (($instructions -join ',') -ne '10:283,10:28A,10:28B,10:28D,10:3FF,10:159') {
    throw 'Unexpected generated SVF instruction sequence; no board configuration attempted' 
}
$payloadBits = [long]$bytes.Length * 8
$match = [regex]::Match($svfText, 'SDR\s+' + $payloadBits + '\s+TDI\s*\(([0-9A-Fa-f\s]+)\)')
if (!$match.Success) {
    throw 'SVF does not contain the complete selected bitstream' 
}
$hex = [regex]::Replace($match.Groups[1].Value, '\s+', '')
if (!('TinyRiscvSvfAudit' -as [type])) {
    Add-Type -TypeDefinition @'
public static class TinyRiscvSvfAudit {
    static int Hex(char c) { return c <= '9' ? c-'0' : (c & ~32)-'A'+10; }
    public static bool Matches(string hex, byte[] data) {
        if(hex.Length != data.Length*2) return false;
        for(int i=0;i<data.Length;i++) {
            int x=data[data.Length-1-i], reversed=0;
            for(int b=0;b<8;b++) { reversed=(reversed<<1)|(x&1); x>>=1; }
            if(((Hex(hex[i*2])<<4)|Hex(hex[i*2+1])) != reversed) return false;
        }
        return true;
    }
}
'@
}
if (![TinyRiscvSvfAudit]::Matches($hex, $bytes)) {
    throw 'SVF payload differs from selected sbit; no board configuration attempted' 
}
$manifest = [ordered]@{
    CreatedAt               = (Get-Date -Format o)
    SourceBitstream         = $inputPath

    BitstreamSHA256         = (Get-FileHash -LiteralPath $savedBit).Hash

    SVFSHA256               = (Get-FileHash -LiteralPath $svf).Hash
    PayloadBits             = $payloadBits

    PayloadMatchesBitstream = $true
    Instructions            = $instructions
    JtagClockHz             = 1000000

    Method                  = 'PDS-generated CRAM SVF; JRST, CFGI, JWAKEUP'
    Status                  = 'Prepared'

    ConfigurationPassed     = $false
    SoftwareBootVerified    = $false

    Note                    = 'Board/wiring verification, matching timing report and UART boot evidence are separate requirements'
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$OutputRoot/manifest.json" -Encoding utf8
Write-Output "SVF_PREPARED SHA256=$($manifest.BitstreamSHA256); payload checked; $OutputRoot"
if ($PrepareOnly) {
    return 
}
$log = RunCfg @(
    "cfg_connect -ip $JtagHost -port $JtagPort",
    'cfg_scan_chain',
    ('cfg_assign_file -file ' + (TclPath $savedBit) + ' -device_index 0'),
    ('cfg_execute_svf -svf_file_name ' + (TclPath $svf) + ' -device_index 0'),
    'cfg_read_device_property -device_index 0 -mode 3',
    'cfg_disconnect',
    'exit'
) 'configure'
$statusMatch = [regex]::Matches($log, '(?i)Status Register:\s*0x([0-9a-f]+)')
if (!$log.Contains('COMMAND[SVF Run] execute successfully') -or $statusMatch.Count -eq 0) {
    throw 'SVF execution/status completion evidence missing' 
}
$status = [Convert]::ToUInt32($statusMatch[$statusMatch.Count - 1].Groups[1].Value, 16)
$required = (1 -shl 10) -bor (1 -shl 12) -bor (1 -shl 17) -bor (1 -shl 18) -bor (1 -shl 19)
$manifest.StatusRegister = '0x' + $status.ToString('X8')
$manifest.CompletedAt = Get-Date -Format o
$manifest.ConfigurationPassed = (($status -band $required) -eq $required -and ($status -band 7) -eq 0)
$manifest.Status = if ($manifest.ConfigurationPassed) {
    'Configured; UART boot still needs checking' 
}
else {
    'Configuration state failed; stop and preserve log' 
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$OutputRoot/manifest.json" -Encoding utf8
if (!$manifest.ConfigurationPassed) {
    throw "Configuration state failed: $($manifest.StatusRegister); do not continue trial writes" 
}
Write-Output "CONFIGURATION_PASS $($manifest.StatusRegister); open UART/check software boot; $OutputRoot"
