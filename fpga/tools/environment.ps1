# 提交根目录中的外部工具定位。优先使用调用方参数；工具链本体不进入提交包。
function Resolve-RiscVGccBin {
    param([string]$Requested = '', [string]$SubmissionRoot = '')
    $candidates = @()
    if ($Requested) {
        $candidates += $Requested 
    }
    elseif ($env:RISCV_GCC_BIN) {
        $candidates += $env:RISCV_GCC_BIN 
    }
    else {
        $command = Get-Command riscv-none-elf-gcc.exe -ErrorAction SilentlyContinue
        if ($command) {
            $candidates += (Split-Path -Parent $command.Source) 
        }
        if ($SubmissionRoot) {
            $candidates += "$SubmissionRoot/../xpacks/@xpack-dev-tools/riscv-none-elf-gcc/.content/bin"
        }
    }
    foreach ($candidate in $candidates) {
        $resolved = [IO.Path]::GetFullPath($candidate)
        if (Test-Path -LiteralPath "$resolved/riscv-none-elf-gcc.exe") {
            return $resolved 
        }
    }
    throw 'Specify -GccBin or RISCV_GCC_BIN with the xPack RISC-V GCC 15.2.0 bin directory.'
}
