/*
 * 模块说明：cache_system。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// CPU + I/D cache + synchronous memory: conflicts, ROM data and self-modifying code.
    .section .text.init
    .global _start
_start:
    li x26, 0
    li x27, 0
    li s0, 0x10000000
    li t0, 0x11223344
    sw t0, 0(s0)
    li t1, 0x55667788
    sw t1, 0x400(s0)
    li t2, 0x76543210
    li s2, 0x10000800
    sw t2, 0(s2)
    lw t3, 0(s0)
    bne t3, t0, fail
    lw t3, 0x400(s0)
    bne t3, t1, fail
    lw t3, 0(s0)
    bne t3, t0, fail
    lw t3, 0(s2)
    bne t3, t2, fail
    lw t3, 0(s0)
    bne t3, t0, fail
    li t0, 0xab
    sb t0, 1(s0)
    lbu t3, 1(s0)
    bne t3, t0, fail
    la s1, function
    lw t0, 0(s1)
    li t1, 0x00100f13
    bne t0, t1, fail
    jal ra, function
    li t0, 1
    bne t5, t0, fail
    li t0, 0x00200f13
    sw t0, 0(s1)
    lw t1, 0(s1)
    bne t0, t1, fail
    .word 0x0000100f
    jal ra, function
    li t0, 2
    bne t5, t0, fail
    li s2, 0x40000004
    sw t0, 0(s2)
    beq zero, zero, skip
    sw t0, 0(s2)
skip:
    sw t0, 0(s2)
    fence
    li x27, 1
    li x26, 1
1:  j 1b
function:
    addi t5, zero, 1
    jalr zero, 0(ra)
fail:
    li x27, 0
    li x26, 1
2:  j 2b
