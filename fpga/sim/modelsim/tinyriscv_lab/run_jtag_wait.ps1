# 模块说明：run_jtag_wait。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([Parameter(Mandatory = $true)][string]$RecordRoot, [string]$ModelSimBin = 'D:/modeltech64_2020.4/win64')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../../..")
$RecordRoot = [IO.Path]::GetFullPath($RecordRoot)
if (Test-Path -LiteralPath $RecordRoot) {
    throw 'Use a new JTAG-wait RecordRoot'
}
New-Item -ItemType Directory -Path "$RecordRoot/source" | Out-Null
$base = "$projectRoot/pds/tinyriscv_mes50hp/rtl/vendor"
$sources = @("$base/debug/jtag_dm_wait.v", "$base/utils/full_handshake_tx.v", "$base/utils/full_handshake_rx.v", "$PSScriptRoot/jtag_wait_tb.sv")
foreach ($file in @($sources) + @($PSCommandPath)) {
    Copy-Item -LiteralPath $file -Destination "$RecordRoot/source"
}
$sources | ForEach-Object { [pscustomobject]@{Path = $_
        SHA256                                     = (Get-FileHash -LiteralPath $_).Hash
    } } | Export-Csv -LiteralPath "$RecordRoot/source_manifest.csv" -NoTypeInformation
function TclPath([string]$p) {
    '{' + $p.Replace('\', '/') + '}'
}
$do = @('onerror {quit -f -code 1}', ('cd ' + (TclPath $RecordRoot)), 'if {![file exists modelsim.ini]} {vmap -c}', 'vlib work', 'vmap work work')
$do += 'vlog -sv ' + (($sources | ForEach-Object { TclPath $_ }) -join ' ')
$do += 'vsim -onfinish stop -voptargs=+acc work.jtag_wait_tb'
$do += 'run -all'
$do += 'set pass [examine -radix unsigned /jtag_wait_tb/passed]'
$do += 'set result_file [open results.csv w]'
$do += 'puts $result_file {Case,Passed}'
$do += 'puts $result_file "jtag_wait,$pass"'
$do += 'close $result_file'
$do += 'quit -f -code [expr {$pass != 1}]'
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
if ($code -ne 0 -or $rows.Count -ne 1 -or $rows[0].Passed -ne '1') {
    throw "JTAG wait unit failed: $RecordRoot"
}
[ordered]@{CompletedAt = (Get-Date -Format o)
    Passed             = $true
    Scope              = 'DMI/32-bit SBA against delayed memory model; not full JTAG pin/SoC/board validation'
} | ConvertTo-Json | Set-Content -LiteralPath "$RecordRoot/completion.json"
$rows | Format-Table -AutoSize
