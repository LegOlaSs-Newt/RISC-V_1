# 模块说明：run_cache_probe。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([Parameter(Mandatory = $true)][string]$RecordRoot, [Parameter(Mandatory = $true)][string]$FirmwareRoot, [string]$ModelSimBin = 'D:/modeltech64_2020.4/win64')
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath("$PSScriptRoot/../../..")
$rtl = "$repo/pds/tinyriscv_mes50hp/rtl"
$out = [IO.Path]::GetFullPath($RecordRoot)
$firmware = [IO.Path]::GetFullPath($FirmwareRoot)
if (Test-Path -LiteralPath $out) {
    throw 'Use a new cache-probe simulation record'
}
New-Item -ItemType Directory -Path "$out/source" -Force | Out-Null
Copy-Item -LiteralPath $firmware -Destination "$out/Firmware" -Recurse
$sources = @(Get-ChildItem -LiteralPath "$rtl/vendor" -Recurse -Filter '*.v' | Sort-Object FullName | ForEach-Object FullName) + @("$PSScriptRoot/cache_probe_tb.sv")
$compiled = @($sources | Where-Object { [IO.Path]::GetFileName($_) -notin @('full_handshake_tx.v', 'full_handshake_rx.v') })
# Existing ModelSim declaration-order workaround, restricted to staged copies.
foreach ($pair in @(@('full_handshake_tx.v', 'ack'), @('full_handshake_rx.v', 'req'))) {
    $original = "$rtl/vendor/utils/$($pair[0])"
    $text = [IO.File]::ReadAllText($original)
    $pattern = '(?m)^[ \t]*reg[ \t]+' + $pair[1] + ';[ \t]*\r?\n'
    if ([regex]::Matches($text, $pattern).Count -ne 1) {
        throw 'Handshake declaration changed'
    }
    $text = [regex]::Replace($text, $pattern, '').Replace('    localparam STATE_IDLE', ('    reg ' + $pair[1] + ";`n`n    localparam STATE_IDLE"))
    [IO.File]::WriteAllText("$out/source/$($pair[0])", $text)
    $compiled += "$out/source/$($pair[0])"
}
foreach ($file in $sources) {
    if ([IO.Path]::GetFileName($file) -notin @('full_handshake_tx.v', 'full_handshake_rx.v')) {
        Copy-Item -LiteralPath $file -Destination "$out/source"
    }
}
$sources | ForEach-Object { [pscustomobject]@{Path = $_
        SHA256                                     = (Get-FileHash -LiteralPath $_).Hash
    } } | Export-Csv -LiteralPath "$out/source_manifest.csv" -NoTypeInformation
function TclPath([string]$p) {
    '{' + $p.Replace('\', '/') + '}'
}
$do = @('onerror {quit -f -code 1}', ('cd ' + (TclPath $out)), 'vmap -c', 'vlib work', 'vmap work work')
$do += 'vlog -sv +define+MES50HP_BP_ENABLE=1 ' + (TclPath "+incdir+$rtl/vendor/core") + ' ' + (TclPath "+incdir+$rtl") + ' ' + (($compiled | ForEach-Object { TclPath $_ }) -join ' ')
$do += 'set result_file [open results.csv w]'
$do += 'puts $result_file {Cache,Passed}'
foreach ($cache in @(0, 1)) {
    $do += 'transcript file ' + (TclPath "$out/cache_$cache.log")
    $do += "vsim -onfinish stop -voptargs=+acc -gCACHE=$cache work.cache_probe_tb " + (TclPath "+IMAGE=$out/Firmware/probe.mem") + ' ' + (TclPath "+UART_LOG=$out/cache_$cache.uart.log")
    $do += 'run -all'
    $do += 'set pass [examine -radix unsigned /cache_probe_tb/passed]'
    $do += 'puts $result_file "' + $cache + ',$pass"'
    $do += 'flush $result_file'
    $do += 'if {$pass != 1} {quit -f -code 1}'
    $do += 'quit -sim'
}
$do += 'close $result_file'
$do += 'quit -f -code 0'
[IO.File]::WriteAllLines("$out/run.do", [string[]]$do)
Push-Location -LiteralPath $out
try {
    & "$ModelSimBin/vsim.exe" -c -do 'do run.do' *> "$out/runner.log"
    $code = $LASTEXITCODE
}
finally {
    Pop-Location
}
if ($code -ne 0) {
    throw "Cache probe failed; preserve $out"
}
$rows = @(Import-Csv -LiteralPath "$out/results.csv")
if ($rows.Count -ne 2 -or @($rows | Where-Object Passed -ne '1').Count) {
    throw 'Cache probe results incomplete'
}
[ordered]@{CompletedAt = (Get-Date -Format o)
    Passed             = $true
    Cases              = 2
    BinarySHA256       = (Get-FileHash -LiteralPath "$out/Firmware/probe.bin").Hash
    Scope              = 'SoC simulation of actual 27MHz/UART board workload; no physical board operation; analyze WORK counts separately'
} | ConvertTo-Json | Set-Content -LiteralPath "$out/completion.json"
$rows | Format-Table -AutoSize
