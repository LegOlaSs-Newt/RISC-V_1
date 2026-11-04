/*
 * 模块说明：pipeline。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Directed learning program: bypass, store/load dependency and branch flush.
// Build with LAB_INTENTIONAL_FAIL to practice finding a failed comparison.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    lui x10, 0x10000
    sw zero, 4(x10)
    addi x1, zero, 5
    add x2, x1, x1
    sw x2, 0(x10)
    lw x3, 0(x10)
    add x4, x3, x1
#ifdef LAB_INTENTIONAL_FAIL
    addi x5, zero, 16
#else
    addi x5, zero, 15
#endif
    bne x4, x5, fail
    beq x4, x5, taken
    sw x4, 4(x10)       // Wrong path: must not change RAM.
    addi x27, zero, 0   // Wrong path: must be discarded.
taken:
    lw x6, 4(x10)
    bne x6, zero, fail
    addi x0, zero, 99
    addi x7, x0, 1
    addi x8, zero, 1
    bne x7, x8, fail
    li x27, 1
    li x26, 1
pass_loop:
    j pass_loop
fail:
    li x27, 0
    li x26, 1
fail_loop:
    j fail_loop
