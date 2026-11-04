# 模块说明：build_rom_probe。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([string]$OutputRoot = '', [string]$GccBin = '')
$ErrorActionPreference = 'Stop'
$boardRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../..")
$projectRoot = [IO.Path]::GetFullPath("$boardRoot/../../..")
if (!$GccBin -and $env:RISCV_GCC_BIN) {
    $GccBin = $env:RISCV_GCC_BIN 
}
if (!$GccBin) {
    $GccBin = "$projectRoot/xpacks/@xpack-dev-tools/riscv-none-elf-gcc/.content/bin" 
}
$config = [IO.File]::ReadAllText("$boardRoot/rtl/mes50hp_config.vh")
if ($config -notmatch 'MES50HP_CPU_HZ\s+27000000\b' -or $config -notmatch 'MES50HP_UART_DIV\s+233\b') {
    throw 'This ROM diagnostic requires the verified 27MHz / UART divider233 configuration.' 
}
if (!$OutputRoot) {
    $OutputRoot = "$boardRoot/build_r04/rom_probe" 
}
$OutputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
# The tiny assembly has fixed bounds for the preserved 732-byte V2 image.
$header = [IO.File]::ReadAllText("$boardRoot/rtl/boot_image_path.vh")
if ($header -notmatch 'MES50HP_BOOT_MEM\s+"([^"]+)"') {
    throw 'Cannot resolve the active boot image' 
}
$bootPath = $Matches[1]
if ((Get-Item -LiteralPath (Join-Path (Split-Path -Parent $bootPath) 'hello.bin')).Length -ne 732) {
    throw 'ROM probe bounds require the preserved 732-byte image; update and revalidate the diagnostic for another image.' 
}
Copy-Item -LiteralPath $bootPath -Destination "$OutputRoot/boot_before.mem" -Force
$flags = @('-march=rv32im_zicsr', '-mabi=ilp32', '-nostdlib', '-mno-relax', '-Wl,--no-relax')
& "$GccBin/riscv-none-elf-gcc.exe" @flags -T "$boardRoot/../../third_party/tinyriscv/tests/isa/link.ld" "$PSScriptRoot/rom_boot_probe.S" -o "$OutputRoot/probe.elf"
if ($LASTEXITCODE -ne 0) {
    throw 'Probe assembly failed' 
}
& "$GccBin/riscv-none-elf-objcopy.exe" -O binary "$OutputRoot/probe.elf" "$OutputRoot/probe.bin"
if ($LASTEXITCODE -ne 0) {
    throw 'Probe objcopy failed' 
}
& "$GccBin/riscv-none-elf-objdump.exe" -d -M 'numeric,no-aliases' "$OutputRoot/probe.elf" | Set-Content -LiteralPath "$OutputRoot/probe.dis"
if ($LASTEXITCODE -ne 0) {
    throw 'Probe objdump failed' 
}
$bytes = [IO.File]::ReadAllBytes("$OutputRoot/probe.bin")
$loaderBytes = ([int][Math]::Floor($bytes.Length / 128) + 1) * 128
if ($bytes.Length -eq 0 -or $loaderBytes -gt 256) {
    throw 'Probe would overwrite the measured ROM range' 
}
[IO.File]::WriteAllLines("$OutputRoot/probe.bytes", [string[]]@($bytes | ForEach-Object { $_.ToString('x2') }))
[ordered]@{CreatedAt   = (Get-Date -Format o)
    ClockHz            = 27000000
    Flags              = $flags
    BinaryBytes        = $bytes.Length
    LoaderWrittenBytes = $loaderBytes
    DumpFirstAddress   = 256
    DumpEndExclusive   = 732
    DumpWords          = 119
    BinarySHA256       = (Get-FileHash -LiteralPath "$OutputRoot/probe.bin").Hash
    SourceSHA256       = (Get-FileHash -LiteralPath "$PSScriptRoot/rom_boot_probe.S").Hash
    BootImagePath      = $bootPath
    BootImageSHA256    = (Get-FileHash -LiteralPath $bootPath).Hash
    Scope              = 'Diagnostic only; does not observe the overwritten first 256 ROM bytes'
} | ConvertTo-Json | Set-Content -LiteralPath "$OutputRoot/probe_manifest.json" -Encoding utf8
Write-Output "ROM probe $($bytes.Length) bytes; UART writes $loaderBytes bytes; dumps 119 untouched words from 0x100"
