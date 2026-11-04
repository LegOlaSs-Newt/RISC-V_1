/*
 * 模块说明：interrupt_sources。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Real UART RX + all three pending sources, masking, priority and mtvec vectors.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    li x24, 0
    csrw mstatus, zero
    csrw mie, zero
    la x5, vectors
    ori x5, x5, 1
    csrw mtvec, x5
    lui x10, 0x20000
    lui x11, 0x30000
    li x5, 233
    sw x5, 8(x11)             // current 27 MHz board UART divider
    li x5, 6
    sw x5, 0(x11)             // RX and RX IRQ, TX stays disabled
wait_uart:
    csrr x5, mip
    srli x5, x5, 11
    beq x5, zero, wait_uart
    bne x24, zero, fail
    lw x5, 0x10(x11)
    li x6, 75
    bne x5, x6, fail
    li x5, -1
    sw x5, 12(x10)
    lw x6, 12(x10)
    li x7, 1
    bne x6, x7, fail         // MSIP upper bits hardwired zero
    li x5, 5
    sw x5, 8(x10)
    li x5, 3
    sw x5, 0(x10)
wait_all:
    csrr x5, mip
    li x6, 0x888
    bne x5, x6, wait_all
    // Globally enable with all per-source masks still zero.
    csrsi mstatus, 8
    nop
    nop
    bne x24, zero, fail
    li x5, 0x888
    csrw mie, x5
resume:
    li x5, 3
    bne x24, x5, fail        // MRET re-enters before this instruction until cleared
    csrr x5, mip
    bne x5, zero, fail
    li x27, 1
    li x26, 1
1:  j 1b

    .balign 256
vectors:
    j fail
    j fail
    j fail
    j software
    j fail
    j fail
    j fail
    j timer
    j fail
    j fail
    j fail
    j external
external:
    li x29, 11
    bne x24, zero, fail
    sw zero, 4(x11)          // original UART RX pending clear rule
    j handler
software:
    li x29, 3
    li x5, 1
    bne x24, x5, fail
    sw zero, 12(x10)
    j handler
timer:
    li x29, 7
    li x5, 2
    bne x24, x5, fail
    li x5, 4
    sw x5, 0(x10)
handler:
    csrr x5, mcause
    li x6, 0x80000000
    or x6, x6, x29
    bne x5, x6, fail
    csrr x5, mepc
    la x6, resume
    bne x5, x6, fail
    csrr x5, mtval
    bne x5, zero, fail
    csrr x5, mstatus
    li x6, 0x1880
    bne x5, x6, fail
    addi x24, x24, 1
    mret
fail:
    li x27, 0
    li x26, 1
2:  j 2b

