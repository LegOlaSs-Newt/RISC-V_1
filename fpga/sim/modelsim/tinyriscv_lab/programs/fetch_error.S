/*
 * 模块说明：fetch_error。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
    .section .text
    .globl _start
_start:
    li s10,0
    li s11,0
    li s0,0
    la t0,trap_entry
    csrw mtvec,t0
    j failing_fetch
    .org 0x100
trap_entry:
    csrr t0,mcause
    li t1,1
    bne t0,t1,fail
    csrr t0,mepc
    li t1,0x200
    bne t0,t1,fail
    csrr t0,mtval
    bne t0,t1,fail
    addi s0,s0,1
    li t0,0x204
    csrw mepc,t0
    mret
fail:
    li s11,0
    li s10,1
1:  j 1b
    .org 0x200
failing_fetch:
    addi s0,s0,100
resume:
    li t0,1
    bne s0,t0,fail
    li s11,1
    li s10,1
1:  j 1b
