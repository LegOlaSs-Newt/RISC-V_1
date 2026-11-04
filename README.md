# RISC-V_1

基于 TinyRISC-V 的三级 RV32IM 处理器，面向紫光同创 MES50HP（PGL50H-6IFBG484）。当前公开版本为 r04：27 MHz 直连板载晶振、两路 I/D Cache、动态分支预测、机器态异常/中断和数据提前查询。

这是可构建的精简完整工程，包含 CPU、板级适配、软件、必要测试和使用说明。研发历史、比赛报告、实物照片、视频、签署文件和原始详细测试记录不随仓库发布。原项目从三级流水线学习与板级移植开始，逐步完成本版本的扩展。

## 功能与边界

| 项目 | 当前实现 |
|---|---|
| ISA / 流水线 | RV32IM，机器态 CSR，IF/ID/EX 三级顺序执行 |
| 分支控制 | 128 项带标签 BTB、两位方向计数器、8 项 RAS，误预测重定向 |
| 异常与中断 | 精确提交，机器态异常、软件/定时器/外部中断，MRET |
| I/D Cache | 各 2 KiB、2 路、32 组、32 字节行，每组 1 位 LRU |
| 写策略 | D 写直达、不写分配；MMIO 绕过缓存 |
| 存储 | 程序区 / RAM 各 16 KiB；同步片内 DRM，一次整行请求返回 8 个数据拍 |
| r04 提前查询 | 译码阶段准备只读查询，执行阶段核对完整地址、归属与有效条件后采用；不满足则回退 |
| 外设 / 调试 | UART、16 路 GPIO、Timer、SPI，串口程序下载 |
| 默认配置 | Wait / Cache On / BP On / EarlyLookup On，27 MHz，FixHold，placement seed 1 |

没有 DDR、MMU、U/S 态、AI 加速器或已验收的 Flash 掉电启动。Cache 为阻塞式；提前查询不让 store 或 MMIO 推测执行。板级 CPU 软件 JTAG 引脚未启用；FPGA JTAG 配置与 CPU 软件 JTAG 是不同功能。

## 目录

```text
fpga/
├─ pds/tinyriscv_mes50hp/       RTL、约束、板级程序、构建和下载
├─ sim/modelsim/tinyriscv_lab/  Port 回归与定向测试
├─ sw/coremark/                固定算法、平台移植、构建和计分
├─ third_party/tinyriscv/      必需 ISA / 示例测试及许可
├─ tools/                     外部工具定位
└─ licenses/                  原始声明和逐文件来源
docs/                         设计和本次公开副本验证摘要
LICENSE                       项目原创部分的 MIT 许可
NOTICE.md                     第三方许可范围
```

## 环境

脚本面向 Windows 和 PowerShell 7。外部安装：xPack RISC-V GCC 15.2.0、ModelSim 2020.4、Python 3，以及 Pango PDS 2022.2-SP6.4。板级脚本的 `-Stage Sim` 另需 Icarus Verilog。编译目标为 `rv32im_zicsr` / `ilp32`，器件为 Logos / PGL50H / -6 / FBG484。

工具安装文件不随仓库发布。以下路径是示例，请替换为自己的安装位置；后续命令在仓库的 `fpga` 目录执行。

```powershell
Set-Location ./fpga
$gcc = 'C:/Tools/riscv-none-elf-gcc/bin'
$modelsim = 'C:/Tools/modeltech64_2020.4/win64'
$pds = 'C:/pango/PDS_2022.2-SP6.4'
```

## 从源码构建

先构建默认演示程序，生成本机可用的启动镜像路径：

```powershell
./pds/tinyriscv_mes50hp/build.ps1 -Stage Software -GccBin $gcc
```

最小仿真：

```powershell
./sim/modelsim/tinyriscv_lab/run.ps1 -Suite Quick -RtlSet Port -GccBin $gcc -ModelSimBin $modelsim -RecordRoot ./work/quick_r01
```

完整默认配置回归含 75 项正常检查及 1 项应被拒绝的故意错误检查：

```powershell
./sim/modelsim/tinyriscv_lab/run_delivery.ps1 -GccBin $gcc -ModelSimBin $modelsim -RecordRoot ./work/delivery_r01
```

七项提前查询检查：

```powershell
python ./sim/modelsim/tinyriscv_lab/run_early_directed.py --gcc-bin $gcc --modelsim-bin $modelsim --record ./work/early_r01
```

重跑时选择新的记录目录。原始 Reference RTL 未包含，请使用 `-RtlSet Port`。

生成 FPGA 位流：

```powershell
./pds/tinyriscv_mes50hp/build.ps1 -Stage Bitstream -GccBin $gcc -PdsRoot $pds
```

默认输出在 `pds/tinyriscv_mes50hp/build_submission_r01/`。脚本检查工具日志和布线后时序，不将时序失败位流视为合格产物。GUI 入口为该目录中的 `tinyriscv_mes50hp_r04.pds`；首次打开前仍先执行 Software 构建。源码修改后须重新实现。

## 板卡运行

MES50HP使用K21的27 MHz时钟。先核对自己的板卡、供电和连接；其他板卡需修改约束。KEY1复位，KEY2切换下载模式，LED2表示下载模式。默认Demo输出阶乘校验和心跳，LED3/4每250 ms交替；LED1为独立硬件心跳。

配置自己生成的SRAM位流（不写配置Flash）：

```powershell
./pds/tinyriscv_mes50hp/configure_sram.ps1 -Bitstream ./pds/tinyriscv_mes50hp/build_submission_r01/generate_bitstream/tinyriscv_mes50hp_top.sbit -PdsRoot $pds
```

配置需要可用的PDS JTAG服务，也可用PDS配置界面。通过串口换程序时，先按KEY2使LED2亮，再下载BIN，完成后按KEY2退出下载模式执行：

```powershell
./pds/tinyriscv_mes50hp/download.ps1 -Port COM7 -Binary ./pds/tinyriscv_mes50hp/build_submission_r01/hello.bin
```

`.sbit`建立FPGA硬件并可带初始程序；`.bin`是CPU执行的软件。更换BIN不会改变CPU或GPIO的电路结构。参见[地址与LED说明](docs/design.md)。

## CoreMark

固定EEMBC CoreMark v1.01，六份算法由SOURCE.json校验，保留上游许可。Smoke验证CRC，不能作正式成绩。正式P/V各2000次，实际运行不少于10秒：

```powershell
./sw/coremark/build.ps1 -Profile Formal -RunType Performance -Iterations 2000 -ClockHz 27000000 -GccBin $gcc -OutputRoot ./work/formal_p_r01
./sw/coremark/build.ps1 -Profile Formal -RunType Validation -Iterations 2000 -ClockHz 27000000 -GccBin $gcc -OutputRoot ./work/formal_v_r01
```

下载对应BIN后，在退出下载模式前开启监听：

```powershell
./sw/coremark/capture.ps1 -Port COM7 -Output ./work/formal_p_r01/uart.log
```

Validation使用另一组新日志。计分依据实际频率和完整64位周期；主成绩采用Performance，Validation验证另一组种子。编译不等于板测。

完成真实P/V采集后，传入各自匹配的构建清单。LUT数量填写本次匹配硬件的实际布线后结果；下面8448仅适用于资源仍为该值的r04正式配置：

```powershell
./sw/coremark/score.ps1 -PerformanceLog ./work/formal_p_r01/uart.log -ValidationLog ./work/formal_v_r01/uart.log -PerformanceManifest ./work/formal_p_r01/build_manifest.json -ValidationManifest ./work/formal_v_r01/build_manifest.json -Environment Board -LutCount 8448 -Output ./work/score_r01.json
```

原r04正式27 MHz实板结果为83.126866 CoreMark、3.078772813 CoreMark/MHz；8448 LUT为整个Score顶层，整机保守资源效率0.009839827883 CoreMark/LUT。该历史结果的完整原始证明不在本仓库；公开副本本次实际检查见[验证摘要](docs/verification.md)，不将新仿真或新实现冒充新的实体板成绩。

## 来源与许可

基于[TinyRISC-V](https://github.com/liangkangnan/tinyriscv)移植与扩展。处理器基础和派生文件保留Apache-2.0来源；项目自主新增内容由LegOlaSs-Newt依MIT授权。CoreMark和测试依赖保留各自条款。详见[NOTICE](NOTICE.md)、[原始声明](fpga/licenses/SOURCE_NOTICES.md)及[改动说明](fpga/pds/tinyriscv_mes50hp/MODIFICATIONS.md)。
