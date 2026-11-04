/*
 * 模块说明：memory_config。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Staged V3 integration. Build/simulation defines override these defaults.
`ifndef MES50HP_MEMORY_SYSTEM
`define MES50HP_MEMORY_SYSTEM 0
`endif
`ifndef MES50HP_CACHE_ENABLE
`define MES50HP_CACHE_ENABLE 1
`endif
