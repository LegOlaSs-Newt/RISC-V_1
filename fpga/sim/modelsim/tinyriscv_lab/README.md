# Port 回归入口

使用-RtlSet Port，默认Wait、CacheOn、BPOn、EarlyLookupOn。首次运行前完成板级Software构建；外部工具由-GccBin、-ModelSimBin指定。

run_delivery.ps1执行Quick2、ISA47、Examples6、Board2、CoreMarkSmoke2、Boundary3、Delivery4、Advanced6、Memory3，共75正常项，再检查pipeline_fail应被拒绝。run_early_directed.py额外检查7项提前查询场景。另有缓存后端、等待、UART及预测等独立脚本。

输出使用新的RecordRoot，Smoke不作正式成绩。Reference RTL未包含，也不自动回退Port。命令见[仓库README](../../../../README.md)。
