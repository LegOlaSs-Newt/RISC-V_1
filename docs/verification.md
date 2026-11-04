# 公开副本验证摘要

2026-11-04，对本仓库精简后的公开文件在独立工作目录实际执行。配置为Port、Wait/CacheOn/BPOn/EarlyLookupOn、27 MHz、FixHold、placement seed 1。37份功能Verilog与已验r04提交源码逐字节一致；公开整理修改限于使用说明、许可署名、可移植路径及发布入口。

## 本次实际结果

| 检查 | 结果 |
|---|---|
| 默认Demo软件 | GCC构建通过，BIN为732字节 |
| Quick | 2/2通过 |
| ISA | 47/47通过 |
| Examples | 6/6通过 |
| Board | 2/2通过，含UART下载板级仿真 |
| CoreMark Smoke | Performance/Validation两组CRC通过，共2/2；短仿真不计正式成绩 |
| Boundary / Delivery | 3/3、4/4通过 |
| Advanced / Memory | 6/6、3/3通过 |
| 完整默认回归 | 合计75项正常检查通过；故意错误pipeline_fail以非零退出，被正确拒绝；运行输入未改变 |
| r04提前查询 | 7/7通过；覆盖提前开关的架构对照、IRQ、halt、host-write和取消；运行输入未改变 |
| Reference缺失保护 | 明确拒绝Reference请求，不创建测试输出或回退至Port |
| 脚本 | PowerShell语法解析通过；计分必须显式传入匹配的两份构建清单 |
| PDS完整实现 | 从公开源码重新编译、综合、布局布线并生成非空SRAM位流通过 |
| DRM启动初始化 | 从综合网表重建8个ROM DRM的4096个32位字，与boot.mem全量相同；单比特破坏负控被检出 |

## 新实现资源与时序

PDS 2022.2-SP6.4，Logos / PGL50H / -6 / FBG484。沿用MES50HP板级约束，K21晶振直接提供27 MHz时钟，不使用PLL。

| 项目 | 布线后结果 |
|---|---|
| LUT / FF | 8448 / 3921 |
| APM / DRM | 4 / 21.5个DRM18K等效 |
| Slow Setup / Hold | +2.540 / +0.153 ns |
| Fast Setup / Hold | +12.520 / +0.111 ns |
| 工具时序结论 | All Constraints Met |

时序结论限于工程中已声明的约束。按钮、UART和GPIO等异步板级端口没有外部同步I/O延时约束；此结论不表示这些端口具有完整的外部时序合同。

默认Demo BIN SHA-256：

```text
51F1440717DDDE200B6E0F4776886DE9FA6AC9F53C75A05A01A0B1735FFE96FA
```

## 验证范围

本次公开副本执行了软件构建、仿真和PDS实现，没有重新配置实体板、采集ILA或运行正式CoreMark板测。README中的83.126866 CoreMark和3.078772813 CoreMark/MHz来自此前已验的r04正式27 MHz实板，不将本次Smoke或新位流当作新的板测。

完整研发日志和原始详细证据保留在维护者的私有工程，本仓库提供复现入口和本次结果摘要。首次克隆后先执行Software构建以生成本机启动镜像路径；命令见[README](../README.md)。
