# 模块说明：run_timer_unit。
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
    throw 'Use a new timer unit RecordRoot'
}
New-Item -ItemType Directory -Path $RecordRoot | Out-Null
$rtl = "$projectRoot/pds/tinyriscv_mes50hp/rtl/vendor/perips/timer.v"
$bench = "$PSScriptRoot/timer_irq_tb.sv"
New-Item -ItemType Directory -Path "$RecordRoot/source" | Out-Null
Copy-Item -LiteralPath $rtl, $bench -Destination "$RecordRoot/source"
@($rtl, $bench) | ForEach-Object { [pscustomobject]@{Path = $_
        SHA256                                            = (Get-FileHash -LiteralPath $_).Hash
    } } |
    Export-Csv -LiteralPath "$RecordRoot/source_manifest.csv" -NoTypeInformation -Encoding utf8
$commands = @(
    'onerror {quit -f -code 1}', 'vmap -c', 'vlib work', 'vmap work work',
    ('vlog -sv {' + $rtl.Replace('\', '/') + '} {' + $bench.Replace('\', '/') + '}'),
    'vsim -voptargs=+acc -onfinish stop work.timer_irq_tb',
    'run -all', 'set pass [examine -radix unsigned /timer_irq_tb/passed]',
    'set result_file [open results.csv w]',
    'puts $result_file {Case,Passed}',
    'puts $result_file "timer_irq,$pass"', 'close $result_file',
    'quit -f -code [expr {$pass != 1}]'
)
[IO.File]::WriteAllLines("$RecordRoot/run.do", [string[]]$commands)
Push-Location -LiteralPath $RecordRoot
try {
    & "$ModelSimBin/vsim.exe" -c -do 'do run.do' *> "$RecordRoot/runner.log"
    $timerCode = $LASTEXITCODE
    $rows = @(Import-Csv -LiteralPath "$RecordRoot/results.csv")
    if ($timerCode -ne 0 -or $rows.Count -ne 1 -or $rows[0].Passed -ne '1') {
        throw "Timer unit failed; see $RecordRoot"
    }
    $rows | Format-Table -AutoSize
}
finally {
    Pop-Location
}

