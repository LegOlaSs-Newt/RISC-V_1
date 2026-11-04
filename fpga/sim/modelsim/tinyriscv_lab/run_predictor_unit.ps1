# 模块说明：run_predictor_unit。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param(
    [Parameter(Mandatory = $true)][string]$RecordRoot,
    [string]$ModelSimBin = 'D:/modeltech64_2020.4/win64'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../../..")
$RecordRoot = [IO.Path]::GetFullPath($RecordRoot)
if (Test-Path -LiteralPath $RecordRoot) {
    throw 'Use a new unit RecordRoot' 
}
New-Item -ItemType Directory -Path $RecordRoot | Out-Null
$rtl = "$projectRoot/pds/tinyriscv_mes50hp/rtl/vendor/core/branch_predictor.v"
$bench = "$PSScriptRoot/branch_predictor_tb.sv"
New-Item -ItemType Directory -Path "$RecordRoot/source" | Out-Null
Copy-Item -LiteralPath $rtl, $bench -Destination "$RecordRoot/source"
function TclPath([string]$p) {
    '{' + $p.Replace('\', '/') + '}' 
}
@($rtl, $bench) | ForEach-Object {
    [pscustomobject]@{Path = $_
        SHA256             = (Get-FileHash -LiteralPath $_).Hash
    }
} | Export-Csv -LiteralPath "$RecordRoot/source_manifest.csv" -NoTypeInformation -Encoding utf8
$commands = @(
    'onerror {quit -f -code 1}',
    ('cd ' + (TclPath $RecordRoot)),
    'if {![file exists modelsim.ini]} {vmap -c}',
    'vlib work',
    'vmap work work',
    ('vlog -sv ' + (TclPath $rtl) + ' ' + (TclPath $bench)),
    'set failed 0',
    'set result_file [open results.csv w]',
    'puts $result_file {Enable,Passed}'
)
foreach ($enabled in @(0, 1)) {
    $commands += "vsim -voptargs=+acc -onfinish stop -gENABLE=$enabled work.branch_predictor_tb"
    $commands += 'run -all'
    $commands += 'set pass [examine -radix unsigned /branch_predictor_tb/passed]'
    $commands += ('puts $result_file "' + $enabled + ',$pass"')
    $commands += 'flush $result_file'
    $commands += 'if {$pass != 1} {incr failed}'
    $commands += 'quit -sim'
}
$commands += 'close $result_file'
$commands += 'quit -f -code [expr {$failed > 0}]'
[IO.File]::WriteAllLines("$RecordRoot/run.do", [string[]]$commands)
Push-Location -LiteralPath $RecordRoot
try {
    & "$ModelSimBin/vsim.exe" -c -do 'do run.do' *> "$RecordRoot/runner.log"
    $unitCode = $LASTEXITCODE
    $rows = @(Import-Csv -LiteralPath "$RecordRoot/results.csv")
    if ($unitCode -ne 0 -or $rows.Count -ne 2 -or @($rows | Where-Object Passed -ne '1').Count -ne 0) {
        throw "Predictor unit tests failed; see $RecordRoot"
    }
    $rows | Format-Table -AutoSize
}
finally {
    Pop-Location 
}

