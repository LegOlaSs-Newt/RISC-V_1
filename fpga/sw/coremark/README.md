# CoreMark 平台移植

固定EEMBC v1.01，commit cfa9ab377835911f23d9b0831c7be302ed1f58de。SOURCE.json校验六份算法，保留原版权及许可。port负责UART、64位计时、GPIO和有效性检查；启动代码在板级sw/start.S。

build.ps1支持Smoke/Formal与Performance/Validation。Smoke只验证CRC；Formal设置2000次，实际不少于10秒。capture.ps1保存串口，score.ps1核对P/V和manifest计分。重建软件不是新板测。

目标rv32im_zicsr/ilp32，默认27MHz。按64位周期和实际频率计时，Performance作主分数，Validation检查另一组种子。固定程序的历史字符串不检测Cache开关；实际开关由RTL/位流确定。命令见[仓库README](../../../README.md)。
