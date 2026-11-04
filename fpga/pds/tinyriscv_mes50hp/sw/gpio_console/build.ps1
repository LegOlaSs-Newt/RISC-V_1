# 模块说明：build。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([string]$GccBin = '', [int]$ClockHz = 27000000, [string]$OutputRoot = '')
$ErrorActionPreference = 'Stop'
$boardRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../..")
$projectRoot = [IO.Path]::GetFullPath("$boardRoot/../../..")
if (!$GccBin -and $env:RISCV_GCC_BIN) {
    $GccBin = $env:RISCV_GCC_BIN 
}
if (!$GccBin) {
    $GccBin = "$projectRoot/xpacks/@xpack-dev-tools/riscv-none-elf-gcc/.content/bin" 
}
$out = "$boardRoot/build_r04/gpio_console"
if ($OutputRoot) {
    $out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputRoot)
    if (Test-Path -LiteralPath $out) {
        throw 'OutputRoot exists; choose a new directory to preserve evidence' 
    }
}
New-Item -ItemType Directory -Force -Path $out | Out-Null
$divider = [int][Math]::Round($ClockHz / 115200.0) - 1
function Check([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed: $LASTEXITCODE" 
    } 
}
$flags = @('-march=rv32im_zicsr', '-mabi=ilp32', '-O2', '-ffreestanding', '-nostdlib', '-msmall-data-limit=0', '-mno-relax', '-fno-pic', '-fno-stack-protector', '-ffixed-s10', '-ffixed-s11', "-DUART_DIVIDER=$divider", '-Wl,--no-relax', "-Wl,-Map,$out/console.map")
& "$GccBin/riscv-none-elf-gcc.exe" @flags -T "$boardRoot/sw/link.ld" "$boardRoot/sw/start.S" "$PSScriptRoot/main.c" -o "$out/console.elf"
Check 'GCC'
& "$GccBin/riscv-none-elf-objcopy.exe" -O binary "$out/console.elf" "$out/console.bin"
Check 'objcopy'
& "$GccBin/riscv-none-elf-objdump.exe" -d -M 'numeric,no-aliases' "$out/console.elf" | Set-Content -LiteralPath "$out/console.dis"
Check 'objdump'
$bytes = [IO.File]::ReadAllBytes("$out/console.bin")
if ($bytes.Length -eq 0 -or $bytes.Length -gt 16255) {
    throw 'UART image must contain 1..16255 bytes' 
}
[IO.File]::WriteAllLines("$out/console.bytes", [string[]]@($bytes | ForEach-Object { $_.ToString('x2') }))
$padded = [byte[]]::new(16384)
[Array]::Copy($bytes, $padded, $bytes.Length)
[IO.File]::WriteAllLines("$out/console.mem", [string[]]@(for ($i = 0; $i -lt 16384; $i += 4) {
            [BitConverter]::ToUInt32($padded, $i).ToString('x8') 
        }))
$sources = @("$PSScriptRoot/main.c", "$PSScriptRoot/build.ps1", "$boardRoot/sw/start.S", "$boardRoot/sw/link.ld")
[ordered]@{CreatedAt = (Get-Date -Format o)
    ClockHz          = $ClockHz
    UartDivider      = $divider
    Flags            = $flags
    Bytes            = $bytes.Length
    BinarySHA256     = (Get-FileHash -LiteralPath "$out/console.bin").Hash
    Compiler         = (& "$GccBin/riscv-none-elf-gcc.exe" --version | Select-Object -First 1)
    Sources          = @($sources | ForEach-Object { @{Path = $_; SHA256 = (Get-FileHash -LiteralPath $_).Hash } })
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$out/build_manifest.json" -Encoding utf8
Write-Output "GPIO console: $($bytes.Length) bytes, $out/console.bin"
