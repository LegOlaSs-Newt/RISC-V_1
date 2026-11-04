# 模块说明：run_memory_soc。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([Parameter(Mandatory = $true)][string]$RecordRoot, [string]$GccBin = '', [string]$ModelSimBin = 'D:/modeltech64_2020.4/win64')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../../..")
$rtl = "$projectRoot/pds/tinyriscv_mes50hp/rtl"
$RecordRoot = [IO.Path]::GetFullPath($RecordRoot)
if (Test-Path -LiteralPath $RecordRoot) {
    throw 'Use a new memory-SoC RecordRoot'
}
New-Item -ItemType Directory -Path "$RecordRoot/source" | Out-Null
. "$projectRoot/tools/environment.ps1"
$gcc = Resolve-RiscVGccBin -Requested $GccBin -SubmissionRoot $projectRoot
$assembly = "$PSScriptRoot/programs/memory_soc.S"
& "$gcc/riscv-none-elf-gcc.exe" -march=rv32im_zicsr -mabi=ilp32 -nostdlib -ffreestanding -mno-relax '-Wl,--no-relax' -T "$projectRoot/third_party/tinyriscv/tests/isa/link.ld" $assembly -o "$RecordRoot/program.elf"
if ($LASTEXITCODE -ne 0) {
    throw 'Assembly failed'
}
& "$gcc/riscv-none-elf-objcopy.exe" -O binary "$RecordRoot/program.elf" "$RecordRoot/program.bin"
if ($LASTEXITCODE -ne 0) {
    throw 'objcopy failed'
}
& "$gcc/riscv-none-elf-objdump.exe" -d -M no-aliases "$RecordRoot/program.elf" | Set-Content -LiteralPath "$RecordRoot/program.dis"
if ($LASTEXITCODE -ne 0) {
    throw 'objdump failed'
}
$bytes = [IO.File]::ReadAllBytes("$RecordRoot/program.bin")
$padded = [byte[]]::new(16384)
[Array]::Copy($bytes, $padded, $bytes.Length)
$words = for ($i = 0; $i -lt 16384; $i += 4) {
    [BitConverter]::ToUInt32($padded, $i).ToString('x8')
}
[IO.File]::WriteAllLines("$RecordRoot/program.mem", [string[]]$words)
$sources = @(Get-ChildItem -LiteralPath "$rtl/vendor" -Recurse -Filter '*.v' | Sort-Object FullName | ForEach-Object FullName) + @("$PSScriptRoot/memory_soc_tb.sv")
foreach ($file in @($sources) + @($PSCommandPath, $assembly)) {
    Copy-Item -LiteralPath $file -Destination "$RecordRoot/source"
}
$sources | ForEach-Object { [pscustomobject]@{Path = $_
        SHA256                                     = (Get-FileHash -LiteralPath $_).Hash
    } } | Export-Csv -LiteralPath "$RecordRoot/source_manifest.csv" -NoTypeInformation
function TclPath([string]$p) {
    '{' + $p.Replace('\', '/') + '}'
}
$do = @('onerror {quit -f -code 1}', ('cd ' + (TclPath $RecordRoot)), 'if {![file exists modelsim.ini]} {vmap -c}', 'vlib work', 'vmap work work')
$do += 'vlog -sv +define+MES50HP_BP_ENABLE=1 ' + (TclPath "+incdir+$rtl/vendor/core") + ' ' + (TclPath "+incdir+$rtl") + ' ' + (($sources | ForEach-Object { TclPath $_ }) -join ' ')
$do += 'set result_file [open results.csv w]'
$do += 'puts $result_file {Cache,Passed}'
foreach ($enabled in @(0, 1)) {
    $do += 'transcript file ' + (TclPath "$RecordRoot/cache_$enabled.log")
    $do += "vsim -onfinish stop -voptargs=+acc -gCACHE=$enabled work.memory_soc_tb " + (TclPath "+IMAGE=$RecordRoot/program.mem")
    $do += 'run -all'
    $do += 'set pass [examine -radix unsigned /memory_soc_tb/passed]'
    $do += 'puts $result_file "' + $enabled + ',$pass"'
    $do += 'flush $result_file'
    $do += 'if {$pass != 1} {quit -f -code 1}'
    $do += 'quit -sim'
}
$do += 'close $result_file'
$do += 'quit -f -code 0'
[IO.File]::WriteAllLines("$RecordRoot/run.do", [string[]]$do)
Push-Location -LiteralPath $RecordRoot
try {
    & "$ModelSimBin/vsim.exe" -c -do 'do run.do' *> "$RecordRoot/runner.log"
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}
$rows = if (Test-Path -LiteralPath "$RecordRoot/results.csv") {
    @(Import-Csv -LiteralPath "$RecordRoot/results.csv")
}
else {
    @()
}
if ($code -ne 0 -or $rows.Count -ne 2 -or @($rows | Where-Object Passed -ne '1').Count -ne 0) {
    throw "Memory SoC coordination failed: $RecordRoot"
}
[ordered]@{CompletedAt = (Get-Date -Format o)
    Passed             = $true
    Cases              = $rows.Count
    Scope              = 'SoC UART mode drain plus DMI-level JTAG memory/halt/resume; no physical JTAG/board result'
} | ConvertTo-Json | Set-Content -LiteralPath "$RecordRoot/completion.json"
$rows | Format-Table -AutoSize
