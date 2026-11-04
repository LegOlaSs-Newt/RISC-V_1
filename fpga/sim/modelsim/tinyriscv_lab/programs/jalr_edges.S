/*
 * 模块说明：jalr_edges。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// JALR: positive/negative immediates, ALU/load bypass, rd=rs1, rd=x0,
// link PC+4 and independently poisoned register/store/CSR wrong paths.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    lui x10, 0x10000
    sw zero, 0(x10)
    li x9, 0x123
    csrw mscratch, x9
    li x5, 0x55
    la x6, target_pos
    addi x6, x6, -6
    jalr x7, 7(x6)           // adjacent ALU; odd sum = target+1
link_pos:
    li x5, 99               // wrong-path register write
    sw x5, 0(x10)
target_pos:
    la x8, link_pos
    bne x7, x8, fail
    li x8, 0x55
    bne x5, x8, fail
capture_pc:
    auipc x8, 0
    la x11, capture_pc
    bne x8, x11, fail
    la x6, target_neg
    addi x6, x6, 8
    sw x6, 4(x10)
    lw x6, 4(x10)
    jalr x7, -7(x6)          // adjacent load; signed negative immediate
link_neg:
    sw x9, 0(x10)           // wrong-path store
    li x5, 99
target_neg:
    la x8, link_neg
    bne x7, x8, fail
    lw x8, 0(x10)
    bne x8, zero, fail
    la x6, target_same
    addi x6, x6, 1
    jalr x6, 0(x6)           // use old rs1 before writing link
link_same:
    csrw mscratch, zero     // wrong-path CSR write
    li x5, 99
target_same:
    la x8, link_same
    bne x6, x8, fail
    csrr x8, mscratch
    bne x8, x9, fail
    la x6, target_zero
    addi x6, x6, 1
    jalr zero, 0(x6)
    sw x9, 0(x10)
    csrw mscratch, zero
target_zero:
    bne zero, x0, fail
    lw x8, 0(x10)
    bne x8, zero, fail
    csrr x8, mscratch
    bne x8, x9, fail
    li x8, 0x55
    bne x5, x8, fail
    jal x7, target_jal
link_jal:
    li x5, 99
target_jal:
    la x8, link_jal
    bne x7, x8, fail
    li x27, 1
    li x26, 1
1:  j 1b
fail:
    li x27, 0
    li x26, 1
2:  j 2b
