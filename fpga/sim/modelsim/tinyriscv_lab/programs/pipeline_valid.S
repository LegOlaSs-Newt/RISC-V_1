/*
 * 模块说明：pipeline_valid。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Explicit validity: RIB fetch holes, divider completion and killed effects.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    lui x10, 0x10000
    sw zero, 0(x10)
    csrw mscratch, zero
    li x5, 100
    li x6, 7
    div x7, x5, x6
    li x8, 14
    bne x7, x8, fail
    rem x9, x5, x6
    li x8, 2
    bne x9, x8, fail
    // Each taken branch kills a different younger instruction class.
    beq zero, zero, after_store
    sw x5, 0(x10)
after_store:
    beq zero, zero, after_csr
    csrw mscratch, x5
after_csr:
    beq zero, zero, after_ecall
    ecall
after_ecall:
    beq zero, zero, after_illegal
    .word 0xffffffff
after_illegal:
    lw x5, 0(x10)
    bne x5, zero, fail
    csrr x5, mscratch
    bne x5, zero, fail
    // Natural data dependence after consecutive loads and writes.
    li x5, 0x76543210
    sw x5, 4(x10)
    lw x6, 4(x10)
    add x7, x6, x6
    slli x8, x5, 1
    bne x7, x8, fail
    li x27, 1
    li x26, 1
1:  j 1b
fail:
    li x27, 0
    li x26, 1
2:  j 2b
