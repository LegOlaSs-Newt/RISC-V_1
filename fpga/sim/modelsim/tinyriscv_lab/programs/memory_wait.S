/*
 * 模块说明：memory_wait。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Variable-latency LSU: byte lanes, accepted-store IRQ, and precise bus errors.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    la t0, handler
    csrw mtvec, t0
    li s0, 0x10000000
    li s1, 0
    li t0, 0x11223344
    sw t0, 0(s0)
    li t0, 0x80
    sb t0, 1(s0)
    li t0, 0xaabb
    sh t0, 2(s0)
    lw t1, 0(s0)
    li t0, 0xaabb8044
    bne t0, t1, fail
    lb t1, 1(s0)
    li t0, -128
    bne t0, t1, fail
    lbu t1, 1(s0)
    li t0, 128
    bne t0, t1, fail
    lh t1, 2(s0)
    li t0, 0xffffaabb
    bne t0, t1, fail
    lhu t1, 2(s0)
    li t0, 0xaabb
    bne t0, t1, fail
    // The bench raises MSI only after this store has been accepted.
    li t0, 8
    csrw mie, t0
    csrs mstatus, t0
    li t0, 0x55aa
    sw t0, 0x40(s0)
    lw t1, 0x40(s0)
    bne t0, t1, fail
    li t0, 1
    bne s1, t0, fail
    li t0, 0x1234
    // Legal CPU addresses; the bench rejects these before any physical write.
    lw t0, 0x80(s0)
    li t1, 0x1234
    bne t0, t1, fail
    li t0, 2
    bne s1, t0, fail
    sw t0, 0x84(s0)
    li t0, 3
    bne s1, t0, fail
    fence
    .word 0x0000100f  // FENCE.I, encoded like the existing V0.4 tests.
    li t0, 100
    li t1, 7
    div t2, t0, t1
    li t0, 14
    bne t0, t2, fail
    li x27, 1
    li x26, 1
1:  j 1b
handler:
    csrr t3, mcause
    bltz t3, interrupt
    csrr t3, mtval
    li t4, 0x10000080
    li t5, 1
    beq s1, t5, load_error
    addi t4, t4, 4
    bne t3, t4, fail
    csrr t3, mcause
    li t4, 7
    bne t3, t4, fail
    j skip_fault
load_error:
    bne t3, t4, fail
    csrr t3, mcause
    li t4, 5
    bne t3, t4, fail
skip_fault:
    addi s1, s1, 1
    csrr t3, mepc
    addi t3, t3, 4
    csrw mepc, t3
    mret
interrupt:
    li t4, 0x80000003
    bne t3, t4, fail
    // Completion must already be visible when taking the deferred interrupt.
    lw t3, 0x40(s0)
    li t4, 0x55aa
    bne t3, t4, fail
    csrw mie, zero
    addi s1, s1, 1
    mret
fail:
    li x27, 0
    li x26, 1
2:  j 2b
