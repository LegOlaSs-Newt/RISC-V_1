# r04 MES50HP 板级工程

RTL位于rtl/vendor及rtl/tinyriscv_mes50hp_top.v。默认27MHz K21晶振，Wait、CacheOn、BPOn、EarlyLookupOn，FixHold、seed1。

先运行build.ps1 -Stage Software并传入GccBin，生成本机启动镜像；再-Stage Bitstream并指定PdsRoot，或打开build_submission_r01/tinyriscv_mes50hp_r04.pds。源码、约束和输出由脚本定位，不依赖原开发电脑。

sw/main.c是UART/LED演示，sw/cache_probe和sw/gpio_console为独立程序。download.ps1下载CPU BIN；configure_sram.ps1配置FPGA SRAM。它们不执行配置Flash固化。编译不替代实体板运行。

完整使用步骤见[仓库README](../../../README.md)，来源及改动见[MODIFICATIONS](MODIFICATIONS.md)。
