/*
 * 模块说明：environment。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Directed evidence for the inherited FENCE and synchronous trap behavior.
// Does not claim a complete privileged architecture implementation.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    lui x10, 0x10000
    li x5, 0x123
    sw x5, 0(x10)
    fence iorw, iorw
    lw x6, 0(x10)
    bne x5, x6, fail
    la x5, trap
    csrw mtvec, x5
    li x20, 0
    li x21, 11
    la x22, ecall_site
ecall_site:
    ecall
    li x5, 1
    bne x20, x5, fail
    li x21, 3
    la x22, ebreak_site
ebreak_site:
    ebreak
    li x5, 2
    bne x20, x5, fail
    li x27, 1
    li x26, 1
1:  j 1b
trap:
    csrr x6, mcause
    bne x6, x21, fail
    csrr x6, mepc
    bne x6, x22, fail
    addi x6, x6, 4
    csrw mepc, x6
    addi x20, x20, 1
    mret
fail:
    li x27, 0
    li x26, 1
2:  j 2b
