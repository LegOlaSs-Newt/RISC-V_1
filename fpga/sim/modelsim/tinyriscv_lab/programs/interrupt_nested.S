/*
 * 模块说明：interrupt_nested。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// M-only software-managed nesting, branch boundary and timer during divide.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    li x24, 0
    li x25, 0
    li sp, 0x10004000
    lui x10, 0x20000
    lui x11, 0x10000
    sw zero, 0(x11)
    la x5, handler
    csrw mtvec, x5
    li x5, 0x88
    csrw mie, x5
    csrsi mstatus, 8
    li x5, 1
    sw x5, 12(x10)
branch_resume:
    beq zero, zero, after_branch
    sw x5, 0(x11)             // younger store killed by IRQ, then by branch
after_branch:
    lw x5, 0(x11)
    bne x5, zero, fail
    li x5, 2
    bne x24, x5, fail
    li x5, 1
    bne x25, x5, fail

    la x5, div_handler
    csrw mtvec, x5
    li x5, 20
    sw x5, 8(x10)
    li x6, 100
    li x8, 7
    li x5, 3
    sw x5, 0(x10)
    div x7, x6, x8
after_div:
    li x5, 14
    bne x7, x5, fail
    li x5, 3
    bne x24, x5, fail
    li x27, 1
    li x26, 1
1:  j 1b
handler:
    csrr x5, mcause
    li x6, 0x80000003
    beq x5, x6, outer
    li x6, 0x80000007
    bne x5, x6, fail
    li x5, 1
    bne x24, x5, fail
    csrr x5, mepc
    la x6, nested_resume
    bne x5, x6, fail
    csrr x5, mstatus
    li x6, 0x1880
    bne x5, x6, fail
    li x5, 4
    sw x5, 0(x10)
    li x24, 2
    mret
outer:
    bne x24, zero, fail
    csrr x5, mepc
    la x6, branch_resume
    bne x5, x6, fail
    addi sp, sp, -16
    csrr x5, mepc
    sw x5, 0(sp)
    csrr x5, mstatus
    sw x5, 4(sp)
    li x24, 1
    sw zero, 12(x10)
    li x5, 5
    sw x5, 8(x10)
    li x5, 3
    sw x5, 0(x10)
wait_timer:
    csrr x5, mip
    andi x5, x5, 0x80
    beq x5, zero, wait_timer
    csrsi mstatus, 8
nested_resume:
    addi x25, x25, 1
    li x5, 2
    bne x24, x5, fail
    csrci mstatus, 8
    lw x5, 0(sp)
    csrw mepc, x5
    lw x5, 4(sp)
    csrw mstatus, x5
    addi sp, sp, 16
    mret
div_handler:
    csrr x5, mcause
    li x6, 0x80000007
    bne x5, x6, fail
    csrr x5, mepc
    la x6, after_div
    bne x5, x6, fail
    li x5, 14
    bne x7, x5, fail          // divide writeback must already be committed
    li x5, 4
    sw x5, 0(x10)
    addi x24, x24, 1
    mret
fail:
    li x27, 0
    li x26, 1
2:  j 2b

