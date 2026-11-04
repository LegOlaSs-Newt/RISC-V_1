/*
 * 模块说明：jalr_odd。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// An architectural boundary test. The preserved reference currently fails it.
    .section .text.init
    .global _start
_start:
    addi x1, zero, 17
    jalr x2, 0(x1)      // Required target is 16; return address is 8.
    addi x5, zero, 99
    addi x5, zero, 99
target:
    auipc x3, 0        // Must observe 16, not 17.
    addi x4, zero, 16
    bne x3, x4, fail
    addi x4, zero, 8
    bne x2, x4, fail
    li x27, 1
    li x26, 1
pass_loop:
    j pass_loop
fail:
    li x27, 0
    li x26, 1
fail_loop:
    j fail_loop
