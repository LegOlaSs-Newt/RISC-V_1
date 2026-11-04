# 模块说明：build。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param(
    [ValidateSet('Software', 'Sim', 'Compile', 'Synthesize', 'Bitstream')]
    [string]$Stage = 'Sim',
    [ValidateSet(27, 50)][int]$ClockMHz = 27,
    [ValidateSet('On', 'Off')][string]$BranchPrediction = 'On',
    [ValidateSet('Legacy', 'Wait')][string]$MemorySystem = 'Wait',
    [ValidateSet('On', 'Off')][string]$Cache = 'On',
    [ValidateSet('On', 'Off')][string]$EarlyLookup = 'On',
    [string]$PdsRoot = 'D:\pango\PDS_2022.2-SP6.4',
    [string]$GccBin = '',
    [string]$OutputRoot = '',
    [string]$FabricConfig = '',
    [switch]$FixHold = $true,
    [ValidateRange(0, 2147483647)][int]$PlacementSeed = 1
)
$ErrorActionPreference = 'Stop'
$portRoot = $PSScriptRoot
$projectRoot = [IO.Path]::GetFullPath((Join-Path $portRoot '../../..'))
if (!$GccBin) {
    $GccBin = Join-Path $projectRoot 'xpacks/@xpack-dev-tools/riscv-none-elf-gcc/.content/bin' 
}
if (!$OutputRoot) {
    $OutputRoot = Join-Path $portRoot 'build_submission_r01' 
}
$outputRoot = [IO.Path]::GetFullPath($OutputRoot)
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
$clockHz = $ClockMHz * 1000000
$uartDivider = [int][Math]::Round($clockHz / 115200.0) - 1
$clockPin = if ($ClockMHz -eq 27) {
    'K21' 
}
else {
    'P20' 
}
$clockPeriod = (1000.0 / $ClockMHz).ToString('F3', [Globalization.CultureInfo]::InvariantCulture)
$clockHalf = (500.0 / $ClockMHz).ToString('F3', [Globalization.CultureInfo]::InvariantCulture)
$configText = '`define MES50HP_CPU_HZ ' + $clockHz + "`n" + '`define MES50HP_UART_DIV ' + $uartDivider + "`n"
$configText += '`ifndef MES50HP_BP_ENABLE' + "`n" + '`define MES50HP_BP_ENABLE ' + $(if ($BranchPrediction -eq 'On') {
        '1' 
    }
    else {
        '0' 
    }) + "`n" + '`endif' + "`n"
$configText += '`ifndef MES50HP_MEMORY_SYSTEM' + "`n" + '`define MES50HP_MEMORY_SYSTEM ' + $(if ($MemorySystem -eq 'Wait') {
        '1' 
    }
    else {
        '0' 
    }) + "`n" + '`endif' + "`n"
$configText += '`ifndef MES50HP_CACHE_ENABLE' + "`n" + '`define MES50HP_CACHE_ENABLE ' + $(if ($Cache -eq 'On') {
        '1' 
    }
    else {
        '0' 
    }) + "`n" + '`endif' + "`n"
$configText += '`ifndef MES50HP_EARLY_D_LOOKUP' + "`n" + '`define MES50HP_EARLY_D_LOOKUP ' + $(if ($EarlyLookup -eq 'On' -and $MemorySystem -eq 'Wait' -and $Cache -eq 'On') {
        '1' 
    }
    else {
        '0' 
    }) + "`n" + '`endif' + "`n"
[IO.File]::WriteAllText("$portRoot/rtl/mes50hp_config.vh", $configText)
$fdcPrefix = @(
    "# Generated for $ClockMHz MHz board oscillator ($clockPin).",
    ('create_clock -name {clk_sys} [get_ports clk_sys] -period {' + $clockPeriod + '} -waveform {0.000 ' + $clockHalf + '}'),
    'define_attribute {p:clk_sys} {PAP_IO_DIRECTION} {INPUT}',
    "define_attribute {p:clk_sys} {PAP_IO_LOC} {$clockPin}",
    'define_attribute {p:clk_sys} {PAP_IO_VCCIO} {3.3}',
    'define_attribute {p:clk_sys} {PAP_IO_STANDARD} {LVCMOS33}'
)
[IO.File]::WriteAllLines("$portRoot/constraints/mes50hp.fdc", [string[]]($fdcPrefix + [IO.File]::ReadAllLines("$portRoot/constraints/mes50hp_pins.fdc")))
function Assert-Exit([string]$Step) {
    if ($LASTEXITCODE -ne 0) {
        throw "$Step failed (exit $LASTEXITCODE)" 
    } 
}
$gcc = Join-Path $GccBin 'riscv-none-elf-gcc.exe'
$elf = Join-Path $outputRoot 'hello.elf'
$bin = Join-Path $outputRoot 'hello.bin'
& $gcc -march=rv32im_zicsr -mabi=ilp32 -O2 -ffreestanding -nostdlib -msmall-data-limit=0 -mno-relax -fno-pic -fno-stack-protector -ffixed-s10 -ffixed-s11 "-DCPU_FREQ_HZ=$clockHz" "-DUART_DIVIDER=$uartDivider" '-Wl,--no-relax' "-Wl,-Map,$outputRoot/hello.map" -T "$portRoot/sw/link.ld" "$portRoot/sw/start.S" "$portRoot/sw/main.c" -o $elf
Assert-Exit 'RISC-V software build'
& (Join-Path $GccBin 'riscv-none-elf-objcopy.exe') -O binary $elf $bin
Assert-Exit 'Binary conversion'
& (Join-Path $GccBin 'riscv-none-elf-objdump.exe') -d -M 'numeric,no-aliases' $elf | Set-Content -LiteralPath "$outputRoot/hello.dis"
Assert-Exit 'Numeric disassembly'
& (Join-Path $GccBin 'riscv-none-elf-objdump.exe') -d -M no-aliases $elf | Set-Content -LiteralPath "$outputRoot/hello.abi.dis"
Assert-Exit 'ABI disassembly'
$bytes = [IO.File]::ReadAllBytes($bin)
if ($bytes.Length -gt 16384) {
    throw 'Software exceeds the 16 KiB reference ROM' 
}
$padded = [byte[]]::new(16384)
[Array]::Copy($bytes, $padded, $bytes.Length)
$words = for ($i = 0; $i -lt $padded.Length; $i += 4) {
    [BitConverter]::ToUInt32($padded, $i).ToString('x8') 
}
[IO.File]::WriteAllLines("$outputRoot/boot.mem", [string[]]$words)
$memPath = "$outputRoot/boot.mem".Replace('\', '/')
[IO.File]::WriteAllText("$portRoot/rtl/boot_image_path.vh", '`define MES50HP_BOOT_MEM "' + $memPath + '"' + "`n")
Write-Output "Software: $($bytes.Length) bytes; $bin"
Write-Output "Board clock: $ClockMHz MHz at $clockPin; UART divider: $uartDivider"
if ($Stage -eq 'Software') {
    exit 0 
}

$sources = @(Get-ChildItem -LiteralPath "$portRoot/rtl/vendor" -Recurse -Filter '*.v' | ForEach-Object FullName)
$sources += "$portRoot/rtl/tinyriscv_mes50hp_top.v"
$include = "$portRoot/rtl/vendor/core"
if ($Stage -eq 'Sim') {
    foreach ($bench in @('mes50hp_tb', 'uart_loader_tb')) {
        & iverilog -g2012 -s $bench -I $include -I "$portRoot/rtl" -o "$outputRoot/$bench.vvp" "$portRoot/sim/$bench.sv" @sources
        Assert-Exit "Icarus compile: $bench"
        & vvp "$outputRoot/$bench.vvp" | Tee-Object -FilePath "$outputRoot/$bench.log"
        Assert-Exit "Board simulation: $bench"
    }
    exit 0
}

$tcl = @()
foreach ($source in $sources) {
    $tcl += 'add_design "' + $source.Replace('\', '/') + '"' 
}
$tcl += 'add_constraint "' + "$portRoot/constraints/mes50hp.fdc".Replace('\', '/') + '"'
if ($FabricConfig) {
    $fabricPath = (Get-Item -LiteralPath $FabricConfig).FullName
    if ([IO.Path]::GetExtension($fabricPath) -ne '.fic') {
        throw 'FabricConfig must be a real Fabric Inserter .fic file' 
    }
    $tcl += 'add_fic "' + $fabricPath.Replace('\', '/') + '"'
}
$tcl += 'set_arch -family Logos -device PGL50H -speedgrade -6 -package FBG484'
$compile = 'compile -top_module tinyriscv_mes50hp_top -include_path {"' + $include.Replace('\', '/') + '" "' + "$portRoot/rtl".Replace('\', '/') + '"}'
$tcl += $compile
if ($Stage -ne 'Compile') {
    $tcl += 'synthesize -ads -selected_syn_tool_opt 2' 
}
if ($Stage -eq 'Bitstream') {
    $tcl += 'dev_map'
    $pnrCommand = 'pnr'
    if ($PlacementSeed -ne 0) {
        $pnrCommand += " -gplace_seed $PlacementSeed" 
    }
    if ($FixHold) {
        $pnrCommand += ' -fix_hold_violation -fix_hold_violation_in_route true -fix_hold_violation_threshold 100' 
    }
    $tcl += $pnrCommand
    $tcl += 'report_timing'
    $tcl += 'gen_bit_stream'
}
[IO.File]::WriteAllLines("$outputRoot/build.tcl", [string[]]$tcl)
& "$PdsRoot/bin/pds_shell.exe" -file "$outputRoot/build.tcl" -work_dir $outputRoot -project_name tinyriscv_mes50hp_r04 2>&1 | Tee-Object -FilePath "$outputRoot/pds_build.log"
Assert-Exit 'PDS process'
# This PDS version can return process exit 0 after a Flow error: inspect its log.
if (Select-String -LiteralPath "$outputRoot/pds_build.log" -Pattern '^E:|Failed to|executed failed|execute failed' -Quiet) {
    throw 'PDS reported an error; see build/pds_build.log' 
}
if ($Stage -eq 'Bitstream') {
    $reportPath = "$outputRoot/report_timing/tinyriscv_mes50hp_top.rtr"
    if (!(Test-Path -LiteralPath $reportPath)) {
        throw 'Post-route timing report is missing' 
    }
    $timingText = [IO.File]::ReadAllText($reportPath)
    $bitstreamPath = "$outputRoot/generate_bitstream/tinyriscv_mes50hp_top.sbit"
    if ($timingText -notmatch 'Design Summary\s*:\s*All Constraints Met\.') {
        if (Test-Path -LiteralPath $bitstreamPath) {
            Move-Item -LiteralPath $bitstreamPath -Destination ($bitstreamPath + '.TIMING_FAILED_' + (Get-Date -Format yyyyMMddHHmmss))
        }
        throw 'Post-route timing is not met. The failing bitstream must not be used as a validated build.'
    }
    if (!(Test-Path -LiteralPath $bitstreamPath) -or (Get-Item -LiteralPath $bitstreamPath).Length -eq 0) {
        throw 'PDS did not produce a nonempty bitstream' 
    }
    Write-Output 'Post-route timing passed; bitstream exists.'
}
Write-Output "PDS stage completed: $Stage"
