# 模块说明：run_cache_backend。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([Parameter(Mandatory = $true)][string]$RecordRoot, [string]$ModelSimBin = 'D:/modeltech64_2020.4/win64')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../../..")
$rtl = "$projectRoot/pds/tinyriscv_mes50hp/rtl"
$RecordRoot = [IO.Path]::GetFullPath($RecordRoot)
if (Test-Path -LiteralPath $RecordRoot) {
    throw 'Use a new cache/backend RecordRoot'
}
New-Item -ItemType Directory -Path "$RecordRoot/source" | Out-Null
$sources = @("$rtl/vendor/core/two_way_cache.v", "$rtl/vendor/core/drm_transaction.v",
    "$rtl/vendor/perips/ram.v", "$rtl/vendor/perips/rom.v", "$PSScriptRoot/cache_backend_tb.sv")
$inputs = @($sources) + @("$rtl/vendor/core/defines.v", "$rtl/boot_image_path.vh", $PSCommandPath)
foreach ($file in $inputs) {
    Copy-Item -LiteralPath $file -Destination "$RecordRoot/source"
}
$inputs | ForEach-Object { [pscustomobject]@{Path = $_
        SHA256                                    = (Get-FileHash -LiteralPath $_).Hash
    } } | Export-Csv -LiteralPath "$RecordRoot/source_manifest.csv" -NoTypeInformation
function TclPath([string]$Path) {
    '{' + $Path.Replace('\', '/') + '}'
}
$do = @('onerror {quit -f -code 1}', ('cd ' + (TclPath $RecordRoot)),
    'if {![file exists modelsim.ini]} {vmap -c}', 'vlib work', 'vmap work work')
$do += 'vlog -sv ' + (TclPath "+incdir+$rtl/vendor/core") + ' ' + (TclPath "+incdir+$rtl") + ' ' + (($sources | ForEach-Object { TclPath $_ }) -join ' ')
$do += 'set result_file [open results.csv w]'
$do += 'puts $result_file {Cache,ReadOnly,Passed}'
foreach ($enabled in @(0, 1)) {
    foreach ($readonly in @(0, 1)) {
        $do += 'transcript file ' + (TclPath "$RecordRoot/cache_${enabled}_readonly_$readonly.log")
        $do += "vsim -onfinish stop -voptargs=+acc -gCACHE=$enabled -gREAD_ONLY=$readonly work.cache_backend_tb"
        $do += 'run -all'
        $do += 'set pass [examine -radix unsigned /cache_backend_tb/passed]'
        $do += 'puts $result_file "' + $enabled + ',' + $readonly + ',$pass"'
        $do += 'flush $result_file'
        $do += 'if {$pass != 1} {quit -f -code 1}'
        $do += 'quit -sim'
    }
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
if ($code -ne 0 -or $rows.Count -ne 4 -or @($rows | Where-Object Passed -ne '1').Count -ne 0) {
    throw "Cache/backend unit failed: $RecordRoot"
}
[ordered]@{CompletedAt = (Get-Date -Format o)
    Passed             = $true
    Cases              = $rows.Count
    Scope              = 'Isolated synchronous memory, burst and two-way cache; no SoC or hardware result'
} | ConvertTo-Json | Set-Content -LiteralPath "$RecordRoot/completion.json"
$rows | Format-Table -AutoSize
