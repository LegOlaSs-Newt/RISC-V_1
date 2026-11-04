/*
 * 模块说明：jalr_bit1。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// V0.4: JALR clears bit0, then bit1 must cause a precise alignment trap.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    la x5, trap
    csrw mtvec, x5
    li x1, 19
    li x2, 0x1357
site:
    jalr x2, 0(x1)
    j fail
trap:
    csrr x3, mcause
    bne x3, zero, fail
    csrr x3, mtval
    li x4, 18
    bne x3, x4, fail
    csrr x3, mepc
    la x4, site
    bne x3, x4, fail
    li x4, 0x1357
    bne x2, x4, fail
    la x3, resumed
    csrw mepc, x3
    mret
resumed:
    li x27, 1
    li x26, 1
1:  j 1b
fail:
    li x27, 0
    li x26, 1
2:  j 2b
