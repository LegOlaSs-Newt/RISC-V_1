/*
 * 模块说明：csr_semantics。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// V0.4 WARL, CSR operations, zero-source reads and exact retirement checks.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    la x5, trap
    csrw mtvec, x5
    csrw mie, zero
    li x5, -1
    csrw mstatus, x5
    csrr x6, mstatus
    li x7, 0x1888
    bne x6, x7, fail
    csrw mstatus, zero
    csrr x6, mstatus
    li x7, 0x1800
    bne x6, x7, fail
    csrw mie, x5
    csrr x6, mie
    li x7, 0x888
    bne x6, x7, fail
    csrw mie, zero

    csrw misa, zero
    csrr x6, misa
    li x7, 0x40001100
    bne x6, x7, fail
    csrw 0x310, x5
    csrr x6, 0x310
    bne x6, zero, fail
    csrr x6, mhartid
    bne x6, zero, fail
    li x5, 0x1237
    csrw mepc, x5
    csrr x6, mepc
    li x7, 0x1234
    bne x6, x7, fail
    li x5, 0x102
    csrw mtvec, x5
    csrr x6, mtvec
    li x7, 0x100
    bne x6, x7, fail
    li x5, 0x101
    csrw mtvec, x5
    csrr x6, mtvec
    bne x6, x5, fail
    la x5, trap
    csrw mtvec, x5

    csrw mscratch, zero
    li x5, 0x55
    csrrw x6, mscratch, x5
    bne x6, zero, fail
    li x5, 0xa0
    csrrs x6, mscratch, x5
    li x7, 0x55
    bne x6, x7, fail
    li x5, 0x0f
    csrrc x6, mscratch, x5
    li x7, 0xf5
    bne x6, x7, fail
    csrrwi x6, mscratch, 3
    li x7, 0xf0
    bne x6, x7, fail
    csrrsi x6, mscratch, 4
    li x7, 3
    bne x6, x7, fail
    csrrci x6, mscratch, 1
    li x7, 7
    bne x6, x7, fail
    csrr x6, mscratch
    li x7, 6
    bne x6, x7, fail
    // These CSRRS/RC forms read a read-only CSR without writing.
    li x5, 1
    csrw mcountinhibit, x5
    csrr x6, cycle
    csrrs x7, cycle, zero
    bne x6, x7, fail
    csrrc x7, cycle, zero
    bne x6, x7, fail
    csrrsi x7, cycle, 0
    bne x6, x7, fail
    csrrci x7, cycle, 0
    bne x6, x7, fail
    csrr x7, mcycle
    bne x6, x7, fail

    // Store/branch retire; flushed instructions and RIB holes do not.
    lui x10, 0x10000
    csrw minstret, zero
    nop
    sw zero, 0(x10)
    beq zero, zero, counted
    addi x5, zero, 99
counted:
    csrr x5, minstret
    li x6, 3
    bne x5, x6, fail

    // Detached divide retires exactly once, after completion.
    li x6, 99
    li x7, 9
    li x9, 1
    csrw minstret, zero
    div x5, x6, x7
    csrr x8, minstret
    bne x8, x9, fail
    li x6, 11
    bne x5, x6, fail

    // MRET itself retires; it restores MIE/MPIE with MPP fixed to M.
    la x5, returned
    csrw mepc, x5
    csrw mstatus, zero
    csrw minstret, zero
    mret
returned:
    csrr x5, minstret
    bne x5, x9, fail
    csrr x5, mstatus
    li x6, 0x1880
    bne x5, x6, fail

    la x5, after_ecall
    csrw mepc, x5
    csrw minstret, zero
    ecall
after_ecall:
    li x27, 1
    li x26, 1
1:  j 1b
trap:
    csrr x5, minstret
    bne x5, zero, fail       // ECALL did not retire
    csrr x5, mcause
    li x6, 11
    bne x5, x6, fail
    la x5, after_ecall
    csrw mepc, x5
    mret
fail:
    li x27, 0
    li x26, 1
2:  j 2b

