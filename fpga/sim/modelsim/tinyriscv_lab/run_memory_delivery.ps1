# 模块说明：run_memory_delivery。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param([Parameter(Mandatory = $true)][string]$RecordRoot, [string]$GccBin = '', [string]$ModelSimBin = 'D:/modeltech64_2020.4/win64')
$ErrorActionPreference = 'Stop'
$RecordRoot = [IO.Path]::GetFullPath($RecordRoot)
if (Test-Path -LiteralPath $RecordRoot) {
    throw 'Use a new memory-delivery RecordRoot'
}
New-Item -ItemType Directory -Path $RecordRoot | Out-Null
$summary = @()
foreach ($cache in @('On', 'Off')) {
    foreach ($prediction in @('On', 'Off')) {
        $variant = "$RecordRoot/Cache${cache}_Bp$prediction"
        & pwsh -NoProfile -File "$PSScriptRoot/run_delivery.ps1" -RecordRoot $variant -ModelSimBin $ModelSimBin -GccBin $GccBin -MemorySystem Wait -Cache $cache -BranchPrediction $prediction
        if ($LASTEXITCODE -ne 0) {
            throw "Memory delivery failed: $variant"
        }
        $completion = Get-Content -LiteralPath "$variant/completion.json" -Raw | ConvertFrom-Json
        if ($completion.NormalCases -ne 75 -or $completion.NormalPassed -ne 75 -or !$completion.NegativeRejected -or !$completion.InputsUnchanged) {
            throw "Incomplete memory delivery: $variant"
        }
        $summary += [pscustomobject]@{Cache = $cache
            BranchPrediction                = $prediction
            NormalCases                     = $completion.NormalCases
            NormalPassed                    = $completion.NormalPassed
            NegativeRejected                = $completion.NegativeRejected
            RecordRoot                      = $variant
        }
        $summary | Export-Csv -LiteralPath "$RecordRoot/matrix_summary.csv" -NoTypeInformation
    }
}
$unitRoot = "$RecordRoot/Units"
New-Item -ItemType Directory -Path $unitRoot | Out-Null
$jobs = @(
    @{Script = 'run_memory_wait.ps1'; Name = 'CPUWait'; Arguments = @('-BranchPrediction', 'Both') },
    @{Script = 'run_memory_wait.ps1'; Name = 'CPUQuiesce'; Arguments = @('-BranchPrediction', 'Both', '-Quiesce') },
    @{Script = 'run_cache_backend.ps1'; Name = 'CacheBackend'; Arguments = @() },
    @{Script = 'run_uart_wait.ps1'; Name = 'UARTWait'; Arguments = @() },
    @{Script = 'run_jtag_wait.ps1'; Name = 'JTAGWait'; Arguments = @() }
)
foreach ($job in $jobs) {
    $output = "$unitRoot/$($job.Name)"
    $unitArguments = @($job.Arguments)
    if ($job.Script -eq 'run_memory_wait.ps1') {
        $unitArguments += @('-GccBin', $GccBin) 
    }
    & pwsh -NoProfile -File "$PSScriptRoot/$($job.Script)" -RecordRoot $output -ModelSimBin $ModelSimBin @unitArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Supplemental unit failed: $output"
    }
}
[ordered]@{CompletedAt = (Get-Date -Format o)
    Passed             = $true
    Scope              = 'Simulation only: four Port configurations, negative checks, delay/fault/cache/UART/DMI units; no PDS or board result'
    MemorySystem       = 'Wait'
    Variants           = $summary
    NormalCases        = 300
    NegativeChecks     = 4
    Units              = @($jobs.Name)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$RecordRoot/completion.json"
Write-Output "Memory simulation delivery passed: $RecordRoot"
