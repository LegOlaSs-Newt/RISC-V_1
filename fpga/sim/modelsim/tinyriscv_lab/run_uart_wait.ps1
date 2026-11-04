# 模块说明：run_uart_wait。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([Parameter(Mandatory = $true)][string]$RecordRoot, [string]$ModelSimBin = 'D:/modeltech64_2020.4/win64')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../../..")
$RecordRoot = [IO.Path]::GetFullPath($RecordRoot)
if (Test-Path -LiteralPath $RecordRoot) {
    throw 'Use a new UART-wait RecordRoot'
}
New-Item -ItemType Directory -Path "$RecordRoot/source" | Out-Null
$sources = @("$projectRoot/pds/tinyriscv_mes50hp/rtl/vendor/debug/uart_debug_wait.v", "$PSScriptRoot/uart_wait_tb.sv")
$inputs = @($sources) + @($PSCommandPath, "$projectRoot/pds/tinyriscv_mes50hp/rtl/mes50hp_config.vh")
foreach ($file in $inputs) {
    Copy-Item -LiteralPath $file -Destination "$RecordRoot/source"
}
$inputs | ForEach-Object { [pscustomobject]@{Path = $_
        SHA256                                    = (Get-FileHash -LiteralPath $_).Hash
    } } | Export-Csv -LiteralPath "$RecordRoot/source_manifest.csv" -NoTypeInformation
function TclPath([string]$p) {
    '{' + $p.Replace('\', '/') + '}'
}
$do = @('onerror {quit -f -code 1}', ('cd ' + (TclPath $RecordRoot)), 'if {![file exists modelsim.ini]} {vmap -c}', 'vlib work', 'vmap work work')
$do += 'vlog -sv ' + (($sources | ForEach-Object { TclPath $_ }) -join ' ')
$do += 'set result_file [open results.csv w]'
$do += 'puts $result_file {Seed,Passed}'
foreach ($seed in @(1, 12345)) {
    $do += 'transcript file ' + (TclPath "$RecordRoot/seed_$seed.log")
    $do += "vsim -onfinish stop -voptargs=+acc -gSEED=$seed work.uart_wait_tb"
    $do += 'run -all'
    $do += 'set pass [examine -radix unsigned /uart_wait_tb/passed]'
    $do += 'puts $result_file "' + $seed + ',$pass"'
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
    throw "UART wait unit failed: $RecordRoot"
}
[ordered]@{CompletedAt = (Get-Date -Format o)
    Passed             = $true
    Cases              = $rows.Count
    Scope              = 'UART protocol engine against delayed MMIO/memory model; no physical UART/board result'
} | ConvertTo-Json | Set-Content -LiteralPath "$RecordRoot/completion.json"
$rows | Format-Table -AutoSize
