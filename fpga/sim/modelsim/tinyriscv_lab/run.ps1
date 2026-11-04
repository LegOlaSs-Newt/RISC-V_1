# 模块说明：run。
# 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
# 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
# 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
# 许可位置：提交根 licenses，第三方固定原件保留自身声明。
param(
    [ValidateSet('Quick', 'ISA', 'Examples', 'Directed', 'Boundary', 'Board', 'CoreMark', 'Delivery', 'Advanced', 'Memory')][string]$Suite = 'Quick',
    [string]$Case = '',
    [ValidateSet('Port', 'Reference')][string]$RtlSet = 'Port',
    [ValidateSet('On', 'Off')][string]$BranchPrediction = 'On',
    [ValidateSet('Legacy', 'Wait')][string]$MemorySystem = 'Wait',
    [ValidateSet('On', 'Off')][string]$Cache = 'On',
    [ValidateSet('On', 'Off')][string]$EarlyLookup = 'On',
    [string]$RecordRoot = '',
    [string]$GccBin = '',
    [switch]$Gui,
    [switch]$Pause,
    [string]$ModelSimBin = 'D:\modeltech64_2020.4\win64'
)
$ErrorActionPreference = 'Stop'
if ($Pause -and !$Gui) {
    throw '-Pause requires -Gui' 
}
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$referenceRoot = Join-Path $projectRoot 'third_party/tinyriscv'
$portRoot = Join-Path $projectRoot 'pds/tinyriscv_mes50hp'
$exampleRoot = Join-Path $referenceRoot 'tests/example'
$rtlRoot = if ($RtlSet -eq 'Port') {
    "$portRoot/rtl/vendor" 
}
else {
    "$referenceRoot/rtl" 
}
# 用户已从提交根移除原始参考RTL；不把Reference请求悄悄改测Port。
if ($RtlSet -eq 'Reference' -and !(Test-Path -LiteralPath "$rtlRoot/core/tinyriscv.v")) {
    throw 'Reference RTL is not included in this public distribution. Use -RtlSet Port for r04.'
}
$clockHz = 50000000
if ($RtlSet -eq 'Port') {
    $config = [IO.File]::ReadAllText("$portRoot/rtl/mes50hp_config.vh")
    if ($config -notmatch 'MES50HP_CPU_HZ\s+(\d+)') {
        throw 'Missing board clock definition' 
    }
    $clockHz = [int]$Matches[1]
    $bootHeader = [IO.File]::ReadAllText("$portRoot/rtl/boot_image_path.vh")
    if ($bootHeader -notmatch 'MES50HP_BOOT_MEM\s+"([^"]+)"') {
        throw 'Cannot resolve the active Port boot image'
    }
    $portBootImage = [IO.Path]::GetFullPath($Matches[1])
    if (!(Test-Path -LiteralPath $portBootImage)) {
        throw 'Run board build.ps1 -Stage Software first' 
    }
}
$vsim = Join-Path $ModelSimBin 'vsim.exe'
. "$projectRoot/tools/environment.ps1"
$gccBin = Resolve-RiscVGccBin -Requested $GccBin -SubmissionRoot $projectRoot
$gcc = Join-Path $gccBin 'riscv-none-elf-gcc.exe'
if (!(Test-Path -LiteralPath $vsim)) {
    throw "ModelSim not found: $vsim" 
}
function Check-Exit([string]$What) {
    if ($LASTEXITCODE -ne 0) {
        throw "$What failed (exit $LASTEXITCODE)" 
    } 
}
function Tcl-Path([string]$Path) {
    if ($Path.Contains('{') -or $Path.Contains('}')) {
        throw 'Braces in paths are unsupported' 
    }
    '{' + $Path.Replace('\', '/') + '}'
}
$catalog = [ordered]@{
    pipeline            = @{Kind = 'asm'
        Mode          = 'protocol'
        Source        = "$PSScriptRoot/programs/pipeline.S"
    }
    pipeline_fail       = @{Kind = 'asm'
        Mode               = 'protocol'
        Source             = "$PSScriptRoot/programs/pipeline.S"
    }
    pipeline_valid      = @{Kind = 'asm'
        Mode                = 'protocol'
        Source              = "$PSScriptRoot/programs/pipeline_valid.S"
        PortOnly            = $true
    }
    exceptions          = @{Kind = 'asm'
        Mode            = 'protocol'
        Source          = "$PSScriptRoot/programs/exceptions.S"
        PortOnly        = $true
    }
    csr_semantics       = @{Kind = 'asm'
        Mode               = 'protocol'
        Source             = "$PSScriptRoot/programs/csr_semantics.S"
        PortOnly           = $true
    }
    interrupt_sources   = @{Kind = 'asm'
        Mode                   = 'irq'
        Source                 = "$PSScriptRoot/programs/interrupt_sources.S"
        PortOnly               = $true
    }
    interrupt_nested    = @{Kind = 'asm'
        Mode                  = 'protocol'
        Source                = "$PSScriptRoot/programs/interrupt_nested.S"
        PortOnly              = $true
    }
    branch_prediction   = @{Kind = 'asm'
        Mode                   = 'protocol'
        Source                 = "$PSScriptRoot/programs/branch_prediction.S"
        PortOnly               = $true
    }
    cache_system        = @{Kind = 'asm'
        Mode              = 'protocol'
        Source            = "$PSScriptRoot/programs/cache_system.S"
        PortOnly          = $true
        MemoryOnly        = $true
        GpioWrites        = 2
    }
    memory_statistics   = @{Kind = 'asm'
        Mode                   = 'protocol'
        Source                 = "$PSScriptRoot/programs/memory_statistics.S"
        PortOnly               = $true
        MemoryOnly             = $true
    }
    memory_soc          = @{Kind = 'asm'
        Mode            = 'protocol'
        Source          = "$PSScriptRoot/programs/memory_soc.S"
        Top             = 'memory_soc_tb'
        PortOnly        = $true
        MemoryOnly      = $true
    }
    jalr_odd            = @{Kind = 'asm'
        Mode          = 'protocol'
        Source        = "$PSScriptRoot/programs/jalr_odd.S"
    }
    jalr_edges          = @{Kind = 'asm'
        Mode            = 'protocol'
        Source          = "$PSScriptRoot/programs/jalr_edges.S"
    }
    jalr_bit1           = @{Kind = 'asm'
        Mode           = 'protocol'
        Source         = "$PSScriptRoot/programs/jalr_bit1.S"
        PortOnly       = $true
    }
    environment         = @{Kind = 'asm'
        Mode             = 'protocol'
        Source           = "$PSScriptRoot/programs/environment.S"
        PortOnly         = $true
    }
    gpio16              = @{Kind = 'board'
        Top         = 'gpio16_tb'
        Marker      = 'GPIO16_PASS'
        PortOnly    = $true
    }
    console_boot        = @{Kind = 'board'
        Top               = 'gpio_console_tb'
        Marker            = 'GPIO_CONSOLE_PASS'
        PortOnly          = $true
        Console           = $true
        Download          = 0
    }
    console_loader      = @{Kind = 'board'
        Top                 = 'gpio_console_tb'
        Marker              = 'GPIO_CONSOLE_PASS'
        PortOnly            = $true
        Console             = $true
        Download            = 1
    }
    rom_probe           = @{Kind = 'board'
        Top            = 'rom_boot_probe_tb'
        Marker         = 'ROM_PROBE_PASS'
        PortOnly       = $true
        RomProbe       = $true
        InjectMismatch = 0
    }
    rom_probe_fail      = @{Kind = 'board'
        Top                 = 'rom_boot_probe_tb'
        Marker              = 'ROM_PROBE_PASS'
        PortOnly            = $true
        RomProbe            = $true
        InjectMismatch      = 1
    }
    simple              = @{Kind = 'c'
        Mode        = 'protocol'
        Source      = "$exampleRoot/simple/main.c"
    }
    gpio                = @{Kind = 'c'
        Mode      = 'gpio'
        Source    = "$exampleRoot/gpio/main.c"
    }
    uart_tx             = @{Kind = 'c'
        Mode         = 'uart_tx'
        Source       = "$exampleRoot/uart_tx/main.c"
    }
    uart_rx             = @{Kind = 'c'
        Mode         = 'uart_rx'
        Source       = "$exampleRoot/uart_rx/main.c"
    }
    timer_int           = @{Kind = 'c'
        Mode           = 'timer'
        Source         = $(if ($RtlSet -eq 'Port') {
                "$portRoot/sw/timer_irq/main.c" 
            }
            else {
                "$exampleRoot/timer_int/main.c" 
            })
    }
    spi_loopback        = @{Kind = 'c'
        Mode              = 'spi'
        Source            = "$PSScriptRoot/programs/spi_loopback.c"
    }
    board_boot          = @{Kind = 'board'
        Top             = 'mes50hp_tb'
        Marker          = 'MES50HP_SIM_PASS'
    }
    uart_loader         = @{Kind = 'board'
        Top              = 'uart_loader_tb'
        Marker           = 'UART_LOADER_PASS'
    }
    coremark            = @{Kind = 'coremark'
        Mode          = 'coremark'
        RunType       = 'Performance'
        MaxCycles     = 20000000
    }
    coremark_validation = @{Kind = 'coremark'
        Mode                     = 'coremark'
        RunType                  = 'Validation'
        MaxCycles                = 20000000
    }
}
if ($Case) {
    $names = @($Case)
}
else {
    $names = switch ($Suite) {
        'Quick' {
            @('pipeline', 'simple') 
        }
        'Directed' {
            @('pipeline') 
        }
        'Advanced' {
            @('pipeline_valid', 'exceptions', 'csr_semantics', 'interrupt_sources', 'interrupt_nested', 'branch_prediction') 
        }
        'Memory' {
            @('cache_system', 'memory_statistics', 'memory_soc') 
        }
        'Boundary' {
            @('jalr_odd', 'jalr_edges', 'jalr_bit1') 
        }
        'Delivery' {
            @('environment', 'gpio16', 'console_boot', 'console_loader') 
        }
        'Examples' {
            @('simple', 'gpio', 'uart_tx', 'uart_rx', 'timer_int', 'spi_loopback') 
        }
        'Board' {
            @('board_boot', 'uart_loader') 
        }
        'CoreMark' {
            @('coremark', 'coremark_validation') 
        }
        'ISA' {
            @(Get-ChildItem -LiteralPath "$referenceRoot/tests/isa/generated" -Filter '*.bin' | Sort-Object Name | ForEach-Object BaseName) 
        }
    }
}
$entries = @(foreach ($name in $names) {
        if ($catalog.Contains($name)) {
            $entry = @{Name = $name }
            foreach ($key in $catalog[$name].Keys) {
                $entry[$key] = $catalog[$name][$key] 
            }
            [pscustomobject]$entry
        }
        else {
            $binary = Join-Path $referenceRoot "tests/isa/generated/$name.bin"
            if (!(Test-Path -LiteralPath $binary)) {
                throw "Unknown case: $name" 
            }
            [pscustomobject]@{Name = $name; Kind = 'bin'; Mode = 'protocol'; Source = $binary }
        }
    })
if ($entries.Count -eq 0) {
    throw 'No test programs found' 
}
if ($Gui -and $entries.Count -ne 1) {
    throw 'Use -Case <name> with -Gui to inspect one program' 
}
if (@($entries | Where-Object Kind -eq 'board').Count -gt 0 -and $RtlSet -ne 'Port') {
    throw 'Board cases require -RtlSet Port' 
}
if (@($entries | Where-Object { $_.PortOnly }).Count -gt 0 -and $RtlSet -ne 'Port') {
    throw 'Extended delivery cases require -RtlSet Port' 
}
if (@($entries | Where-Object { $_.MemoryOnly }).Count -gt 0 -and $MemorySystem -ne 'Wait') {
    throw 'Memory cases require -MemorySystem Wait'
}
# CoreMark/coremark collide on Windows; keep suite and GUI case records separate.
$runName = if ($Case) {
    $Case 
}
elseif ($Suite -eq 'CoreMark') {
    'CoreMarkSmoke' 
}
else {
    $Suite 
}
if ($runName -notmatch '^[A-Za-z0-9_-]+$') {
    throw 'Invalid output name' 
}
$runRoot = Join-Path $projectRoot "work/tinyriscv_lab/$RtlSet/$runName"
if ($RecordRoot) {
    $runRoot = Join-Path ([IO.Path]::GetFullPath($RecordRoot)) $runName
    if (Test-Path -LiteralPath $runRoot) {
        throw "Use a new record, preserving $runRoot"
    }
}
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null

$consoleBuilt = $false
foreach ($entry in $entries) {
    $caseRoot = Join-Path $runRoot $entry.Name
    New-Item -ItemType Directory -Path $caseRoot -Force | Out-Null
    $entry | Add-Member -NotePropertyName Output -NotePropertyValue $caseRoot
    if ($entry.Kind -eq 'board') {
        if ($entry.Console) {
            if (!$consoleBuilt) {
                & "$portRoot/sw/gpio_console/build.ps1" -ClockHz $clockHz -GccBin $gccBin
                $consoleBuilt = $true 
            }
            Copy-Item -LiteralPath "$portRoot/build_r04/gpio_console/console.bin", "$portRoot/build_r04/gpio_console/console.elf", "$portRoot/build_r04/gpio_console/console.mem", "$portRoot/build_r04/gpio_console/console.bytes", "$portRoot/build_r04/gpio_console/console.dis", "$portRoot/build_r04/gpio_console/build_manifest.json" -Destination $caseRoot -Force
        }
        if ($entry.RomProbe) {
            & "$portRoot/sw/gpio_console/build_rom_probe.ps1" -OutputRoot $caseRoot -GccBin $gccBin 
        }
        continue
    }
    $binary = $entry.Source
    if ($entry.Kind -eq 'coremark') {
        & "$projectRoot/sw/coremark/build.ps1" -Profile Smoke -RunType $entry.RunType -ClockHz $clockHz -GccBin $gccBin
        $firmwareRoot = "$projectRoot/work/coremark/Firmware/Smoke/$($entry.RunType)"
        foreach ($suffix in @('elf', 'bin', 'dis', 'abi.dis', 'map')) {
            Copy-Item -LiteralPath "$firmwareRoot/coremark.$suffix" -Destination "$caseRoot/program.$suffix" -Force
        }
        Copy-Item -LiteralPath "$firmwareRoot/build_manifest.json" -Destination "$caseRoot/build_manifest.json" -Force
        $binary = "$caseRoot/program.bin"
        $symbols = @(& (Join-Path $gccBin 'riscv-none-elf-nm.exe') -n "$caseRoot/program.elf")
        Check-Exit 'Read CoreMark symbols'
        $symbols | Set-Content -LiteralPath "$caseRoot/program_symbols.txt"
        $coremarkLogs = [Collections.Generic.List[string]]::new()
        $coremarkWaves = [Collections.Generic.List[string]]::new()
        $coremarkWaves.Add('# Generated from this ELF; do not reuse addresses with another build.')
        $coremarkWaves.Add('view wave')
        foreach ($row in $symbols) {
            if ($row -match '^([0-9a-fA-F]+)\s+[bBdD]\s+(coremark_(phase|crc_ok|duration_ok|formal_valid|iterations|cycles_hi|cycles_lo))$') {
                $address = [Convert]::ToUInt32($Matches[1], 16)
                $label = $Matches[2]
                $index = [int](($address - 0x10000000) / 4)
                if ($index -lt 0 -or $index -ge 4096) {
                    throw "CoreMark symbol outside RAM: $label" 
                }
                $signal = '/tinyriscv_lab_tb/dut/u_ram/_ram[' + $index + ']'
                $coremarkLogs.Add('log ' + (Tcl-Path $signal))
                $coremarkWaves.Add('add wave -group CoreMark -radix unsigned -label ' + $label + ' ' + (Tcl-Path $signal))
            }
        }
        if ($coremarkLogs.Count -ne 7) {
            throw 'CoreMark debug symbols missing' 
        }
        [IO.File]::WriteAllLines("$caseRoot/log_coremark.do", $coremarkLogs)
        [IO.File]::WriteAllLines("$caseRoot/wave_coremark.do", @($coremarkWaves) + @($coremarkLogs))
    }
    if ($entry.Kind -eq 'asm' -or $entry.Kind -eq 'c') {
        if (!(Test-Path -LiteralPath $gcc)) {
            throw "GCC not found: $gcc" 
        }
        $elf = "$caseRoot/program.elf"
        $binary = "$caseRoot/program.bin"
        $flags = @('-march=rv32im_zicsr', '-mabi=ilp32', '-O0', '-g', '-ffreestanding', '-nostdlib', '-fno-builtin', '-fno-pic', '-fno-stack-protector', '-ffixed-s10', '-ffixed-s11', '-mno-relax', '-DSIMULATION', '-Wl,--no-relax', "-Wl,-Map,$caseRoot/program.map")
        if ($RtlSet -eq 'Port' -and $MemorySystem -eq 'Wait') {
            $flags += '-DLAB_MEMORY_SYSTEM'
        }
        if ($entry.Kind -eq 'asm') {
            if ($entry.Name -eq 'pipeline_fail') {
                $flags += '-DLAB_INTENTIONAL_FAIL' 
            }
            & $gcc @flags -T "$referenceRoot/tests/isa/link.ld" $entry.Source -o $elf
        }
        else {
            $swSources = @("$exampleRoot/start.S", "$exampleRoot/trap_entry.S", "$exampleRoot/init.c", "$exampleRoot/trap_handler.c", "$exampleRoot/lib/utils.c", $entry.Source)
            if ($RtlSet -eq 'Port' -and $entry.Name -eq 'timer_int') {
                $swSources = @($swSources | ForEach-Object { if ($_ -eq "$exampleRoot/trap_handler.c") {
                            "$portRoot/sw/timer_irq/trap_handler.c" 
                        }
                        else {
                            $_ 
                        } })
            }
            if ($entry.Mode -eq 'uart_tx' -or $entry.Mode -eq 'uart_rx') {
                $swSources += @("$exampleRoot/lib/uart.c", "$exampleRoot/lib/xprintf.c") 
            }
            if ($entry.Mode -eq 'spi') {
                $swSources += "$exampleRoot/lib/spi.c" 
            }
            & $gcc @flags "-I$exampleRoot" -T "$exampleRoot/link.lds" @swSources -lgcc -o $elf
        }
        Check-Exit "Build $($entry.Name)"
        & (Join-Path $gccBin 'riscv-none-elf-objcopy.exe') -O binary $elf $binary
        Check-Exit 'Convert binary'
        & (Join-Path $gccBin 'riscv-none-elf-objdump.exe') -d -M 'numeric,no-aliases' $elf | Set-Content -LiteralPath "$caseRoot/program.dis"
        Check-Exit 'Disassemble program'
        & (Join-Path $gccBin 'riscv-none-elf-objdump.exe') -d -M no-aliases $elf | Set-Content -LiteralPath "$caseRoot/program.abi.dis"
        Check-Exit 'Disassemble program with ABI names'
    }
    $bytes = [IO.File]::ReadAllBytes($binary)
    if ($bytes.Length -eq 0 -or $bytes.Length -gt 16384) {
        throw "Image exceeds 16 KiB: $binary" 
    }
    $padded = [byte[]]::new([int]([Math]::Ceiling($bytes.Length / 4.0) * 4))
    [Array]::Copy($bytes, $padded, $bytes.Length)
    $words = [Collections.Generic.List[string]]::new()
    for ($offset = 0; $offset -lt $padded.Length; $offset += 4) {
        $words.Add([BitConverter]::ToUInt32($padded, $offset).ToString('x8')) 
    }
    while ($words.Count -lt 4096) {
        $words.Add('00000013') 
    }
    [IO.File]::WriteAllLines("$caseRoot/inst.data", $words)
}

$originalSources = @(Get-ChildItem -LiteralPath $rtlRoot -Recurse -Filter '*.v' | Sort-Object FullName | ForEach-Object FullName)
if ($RtlSet -eq 'Port') {
    $originalSources += "$portRoot/rtl/tinyriscv_mes50hp_top.v" 
}
$manifest = foreach ($source in $originalSources) {
    [pscustomobject]@{RtlSet = $RtlSet
        Path                 = $source
        SHA256               = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
    } 
}
$manifest | Export-Csv -LiteralPath "$runRoot/rtl_manifest.csv" -NoTypeInformation -Encoding utf8
$sources = $originalSources
$compatRoot = Join-Path $runRoot 'compat'
New-Item -ItemType Directory -Path $compatRoot -Force | Out-Null
foreach ($compat in @(@{File = 'full_handshake_tx.v'; Variable = 'ack' }, @{File = 'full_handshake_rx.v'; Variable = 'req' })) {
    $original = [IO.Path]::GetFullPath("$rtlRoot/utils/$($compat.File)")
    $sourceText = [IO.File]::ReadAllText($original)
    $pattern = '(?m)^[ \t]*reg[ \t]+' + $compat.Variable + ';[ \t]*\r?\n'
    if ([regex]::Matches($sourceText, $pattern).Count -ne 1) {
        throw "Unexpected declaration in $original" 
    }
    $sourceText = [regex]::Replace($sourceText, $pattern, '')
    $marker = '    localparam STATE_IDLE'
    if (!$sourceText.Contains($marker)) {
        throw 'Missing compatibility insertion marker' 
    }
    $sourceText = $sourceText.Replace($marker, ('    reg ' + $compat.Variable + "; // Declaration order only: ModelSim compatibility.`n`n" + $marker))
    $staged = Join-Path $compatRoot $compat.File
    [IO.File]::WriteAllText($staged, $sourceText)
    $sources = @($sources | ForEach-Object { if ([IO.Path]::GetFullPath($_) -eq $original) {
                $staged 
            }
            else {
                $_ 
            } })
}
$metadata = [ordered]@{
    CreatedAt        = (Get-Date -Format o)
    RtlSet           = $RtlSet
    RtlRoot          = $rtlRoot
    ClockHz          = $clockHz

    Simulator        = $vsim
    Cases            = @($entries.Name)
    Pause            = [bool]$Pause

    Note             = 'compat files change declaration order only; the original RTL is not edited'
    BranchPrediction = $(if ($RtlSet -eq 'Port') {
            $BranchPrediction 
        }
        else {
            'NotApplicable' 
        })
    MemorySystem     = $(if ($RtlSet -eq 'Port') {
            $MemorySystem 
        }
        else {
            'NotApplicable' 
        })
    Cache            = $(if ($RtlSet -eq 'Port' -and $MemorySystem -eq 'Wait') {
            $Cache 
        }
        else {
            'NotApplicable' 
        })
    EarlyLookup      = $(if ($RtlSet -eq 'Port' -and $MemorySystem -eq 'Wait' -and $Cache -eq 'On') {
            $EarlyLookup
        }
        else {
            'Off'
        })
}
if ($RtlSet -eq 'Port') {
    $metadata.BootImagePath = $portBootImage
    $metadata.BootImageSHA256 = (Get-FileHash -LiteralPath $portBootImage).Hash 
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath "$runRoot/run_meta.json" -Encoding utf8

$do = [Collections.Generic.List[string]]::new()
$do.Add('onerror {quit -f -code 1}')
$do.Add('cd ' + (Tcl-Path $runRoot))
$do.Add('transcript file compile.log')
$do.Add('if {![file exists modelsim.ini]} {vmap -c}')
$do.Add('if {![file isdirectory work]} {vlib work}')
$do.Add('vmap work work')
$includes = @((Tcl-Path ("+incdir+$rtlRoot/core")))
if ($RtlSet -eq 'Port') {
    $includes += (Tcl-Path ("+incdir+$portRoot/rtl")) 
}
$sourceArgs = ($sources | ForEach-Object { Tcl-Path $_ }) -join ' '
$bpDefine = if ($RtlSet -eq 'Port') {
    '+define+MES50HP_BP_ENABLE=' + $(if ($BranchPrediction -eq 'On') {
            '1' 
        }
        else {
            '0' 
        }) 
}
else {
    '' 
}
if ($RtlSet -eq 'Port') {
    $bpDefine += ' +define+MES50HP_MEMORY_SYSTEM=' + $(if ($MemorySystem -eq 'Wait') {
            '1'
        }
        else {
            '0'
        }) + ' +define+MES50HP_CACHE_ENABLE=' + $(if ($Cache -eq 'On') {
            '1'
        }
        else {
            '0'
        })
}
if ($RtlSet -eq 'Port') {
    $bpDefine += ' +define+MES50HP_EARLY_D_LOOKUP=' + $(if ($EarlyLookup -eq 'On' -and $MemorySystem -eq 'Wait' -and $Cache -eq 'On') {
            '1'
        }
        else {
            '0'
        })
}
$do.Add('vlog -work work ' + $bpDefine + ' ' + ($includes -join ' ') + ' ' + $sourceArgs)
$benchSources = @("$PSScriptRoot/tinyriscv_lab_tb.sv")
if ($RtlSet -eq 'Port') {
    $benchSources += @("$portRoot/sim/mes50hp_tb.sv", "$portRoot/sim/uart_loader_tb.sv", "$portRoot/sim/gpio16_tb.sv", "$portRoot/sim/gpio_console_tb.sv", "$portRoot/sim/rom_boot_probe_tb.sv", "$PSScriptRoot/memory_soc_tb.sv") 
}
$portDefine = if ($RtlSet -eq 'Port') {
    '+define+LAB_PORT' 
}
else {
    '' 
}
if ($RtlSet -eq 'Port' -and $MemorySystem -eq 'Wait') {
    $portDefine += ' +define+LAB_WAIT_MEMORY +define+LAB_CACHE_ENABLE=' + $(if ($Cache -eq 'On') {
            '1'
        }
        else {
            '0'
        })
}
$do.Add("vlog -sv -work work $portDefine +define+LAB_CLOCK_HZ=$clockHz " + ($includes -join ' ') + ' ' + (($benchSources | ForEach-Object { Tcl-Path $_ }) -join ' '))
$do.Add('set failed 0')
$do.Add('set result_file [open results.csv w]')
$do.Add('puts $result_file {Case,Passed}')
foreach ($entry in $entries) {
    $top = if ($entry.Top) {
        $entry.Top 
    }
    else {
        'tinyriscv_lab_tb' 
    }
    $caseLog = "$($entry.Output)/transcript.log"
    $do.Add('transcript file ' + (Tcl-Path $caseLog))
    $plusargs = if ($entry.Kind -eq 'board') {
        '' 
    }
    else {
        (Tcl-Path ("+IMAGE=$($entry.Output)/inst.data")) + ' ' + (Tcl-Path ("+MODE=$($entry.Mode)")) 
    }
    if ($null -ne $entry.GpioWrites) {
        $plusargs += ' +GPIO_EXPECT_WRITES=' + $entry.GpioWrites
    }
    if ($entry.Console) {
        $imageSize = (Get-Item -LiteralPath "$($entry.Output)/console.bin").Length
        $plusargs = (Tcl-Path ("+CONSOLE_MEM=$($entry.Output)/console.mem")) + ' ' + (Tcl-Path ("+CONSOLE_BYTES=$($entry.Output)/console.bytes")) + " +IMAGE_BYTES=$imageSize +DOWNLOAD=$($entry.Download)"
    }
    if ($entry.RomProbe) {
        $imageSize = (Get-Item -LiteralPath "$($entry.Output)/probe.bin").Length
        $plusargs = (Tcl-Path ("+PROBE_BYTES=$($entry.Output)/probe.bytes")) + ' ' + (Tcl-Path ("+BOOT_IMAGE=$($entry.Output)/boot_before.mem")) + " +IMAGE_BYTES=$imageSize +INJECT_MISMATCH=$($entry.InjectMismatch)"
    }
    if ($entry.Kind -eq 'coremark') {
        $plusargs += ' ' + (Tcl-Path ("+MAX_CYCLES=$($entry.MaxCycles)")) + ' ' + (Tcl-Path ("+UART_LOG=$($entry.Output)/uart.log"))
    }
    $do.Add('vsim -onfinish stop -voptargs=+acc -wlf ' + (Tcl-Path "$($entry.Output)/sim.wlf") + " work.$top $plusargs")
    if ($entry.Kind -eq 'board') {
        $do.Add("log /$top/clk /$top/uart_tx /$top/led /$top/dut/soc_rst_n /$top/dut/u_soc/m3_req_i /$top/dut/u_soc/u_tinyriscv/pc_pc_o")
        if ($entry.Name -eq 'uart_loader') {
            $do.Add("log /$top/uart_rx /$top/ack_count") 
        }
        if ($Gui) {
            $do.Add('view wave')
            $do.Add("add wave /$top/clk /$top/uart_tx /$top/led /$top/dut/soc_rst_n /$top/dut/u_soc/m3_req_i")
            $do.Add("add wave -radix hexadecimal /$top/dut/u_soc/u_tinyriscv/pc_pc_o")
            if ($entry.Name -eq 'uart_loader') {
                $do.Add("add wave /$top/uart_rx /$top/ack_count") 
            }
        }
    }
    elseif ($top -ne 'tinyriscv_lab_tb') {
        $do.Add("log /$top/clk /$top/rst /$top/active")
    }
    else {
        $do.Add('log /tinyriscv_lab_tb/*')
        if ($entry.Kind -eq 'coremark') {
            $do.Add('do ' + (Tcl-Path "$($entry.Output)/log_coremark.do")) 
        }
        if ($Gui) {
            $do.Add('view wave')
            $do.Add('do ' + (Tcl-Path "$PSScriptRoot/wave_cpu.do"))
            $do.Add('do ' + (Tcl-Path "$PSScriptRoot/wave_peripherals.do"))
            if ($entry.Kind -eq 'coremark') {
                $do.Add('do ' + (Tcl-Path "$($entry.Output)/wave_coremark.do")) 
            }
        }
    }
    if ($Pause) {
        $do.Add('run 0 ns')
        if ($entry.Kind -eq 'coremark') {
            $do.Add('puts {LAB_PAUSED: CoreMark uses milliseconds; use run 10 ms, then run -all. Smoke checks CRC only, not a formal score.}')
        }
        else {
            $do.Add('puts {LAB_PAUSED: use run 200 ns, then run -all; inspect transcript and waves.}')
        }
    }
    else {
        $do.Add('run -all')
        if ($entry.Kind -ne 'board') {
            $do.Add('set pass [examine -radix unsigned /' + $top + '/passed]') 
        }
        $do.Add('transcript file compile.log')
        if ($entry.Kind -eq 'board') {
            $do.Add('set lf [open ' + (Tcl-Path $caseLog) + ' r]')
            $do.Add('set contents [read $lf]')
            $do.Add('close $lf')
            $do.Add('set pass [expr {[string first {' + $entry.Marker + '} $contents] >= 0}]')
        }
        $do.Add('puts $result_file "' + $entry.Name + ',$pass"')
        $do.Add('flush $result_file')
        $do.Add('if {$pass != 1} {incr failed}')
        $do.Add('puts "LAB_RESULT ' + $entry.Name + ' passed=$pass"')
        if ($Gui) {
            # $finish can switch the GUI to the testbench source pane.
            $do.Add('view wave')
            $do.Add('wave zoom full')
        }
        else {
            $do.Add('quit -sim') 
        }
    }
}
$do.Add('close $result_file')
if (!$Gui) {
    $do.Add('quit -f -code [expr {$failed > 0}]') 
}
[IO.File]::WriteAllLines("$runRoot/run.do", $do)
if ($entries.Count -eq 1 -and $entries[0].Kind -ne 'board') {
    $one = $entries[0]
    $imageForPds = "$($one.Output)/inst.data".Replace('\', '/')
    $wrapper = @(
        '// Generated learning entry: absolute image path, no simulator plusargs required.',
        'module tinyriscv_pds_lesson_tb;',
        ('    tinyriscv_lab_tb #(.CLOCK_HZ(' + $clockHz + '), .DEFAULT_MAX_CYCLES(' + $(if ($one.Kind -eq 'coremark') {
                $one.MaxCycles 
            }
            else {
                250000 
            }) + '), .DEFAULT_IMAGE("' + $imageForPds + '"), .DEFAULT_MODE("' + $one.Mode + '")) uut();'),
        '    // PDS adds "wave *" at this wrapper scope; expose useful signals here.',
        '    wire clk = uut.clk;',
        '    wire rst = uut.rst;',
        '    wire [31:0] pc = uut.pc;',
        '    wire [31:0] ex_pc = uut.ex_pc;',
        '    wire [31:0] ex_inst = uut.ex_inst;',
        '    wire wb_we = uut.wb_we;',
        '    wire [4:0] wb_rd = uut.wb_rd;',
        '    wire [31:0] wb_data = uut.wb_data;',
        '    wire [31:0] x26 = uut.x26;',
        '    wire [31:0] x27 = uut.x27;',
        '    wire passed = uut.passed;',
        'endmodule'
    )
    [IO.File]::WriteAllLines("$runRoot/pds_entry_tb.sv", $wrapper)
    [IO.File]::WriteAllLines("$runRoot/pds_rtl.f", [string[]]@($sources | ForEach-Object { '"' + $_.Replace('\', '/') + '"' }))
    $pdsWaves = @('view wave', 'log /tinyriscv_pds_lesson_tb/uut/*')
    foreach ($waveFile in @('wave_cpu.do', 'wave_peripherals.do')) {
        $pdsWaves += [IO.File]::ReadAllLines("$PSScriptRoot/$waveFile") | ForEach-Object { $_.Replace('/tinyriscv_lab_tb/', '/tinyriscv_pds_lesson_tb/uut/') }
    }
    if ($one.Kind -eq 'coremark') {
        $pdsWaves += [IO.File]::ReadAllLines("$($one.Output)/wave_coremark.do") | ForEach-Object { $_.Replace('/tinyriscv_lab_tb/', '/tinyriscv_pds_lesson_tb/uut/') }
    }
    [IO.File]::WriteAllLines("$runRoot/pds_wave.do", [string[]]$pdsWaves)
}
Write-Output "RTL=$RtlSet clock=$clockHz Hz; cases=$($entries.Name -join ',')"
Write-Output "Outputs: $runRoot"
Push-Location -LiteralPath $runRoot
try {
    $modeArg = if ($Gui) {
        '-gui' 
    }
    else {
        '-c' 
    }
    & $vsim $modeArg -do 'do run.do'
    $simulationExit = $LASTEXITCODE
    if (Test-Path -LiteralPath "$runRoot/results.csv") {
        $rows = @(Import-Csv -LiteralPath "$runRoot/results.csv")
        $rows | Format-Table -AutoSize
        $passCount = @($rows | Where-Object Passed -eq '1').Count
        Write-Output "Summary: $passCount/$($rows.Count) PASS"
    }
    if (!$Gui -and $simulationExit -ne 0) {
        throw "Simulation failed; inspect $runRoot/results.csv and per-case transcript.log" 
    }
}
finally {
    Pop-Location 
}
