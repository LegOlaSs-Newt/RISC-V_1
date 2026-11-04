/*
 * 模块说明：memory_statistics。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// V0.5 exact statistics whitelist, read-only/width/boundary exception rules.
    .section .text.init
    .global _start
    .macro BAD insn,cause,address
    li x20, \cause
    li x21, \address
    la x22, 91f
91: \insn x5, 0(x21)
    .endm
_start:
    li x26, 0
    li x27, 0
    li s0, 0
    la t0, handler
    csrw mtvec, t0
    li t0, 0x60000000
    // Read every implemented low/high pair, including D writes and bypass.
    li t1, 15
read_all:
    lw t2, 4(t0)
    lw t3, 0(t0)
    lw t4, 4(t0)
    bne t2, t4, read_all
    addi t0, t0, 8
    addi t1, t1, -1
    bnez t1, read_all
    li t0, 0x60000030
    lw t1, 0(t0)
    beqz t1, fail
    BAD sw,7,0x60000000
    BAD lb,5,0x60000000
    BAD lh,5,0x60000000
    BAD lw,4,0x60000002
    BAD lw,5,0x60000078
    BAD lw,5,0x6000007c
    BAD lw,5,0x60000080
    BAD lw,5,0x60001000
    li t0, 8
    bne s0, t0, fail
    li x27, 1
    li x26, 1
1:  j 1b
handler:
    csrr t3, mcause
    bne t3, x20, fail
    csrr t3, mtval
    bne t3, x21, fail
    csrr t3, mepc
    bne t3, x22, fail
    addi t3, t3, 4
    csrw mepc, t3
    addi s0, s0, 1
    mret
fail:
    li x27, 0
    li x26, 1
2:  j 2b
