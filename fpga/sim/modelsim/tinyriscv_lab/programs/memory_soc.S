/*
 * 模块说明：memory_soc。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Continues across JTAG halt/resume; UART mode intentionally restarts at _start.
    .section .text.init
    .global _start
_start:
    li x26,0
    li x27,0
    li s0,0x10000000
    li s1,0
    li s2,7
    sw zero,8(s0)
loop:
    addi s1,s1,1
    sw s1,0(s0)
    div t2,s1,s2
    rem t3,s1,s2
    mul t4,t2,s2
    add t4,t4,t3
    bne t4,s1,fail
    lw t0,0(s0)
    bne t0,s1,fail
    lw t1,8(s0)
    beqz t1,loop
    lw t1,12(s0)
    li t0,0x12345678
    bne t0,t1,fail
    li x27,1
    li x26,1
1:  j 1b
fail:
    li x27,0
    li x26,1
2:  j 2b
