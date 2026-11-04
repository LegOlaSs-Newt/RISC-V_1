/*
 * 模块说明：branch_prediction。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Predictable loops, opposite outcomes, same-index targets and killed effects.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    lui x10, 0x10000
    sw zero, 0(x10)
    csrw mscratch, zero
    li x5, 20
    li x6, 0
loop:
    addi x6, x6, 1
    addi x5, x5, -1
    bne x5, zero, loop
    li x5, 20
    bne x6, x5, fail
    li x7, 16
    li x8, 0
alternating:
    xori x8, x8, 1
    beq x8, zero, even
    addi x6, x6, 2
    j next
even:
    addi x6, x6, 3
next:
    addi x7, x7, -1
    bne x7, zero, alternating
    li x5, 60
    bne x6, x5, fail
    li x7, 8
    j alias_a
    .balign 128
alias_a:
    addi x7, x7, -1
    bne x7, zero, alias_b
    j alias_done
    .balign 128
alias_b:
    addi x6, x6, 1
    bne x7, zero, alias_a
    j fail
alias_done:
    li x5, 67
    bne x6, x5, fail
    // A frequently taken branch then exits into these younger effects.
    li x7, 10
guard:
    addi x7, x7, -1
    bne x7, zero, guard
    j after_store
    sw x6, 0(x10)
after_store:
    j after_csr
    csrw mscratch, x6
after_csr:
    j after_ecall
    ecall
after_ecall:
    j after_illegal
    .word 0xffffffff
after_illegal:
    lw x5, 0(x10)
    bne x5, zero, fail
    csrr x5, mscratch
    bne x5, zero, fail
    // Real FENCE.I encoding, then JALR remains EX-resolved.
    .word 0x0000100f
    la x5, indirect
    jalr x1, 0(x5)
    j fail
indirect:
    li x27, 1
    li x26, 1
1:  j 1b
fail:
    li x27, 0
    li x26, 1
2:  j 2b

