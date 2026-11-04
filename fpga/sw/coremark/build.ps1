# 模块说明：build。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param(
    [ValidateSet('Smoke', 'Formal')][string]$Profile = 'Smoke',
    [ValidateSet('Performance', 'Validation')][string]$RunType = 'Performance',
    [ValidateRange(-1, 100000000)][int]$Iterations = -1,
    [ValidateSet('O2', 'Os')][string]$Optimization = 'O2',
    [int]$ClockHz = 0,
    [string]$OutputRoot = '',
    [string]$GccBin = ''
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. "$projectRoot/tools/environment.ps1"
$gccBin = Resolve-RiscVGccBin -Requested $GccBin -SubmissionRoot $projectRoot
$gcc = Join-Path $gccBin 'riscv-none-elf-gcc.exe'
if ($Iterations -eq -1) {
    $Iterations = if ($Profile -eq 'Smoke') {
        1 
    }
    else {
        0 
    } 
}
if ($Profile -eq 'Smoke' -and ($Iterations -lt 1 -or $Iterations -gt 10)) {
    throw 'Smoke uses 1..10 iterations; default is 1' 
}
if ($ClockHz -eq 0) {
    $config = [IO.File]::ReadAllText("$projectRoot/pds/tinyriscv_mes50hp/rtl/mes50hp_config.vh")
    if ($config -notmatch 'MES50HP_CPU_HZ\s+(\d+)') {
        throw 'Board clock definition missing' 
    }
    $ClockHz = [int]$Matches[1]
}
if ($ClockHz -le 0) {
    throw 'ClockHz must be positive' 
}
$outDir = if ($OutputRoot) {
    [IO.Path]::GetFullPath($OutputRoot) 
}
else {
    Join-Path $projectRoot "work/coremark/Firmware/$Profile/$RunType" 
}
if ($OutputRoot -and (Test-Path -LiteralPath $outDir)) {
    throw 'Use a new OutputRoot to preserve existing firmware evidence' 
}
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$upstream = Join-Path $PSScriptRoot 'upstream'
$kernelNames = @('core_list_join.c', 'core_main.c', 'core_matrix.c', 'core_state.c', 'core_util.c', 'coremark.h')
$sourceRecord = Get-Content -LiteralPath "$PSScriptRoot/SOURCE.json" -Raw | ConvertFrom-Json
foreach ($record in $sourceRecord.Files) {
    if ((Get-FileHash -LiteralPath "$upstream/$($record.File)" -Algorithm SHA256).Hash -ine $record.SHA256) {
        throw "CoreMark immutable source changed: $($record.File)"
    }
}
$sources = @($kernelNames | Where-Object { $_ -like '*.c' } | ForEach-Object { "$upstream/$_" })
$sources += @("$PSScriptRoot/port/core_portme.c", "$PSScriptRoot/port/core_portme_io.c")
$smoke = if ($Profile -eq 'Smoke') {
    1 
}
else {
    0 
}
$typeFlag = if ($RunType -eq 'Performance') {
    '-DPERFORMANCE_RUN=1' 
}
else {
    '-DVALIDATION_RUN=1' 
}
$common = @('-march=rv32im_zicsr', '-mabi=ilp32', "-$Optimization", '-g', '-ffreestanding', '-nostdlib', '-fno-builtin', '-fno-pic', '-fno-stack-protector', '-ffixed-s10', '-ffixed-s11', '-mno-relax', '-fno-common', '-ffunction-sections', '-fdata-sections', "-DITERATIONS=$Iterations", '-DTOTAL_DATA_SIZE=2000', $typeFlag)
$versionLines = @(& $gcc --version)
if ($LASTEXITCODE -ne 0) {
    throw 'GCC unavailable' 
}
$version = $versionLines[0].Trim()
$portHashes = @(@('port/core_portme.h', 'port/core_portme.c', 'port/core_portme_io.c', 'link.ld') | ForEach-Object {
        [ordered]@{File = $_; SHA256 = (Get-FileHash -LiteralPath "$PSScriptRoot/$_" -Algorithm SHA256).Hash }
    })
$startupHash = (Get-FileHash -LiteralPath "$projectRoot/pds/tinyriscv_mes50hp/sw/start.S" -Algorithm SHA256).Hash
$sourceFingerprint = (@($sourceRecord.Files.SHA256) + @($portHashes.SHA256) + @($startupHash)) -join '|'
$idInput = "$Profile|$RunType|$Iterations|$ClockHz|$version|$($common -join ' ')|$sourceFingerprint"
# Use APIs shared by Windows PowerShell 5.1 and PowerShell 7.
$sha256 = [Security.Cryptography.SHA256]::Create()
try {
    $idBytes = $sha256.ComputeHash([Text.Encoding]::UTF8.GetBytes($idInput))
    $id = ([BitConverter]::ToString($idBytes)).Replace('-', '').Substring(0, 12).ToLowerInvariant()
}
finally {
    $sha256.Dispose()
}
$escapedFlags = ($common -join ' ').Replace('\', '\\').Replace('"', '\"')
$divider = [int][Math]::Round($ClockHz / 115200.0) - 1
$header = @(
    "#define COREMARK_CPU_HZ ${ClockHz}u", "#define COREMARK_UART_DIV ${divider}u",
    "#define COREMARK_SMOKE $smoke", "#define COREMARK_PROFILE `"$Profile`"",
    "#define COREMARK_RUN_NAME `"$RunType`"", "#define COREMARK_BUILD_ID `"$id`"",
    "#define COMPILER_FLAGS `"$escapedFlags`""
)
[IO.File]::WriteAllLines("$outDir/build_config.h", $header, [Text.Encoding]::ASCII)
$elf = "$outDir/coremark.elf"
$linkFlags = @('-Wl,--no-relax', '-Wl,--gc-sections', "-Wl,-Map,$outDir/coremark.map", '-T', "$PSScriptRoot/link.ld")
& $gcc @common "-I$PSScriptRoot/port" "-I$upstream" "-I$outDir" @linkFlags "$projectRoot/pds/tinyriscv_mes50hp/sw/start.S" @sources -lgcc -o $elf
if ($LASTEXITCODE -ne 0) {
    throw 'CoreMark compilation/link failed; ROM/RAM limits are enforced' 
}
& "$gccBin/riscv-none-elf-objcopy.exe" -O binary $elf "$outDir/coremark.bin"
if ($LASTEXITCODE -ne 0) {
    throw 'CoreMark objcopy failed' 
}
& "$gccBin/riscv-none-elf-objdump.exe" -d -M 'numeric,no-aliases' $elf | Set-Content -LiteralPath "$outDir/coremark.dis"
if ($LASTEXITCODE -ne 0) {
    throw 'CoreMark disassembly failed' 
}
& "$gccBin/riscv-none-elf-objdump.exe" -d -M no-aliases $elf | Set-Content -LiteralPath "$outDir/coremark.abi.dis"
if ($LASTEXITCODE -ne 0) {
    throw 'CoreMark ABI disassembly failed' 
}
& "$gccBin/riscv-none-elf-size.exe" -A $elf | Set-Content -LiteralPath "$outDir/sections.txt"
$binary = Get-Item -LiteralPath "$outDir/coremark.bin"
if ($binary.Length -gt 16255) {
    throw 'CoreMark image exceeds the UART loader limit 16255 bytes' 
}
$manifest = [ordered]@{
    CreatedAt      = (Get-Date -Format o)
    Benchmark      = 'CoreMark 1.0'
    UpstreamTag    = 'v1.01'
    UpstreamCommit = 'cfa9ab377835911f23d9b0831c7be302ed1f58de'

    BuildId        = $id
    Profile        = $Profile
    RunType        = $RunType
    Iterations     = $Iterations
    ClockHz        = $ClockHz
    UartDivider    = $divider

    Compiler       = $version
    CompilerFlags  = $common
    LinkerFlags    = $linkFlags
    TotalDataSize  = 2000
    HasFloat       = 0

    Memory         = '16KiB ROM + 16KiB RAM, static work area, >=4KiB stack reserve'

    BinaryBytes    = $binary.Length
    BinarySHA256   = (Get-FileHash -LiteralPath $binary.FullName -Algorithm SHA256).Hash

    SourceHashes   = @($sourceRecord.Files)
    PortHashes     = $portHashes
    StartupSHA256  = $startupHash
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$outDir/build_manifest.json" -Encoding utf8
Write-Output "CoreMark $Profile/$RunType iterations=$Iterations clock=$ClockHz Hz: $($binary.Length) bytes"
Write-Output "Firmware: $outDir/coremark.bin"
Write-Output 'HAS_FLOAT=0: the official integer time display is truncated; preserve 64-bit raw cycle fields for host calculation.'
