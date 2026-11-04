# 模块说明：build。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([Parameter(Mandatory = $true)][string]$OutputRoot, [string]$GccBin = '', [int]$ClockHz = 27000000)
$ErrorActionPreference = 'Stop'
$boardRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../..")
$repo = [IO.Path]::GetFullPath("$boardRoot/../../..")
if (!$GccBin -and $env:RISCV_GCC_BIN) {
    $GccBin = $env:RISCV_GCC_BIN 
}
if (!$GccBin) {
    $GccBin = "$repo/xpacks/@xpack-dev-tools/riscv-none-elf-gcc/.content/bin"
}
$out = [IO.Path]::GetFullPath($OutputRoot)
if (Test-Path -LiteralPath $out) {
    throw 'Use a new cache-probe output directory'
}
New-Item -ItemType Directory -Path "$out/source" -Force | Out-Null
$divider = [int][Math]::Round($ClockHz / 115200.0) - 1
$sources = @("$boardRoot/sw/start.S", "$PSScriptRoot/main.c", "$PSScriptRoot/measure.S")
$flags = @('-march=rv32im_zicsr', '-mabi=ilp32', '-O2', '-ffreestanding', '-nostdlib', '-fno-builtin', '-msmall-data-limit=0', '-mno-relax', '-fno-pic', '-fno-stack-protector', '-ffixed-s10', '-ffixed-s11', "-DUART_DIVIDER=$divider", '-Wl,--no-relax', "-Wl,-Map,$out/probe.map")
& "$GccBin/riscv-none-elf-gcc.exe" @flags -T "$boardRoot/sw/link.ld" @sources -o "$out/probe.elf"
if ($LASTEXITCODE -ne 0) {
    throw 'Cache probe compilation failed'
}
& "$GccBin/riscv-none-elf-objcopy.exe" -O binary "$out/probe.elf" "$out/probe.bin"
if ($LASTEXITCODE -ne 0) {
    throw 'Cache probe binary conversion failed'
}
& "$GccBin/riscv-none-elf-objdump.exe" -d -M 'numeric,no-aliases' "$out/probe.elf" | Set-Content -LiteralPath "$out/probe.dis"
if ($LASTEXITCODE -ne 0) {
    throw 'Cache probe disassembly failed'
}
& "$GccBin/riscv-none-elf-nm.exe" -n "$out/probe.elf" | Set-Content -LiteralPath "$out/symbols.txt"
if ($LASTEXITCODE -ne 0) {
    throw 'Cache probe symbols failed'
}
$bytes = [IO.File]::ReadAllBytes("$out/probe.bin")
if (!$bytes.Length -or $bytes.Length -gt 16255) {
    throw 'Cache probe does not fit the UART program image'
}
$padded = [byte[]]::new(16384)
[Array]::Copy($bytes, $padded, $bytes.Length)
[IO.File]::WriteAllLines("$out/probe.mem", [string[]]@(for ($i = 0; $i -lt 16384; $i += 4) {
            [BitConverter]::ToUInt32($padded, $i).ToString('x8')
        }))
[IO.File]::WriteAllLines("$out/probe.bytes", [string[]]@($bytes | ForEach-Object { $_.ToString('x2') }))
$inputs = @($sources) + @("$boardRoot/sw/link.ld", "$boardRoot/sw/include/memory_stats.h", $PSCommandPath)
$inputs | ForEach-Object { Copy-Item -LiteralPath $_ -Destination "$out/source" }
[ordered]@{CreatedAt = (Get-Date -Format o)
    ClockHz          = $ClockHz
    UartDivider      = $divider
    Bytes            = $bytes.Length
    Flags            = $flags
    BinarySHA256     = (Get-FileHash -LiteralPath "$out/probe.bin").Hash
    Compiler         = (& "$GccBin/riscv-none-elf-gcc.exe" --version | Select-Object -First 1)
    Sources          = @($inputs | ForEach-Object { @{Path = $_; SHA256 = (Get-FileHash -LiteralPath $_).Hash } })
    Scope            = 'Independent cache workload and 64-bit telemetry; not CoreMark'
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$out/build_manifest.json"
Write-Output "Cache probe: $($bytes.Length) bytes; $out/probe.bin"
