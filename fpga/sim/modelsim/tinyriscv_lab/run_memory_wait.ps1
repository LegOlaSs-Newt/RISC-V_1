# 模块说明：run_memory_wait。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param(
    [Parameter(Mandatory = $true)][string]$RecordRoot,
    [string]$GccBin = '', [string]$ModelSimBin = 'D:/modeltech64_2020.4/win64',
    [ValidateSet('On', 'Off', 'Both')][string]$BranchPrediction = 'Both',
    [switch]$IncludeISA,
    [ValidateSet('Delay', 'System')][string]$Topology = 'Delay',
    [ValidateSet(0, 1)][int]$CacheEnable = 1,
    [switch]$Quiesce
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/../../..")
$RecordRoot = [IO.Path]::GetFullPath($RecordRoot)
if (Test-Path -LiteralPath $RecordRoot) {
    throw 'Use a new memory-wait RecordRoot'
}
New-Item -ItemType Directory -Path $RecordRoot | Out-Null
$core = "$projectRoot/pds/tinyriscv_mes50hp/rtl/vendor/core"
. "$projectRoot/tools/environment.ps1"
$gccRoot = Resolve-RiscVGccBin -Requested $GccBin -SubmissionRoot $projectRoot
$reference = "$projectRoot/third_party/tinyriscv/tests/isa"
$names = @('pipeline', 'pipeline_valid', 'csr_semantics', 'exceptions', 'jalr_odd', 'jalr_edges', 'jalr_bit1', 'memory_wait')
if ($Topology -eq 'System') {
    $names = @($names | Where-Object { $_ -ne 'memory_wait' }) + @('cache_system')
}
if ($Quiesce) {
    if ($Topology -ne 'Delay' -or $IncludeISA) {
        throw 'Quiesce uses the standalone delay model'
    }
    $names = @('memory_wait')
}
if ($Topology -eq 'Delay' -and !$Quiesce) {
    $names += @('fetch_error', 'memory_wait_backpressure')
}
$entries = @()
foreach ($name in $names) {
    $folder = "$RecordRoot/Firmware/$name"
    New-Item -ItemType Directory -Path $folder -Force | Out-Null
    $sourceName = if ($name -eq 'memory_wait_backpressure') {
        'memory_wait'
    }
    else {
        $name
    }
    $source = "$PSScriptRoot/programs/$sourceName.S"
    & "$gccRoot/riscv-none-elf-gcc.exe" -march=rv32im_zicsr -mabi=ilp32 -nostdlib -ffreestanding -mno-relax '-Wl,--no-relax' -DLAB_MEMORY_SYSTEM -T "$reference/link.ld" $source -o "$folder/program.elf"
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed: $name"
    }
    & "$gccRoot/riscv-none-elf-objcopy.exe" -O binary "$folder/program.elf" "$folder/program.bin"
    if ($LASTEXITCODE -ne 0) {
        throw "objcopy failed: $name"
    }
    & "$gccRoot/riscv-none-elf-objdump.exe" -d -M no-aliases "$folder/program.elf" | Set-Content -LiteralPath "$folder/program.dis"
    if ($LASTEXITCODE -ne 0) {
        throw "objdump failed: $name"
    }
    Copy-Item -LiteralPath $source -Destination "$folder/program.S"
    $seeds = if ($Topology -eq 'System') {
        @(1)
    }
    else {
        @(1, 12345)
    }
    $entries += [pscustomobject]@{Name = $name
        Binary                         = "$folder/program.bin"
        Folder                         = $folder
        Faults                         = [int]($name -in @('memory_wait', 'memory_wait_backpressure'))
        Seeds                          = $seeds
    }
}
if ($IncludeISA) {
    foreach ($binary in Get-ChildItem -LiteralPath "$reference/generated" -Filter '*.bin' | Sort-Object Name) {
        $folder = "$RecordRoot/Firmware/$($binary.BaseName)"
        New-Item -ItemType Directory -Path $folder | Out-Null
        Copy-Item -LiteralPath $binary.FullName -Destination "$folder/program.bin"
        $entries += [pscustomobject]@{Name = $binary.BaseName
            Binary                         = "$folder/program.bin"
            Folder                         = $folder
            Faults                         = 0
            Seeds                          = @(41)
        }
    }
}
foreach ($entry in $entries) {
    $bytes = [IO.File]::ReadAllBytes($entry.Binary)
    if ($bytes.Length -gt 16384 -or $bytes.Length -eq 0) {
        throw 'Invalid image size'
    }
    $padded = [byte[]]::new(16384)
    [Array]::Copy($bytes, $padded, $bytes.Length)
    $words = for ($i = 0; $i -lt 16384; $i += 4) {
        [BitConverter]::ToUInt32($padded, $i).ToString('x8')
    }
    [IO.File]::WriteAllLines("$($entry.Folder)/program.mem", [string[]]$words)
}
$sources = @(Get-ChildItem -LiteralPath $core -Filter '*.v' | Sort-Object Name | ForEach-Object FullName)
$sources += "$projectRoot/pds/tinyriscv_mes50hp/rtl/vendor/utils/gen_dff.v"
$sources += "$PSScriptRoot/memory_wait_tb.sv"
if ($Topology -eq 'System') {
    $sources += "$PSScriptRoot/memory_system_cpu_tb.sv"
    $sources += "$projectRoot/pds/tinyriscv_mes50hp/rtl/vendor/perips/rom.v"
    $sources += "$projectRoot/pds/tinyriscv_mes50hp/rtl/vendor/perips/ram.v"
}
New-Item -ItemType Directory -Path "$RecordRoot/source" | Out-Null
foreach ($file in $sources) {
    Copy-Item -LiteralPath $file -Destination "$RecordRoot/source"
}
Copy-Item -LiteralPath $PSCommandPath -Destination "$RecordRoot/source"
$sources | ForEach-Object { [pscustomobject]@{Path = $_
        SHA256                                     = (Get-FileHash -LiteralPath $_).Hash
    } } | Export-Csv -LiteralPath "$RecordRoot/rtl_manifest.csv" -NoTypeInformation
function TclPath([string]$Path) {
    '{' + $Path.Replace('\', '/') + '}'
}
$variants = if ($BranchPrediction -eq 'Both') {
    @('On', 'Off')
}
else {
    @($BranchPrediction)
}
foreach ($variant in $variants) {
    $runRoot = "$RecordRoot/$variant"
    New-Item -ItemType Directory -Path $runRoot | Out-Null
    $do = @('onerror {quit -f -code 1}', ('cd ' + (TclPath $runRoot)),
        'if {![file exists modelsim.ini]} {vmap -c}', 'vlib work', 'vmap work work')
    $enabled = if ($variant -eq 'On') {
        1
    }
    else {
        0
    }
    $top = if ($Topology -eq 'System') {
        'memory_system_cpu_tb'
    }
    else {
        'memory_wait_tb'
    }
    $do += 'vlog -sv +define+MES50HP_BP_ENABLE=' + $enabled + ' ' + (TclPath "+incdir+$core") + ' ' + (($sources | ForEach-Object { TclPath $_ }) -join ' ')
    $do += 'set result_file [open results.csv w]'
    $do += 'puts $result_file {Case,Seed,Passed}'
    foreach ($entry in $entries) {
        foreach ($seed in $entry.Seeds) {
            $caseRoot = "$runRoot/$($entry.Name)_$seed"
            New-Item -ItemType Directory -Path $caseRoot | Out-Null
            $do += 'transcript file ' + (TclPath "$caseRoot/transcript.log")
            $cacheParam = if ($Topology -eq 'System') {
                " -gCACHE=$CacheEnable"
            }
            elseif ($Quiesce) {
                ' -gHALT=1'
            }
            else {
                ''
            }
            if ($entry.Name -eq 'fetch_error') {
                $cacheParam += ' -gFETCH_FAULTS=1'
            }
            if ($entry.Name -eq 'memory_wait_backpressure') {
                $cacheParam += ' -gIRQ_BACKPRESSURE=1'
            }
            $do += "vsim -onfinish stop -voptargs=+acc -gSEED=$seed -gFAULTS=$($entry.Faults)$cacheParam work.$top " + (TclPath "+IMAGE=$($entry.Folder)/program.mem")
            $do += 'run -all'
            $do += 'set pass [examine -radix unsigned /' + $top + '/passed]'
            $do += 'puts $result_file "' + $entry.Name + ',' + $seed + ',$pass"'
            $do += 'flush $result_file'
            $do += 'if {$pass != 1} {quit -f -code 1}'
            $do += 'quit -sim'
        }
    }
    $do += 'close $result_file'
    $do += 'quit -f -code 0'
    [IO.File]::WriteAllLines("$runRoot/run.do", [string[]]$do)
    Push-Location -LiteralPath $runRoot
    try {
        & "$ModelSimBin/vsim.exe" -c -do 'do run.do' *> "$runRoot/runner.log"
        $code = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }
    $expected = ($entries | ForEach-Object { $_.Seeds.Count } | Measure-Object -Sum).Sum
    $rows = if (Test-Path -LiteralPath "$runRoot/results.csv") {
        @(Import-Csv -LiteralPath "$runRoot/results.csv")
    }
    else {
        @()
    }
    if ($code -ne 0 -or $rows.Count -ne $expected -or @($rows | Where-Object Passed -ne '1').Count -ne 0) {
        throw "Memory wait $variant failed: $runRoot"
    }
    Write-Output "Memory wait $variant : $($rows.Count)/$expected PASS"
}
[ordered]@{CompletedAt = (Get-Date -Format o)
    Scope              = 'Standalone WAIT_MEMORY=1 CPU; topology distinguishes delay model from real cache/DRM RTL; no full SoC or hardware result'
    Topology           = $Topology
    CacheEnable        = $(if ($Topology -eq 'System') {
            $CacheEnable
        }
        else {
            $null
        })
    Quiesce            = [bool]$Quiesce
    BranchPrediction   = $variants
    IncludeISA         = [bool]$IncludeISA
    Passed             = $true
} | ConvertTo-Json | Set-Content -LiteralPath "$RecordRoot/completion.json"
