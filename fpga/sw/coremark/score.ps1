# 模块说明：score。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param(
    [Parameter(Mandatory = $true)][string]$PerformanceLog,
    [Parameter(Mandatory = $true)][string]$ValidationLog,
    [Parameter(Mandatory = $true)][string]$PerformanceManifest,
    [Parameter(Mandatory = $true)][string]$ValidationManifest,
    [Parameter(Mandatory = $true)][ValidateSet('Board', 'Simulation')][string]$Environment,
    [ValidateRange(0, 100000000)][int]$LutCount = 0,
    [string]$Output = "$PSScriptRoot/../../work/coremark/score.json"
)
$ErrorActionPreference = 'Stop'
function Read-Run([string]$Log, [string]$Manifest, [string]$RunType) {
    $logPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Log)
    $manifestPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Manifest)
    $text = [IO.File]::ReadAllText($logPath)
    $lines = @([regex]::Matches($text, '(?m)^CM_RESULT ([^\r\n]+)\r?$'))
    if ($lines.Count -ne 1) {
        throw "$RunType log needs exactly one complete CM_RESULT line" 
    }
    $fields = @{}
    foreach ($token in ($lines[0].Groups[1].Value.Trim() -split ' ')) {
        if ($token -match '^([^=]+)=(.+)$') {
            $fields[$Matches[1]] = $Matches[2] 
        }
    }
    foreach ($key in @('build', 'profile', 'run', 'iterations', 'cycles_hi', 'cycles_lo', 'hz', 'crc_ok', 'duration_ok', 'formal_valid')) {
        if (!$fields.ContainsKey($key)) {
            throw "$RunType missing $key" 
        }
    }
    if ($fields.profile -ne 'Formal' -or $fields.run -ne $RunType -or $fields.crc_ok -ne '1' -or $fields.duration_ok -ne '1' -or $fields.formal_valid -ne '1') {
        throw "$RunType is not a valid formal run; Smoke/CRC-only results cannot be scored"
    }
    if (!$text.Contains('Correct operation validated.') -or !$text.Contains('COREMARK_FORMAL_VALID') -or $text -match 'ERROR!|Errors detected|Cannot validate') {
        throw "$RunType official validation output missing or reports errors"
    }
    $crc = if ($RunType -eq 'Performance') {
        @('e9f5', 'e714', '1fd7', '8e3a') 
    }
    else {
        @('18f2', 'e3c1', '0747', '8d84') 
    }
    $labels = @('seedcrc', 'crclist', 'crcmatrix', 'crcstate')
    for ($i = 0; $i -lt $labels.Count; $i++) {
        if ($text -notmatch ($labels[$i] + '\s*: 0x' + $crc[$i] + '\b')) {
            throw "$RunType expected $($labels[$i])=$($crc[$i])" 
        }
    }
    $config = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($config.BuildId -ne $fields.build -or $config.Profile -ne 'Formal' -or $config.RunType -ne $RunType -or $config.TotalDataSize -ne 2000 -or $config.ClockHz -ne [int]$fields.hz) {
        throw "$RunType firmware manifest does not match the UART result"
    }
    $hz = [decimal]$fields.hz
    $iterations = [decimal]$fields.iterations
    $hi = [uint32]::Parse($fields.cycles_hi)
    $lo = [uint32]::Parse($fields.cycles_lo)
    $cycles = [decimal]$hi * [decimal]4294967296 + [decimal]$lo
    if ($hz -le 0 -or $iterations -le 0 -or $cycles -lt $hz * 10) {
        throw "$RunType raw values do not meet the >=10 second requirement" 
    }
    [pscustomobject]@{
        RunType             = $RunType
        BuildId             = $fields.build
        Iterations          = $iterations
        Cycles              = $cycles
        ClockHz             = $hz

        Seconds             = $cycles / $hz
        IterationsPerSecond = $iterations * $hz / $cycles

        CoreMarkPerMHz      = $iterations * [decimal]1000000 / $cycles

        Log                 = $logPath
        LogSHA256           = (Get-FileHash -LiteralPath $logPath -Algorithm SHA256).Hash

        Manifest            = $manifestPath
        Config              = $config
    }
}
$performance = Read-Run $PerformanceLog $PerformanceManifest 'Performance'
$validation = Read-Run $ValidationLog $ValidationManifest 'Validation'
foreach ($name in @('ClockHz', 'Compiler', 'UpstreamCommit', 'HasFloat', 'TotalDataSize', 'StartupSHA256')) {
    if ($performance.Config.$name -ne $validation.Config.$name) {
        throw "Runs differ in $name" 
    }
}
$perfFlags = @($performance.Config.CompilerFlags | Where-Object { $_ -notmatch '^-D(PERFORMANCE|VALIDATION)_RUN=' }) -join ' '
$validFlags = @($validation.Config.CompilerFlags | Where-Object { $_ -notmatch '^-D(PERFORMANCE|VALIDATION)_RUN=' }) -join ' '
if ($perfFlags -ne $validFlags -or ($performance.Config.SourceHashes | ConvertTo-Json -Compress) -ne ($validation.Config.SourceHashes | ConvertTo-Json -Compress) -or ($performance.Config.PortHashes | ConvertTo-Json -Compress) -ne ($validation.Config.PortHashes | ConvertTo-Json -Compress)) {
    throw 'Performance and Validation must use the same kernel, port and compiler configuration except the run seed selection'
}
$report = [ordered]@{
    CreatedAt      = (Get-Date -Format o)
    Benchmark      = 'CoreMark 1.0'
    Environment    = $Environment

    Performance    = $performance
    Validation     = $validation

    CoreMark       = $performance.IterationsPerSecond
    CoreMarkPerMHz = $performance.CoreMarkPerMHz

    LutCount       = $LutCount
    CoreMarkPerLUT = $(if ($LutCount -gt 0) {
            $performance.IterationsPerSecond / $LutCount 
        }
        else {
            $null 
        })

    Note           = 'Performance score; validation is a separate correctness prerequisite. Attach measured clock, RTL/bitstream hashes and matching resource/timing reports to establish board provenance.'
}
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output)
New-Item -ItemType Directory -Path (Split-Path -Parent $outputPath) -Force | Out-Null
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outputPath -Encoding utf8
Write-Output "Environment=$Environment; Performance=$($performance.Seconds) s; Validation=$($validation.Seconds) s"
Write-Output "CoreMark=$($report.CoreMark); CoreMark/MHz=$($report.CoreMarkPerMHz); CoreMark/LUT=$($report.CoreMarkPerLUT)"
Write-Output "Saved: $outputPath"
