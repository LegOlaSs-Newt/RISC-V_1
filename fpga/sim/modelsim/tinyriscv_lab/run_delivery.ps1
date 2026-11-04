# 模块说明：run_delivery。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([string]$RecordRoot = '', [string]$GccBin = '', [string]$ModelSimBin = 'D:/modeltech64_2020.4/win64',
    [ValidateSet('On', 'Off')][string]$BranchPrediction = 'On',
    [ValidateSet('Legacy', 'Wait')][string]$MemorySystem = 'Wait',
    [ValidateSet('On', 'Off')][string]$Cache = 'On',
    [ValidateSet('On', 'Off')][string]$EarlyLookup = 'On')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../../..")
if (!$RecordRoot) {
    $RecordRoot = "$projectRoot/work/development/Delivery_$(Get-Date -Format yyyyMMdd_HHmmss)" 
}
$RecordRoot = [IO.Path]::GetFullPath($RecordRoot)
if (Test-Path -LiteralPath $RecordRoot) {
    throw 'Use a new RecordRoot; this runner never merges old evidence.' 
}
New-Item -ItemType Directory -Path $RecordRoot | Out-Null
$groups = [ordered]@{Quick = 2
    ISA                    = 47
    Examples               = 6
    Board                  = 2
    CoreMark               = 2
    Boundary               = 3
    Delivery               = 4
    Advanced               = 6
}
if ($MemorySystem -eq 'Wait') {
    $groups.Memory = 3
}
$identityInputs = @(Get-ChildItem -LiteralPath "$projectRoot/pds/tinyriscv_mes50hp/rtl" -Recurse -File | Where-Object Extension -in @('.v', '.vh'))
$identityBefore = @($identityInputs | ForEach-Object { [pscustomobject]@{Path = $_.FullName; SHA256 = (Get-FileHash -LiteralPath $_.FullName).Hash } })
$identityBefore | Export-Csv -LiteralPath "$RecordRoot/input_manifest.csv" -NoTypeInformation -Encoding utf8
$summary = @()
foreach ($suite in $groups.Keys) {
    & pwsh -NoProfile -File "$PSScriptRoot/run.ps1" -Suite $suite -RtlSet Port -BranchPrediction $BranchPrediction -MemorySystem $MemorySystem -Cache $Cache -EarlyLookup $EarlyLookup -RecordRoot $RecordRoot -ModelSimBin $ModelSimBin -GccBin $GccBin *> "$RecordRoot/$suite.log"
    $code = $LASTEXITCODE
    $group = if ($suite -eq 'CoreMark') {
        'CoreMarkSmoke' 
    }
    else {
        $suite 
    }
    $rows = @(Import-Csv -LiteralPath "$RecordRoot/$group/results.csv")
    $passed = @($rows | Where-Object Passed -eq '1').Count
    $summary += [pscustomobject]@{Suite = $group
        Expected                        = $groups[$suite]
        Completed                       = $rows.Count
        Passed                          = $passed
        ExitCode                        = $code
    }
    $summary | Export-Csv -LiteralPath "$RecordRoot/summary.csv" -NoTypeInformation -Encoding utf8
    if ($code -ne 0 -or $rows.Count -ne $groups[$suite] -or $passed -ne $rows.Count) {
        throw "Incomplete/failed $suite; evidence saved to $RecordRoot" 
    }
    Write-Output "$group $passed/$($rows.Count) PASS"
}
& pwsh -NoProfile -File "$PSScriptRoot/run.ps1" -Case pipeline_fail -RtlSet Port -BranchPrediction $BranchPrediction -MemorySystem $MemorySystem -Cache $Cache -EarlyLookup $EarlyLookup -RecordRoot $RecordRoot -ModelSimBin $ModelSimBin -GccBin $GccBin *> "$RecordRoot/pipeline_fail.log"
$negativeExit = $LASTEXITCODE
$rows = @(Import-Csv -LiteralPath "$RecordRoot/pipeline_fail/results.csv")
if ($negativeExit -eq 0 -or $rows.Count -ne 1 -or $rows[0].Passed -ne '0') {
    throw 'pipeline_fail was not rejected correctly' 
}
$drift = @($identityBefore | Where-Object { !(Test-Path -LiteralPath $_.Path) -or (Get-FileHash -LiteralPath $_.Path).Hash -ne $_.SHA256 })
if ($drift.Count -ne 0) {
    $drift | Export-Csv -LiteralPath "$RecordRoot/input_drift.csv" -NoTypeInformation
    throw 'RTL/configuration changed during delivery run; do not treat mixed inputs as one validated version'
}
[ordered]@{CompletedAt = (Get-Date -Format o)
    RtlSet             = 'Port'
    BranchPrediction   = $BranchPrediction
    MemorySystem       = $MemorySystem
    Cache              = $(if ($MemorySystem -eq 'Wait') {
            $Cache
        }
        else {
            'NotApplicable'
        })
    EarlyLookup        = $(if ($MemorySystem -eq 'Wait' -and $Cache -eq 'On') {
            $EarlyLookup
        }
        else {
            'Off'
        })
    InputsUnchanged    = $true
    NormalCases        = ($summary | Measure-Object -Property Completed -Sum).Sum
    NormalPassed       = ($summary | Measure-Object -Property Passed -Sum).Sum
    NegativeExit       = $negativeExit
    NegativeRejected   = $true
} | ConvertTo-Json | Set-Content -LiteralPath "$RecordRoot/completion.json" -Encoding utf8
$summary | Format-Table -AutoSize
Write-Output "pipeline_fail rejected, exit=$negativeExit; complete: $RecordRoot"
