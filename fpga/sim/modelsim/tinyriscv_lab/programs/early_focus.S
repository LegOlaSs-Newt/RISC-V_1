/*
 * 模块说明：early_focus。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
    .section .text.init
    .global _start
    .macro BAD_LOAD op, cause, address
        li t5, \address
        li x20, \cause
        mv x21, t5
        la x22, .Lbad\@
        la x23, .Lafter\@
.Lbad\@:
        \op t6, 0(t5)
.Lafter\@:
    .endm
_start:
    li x26,0
    li x27,0
    li x24,0
    li x25,0
    la t0,trap
    csrw mtvec,t0
    csrw mie,zero
    csrw mstatus,zero
    li s0,0x10000000
    li s1,0x807f12fe
    sw s1,0(s0)
    sw s0,4(s0)
    li t0,0x76543210
    sw t0,8(s0)
    lw t0,0(s0)
    bne t0,s1,fail
    lb t0,0(s0)
    li t1,-2
    bne t0,t1,fail
    lbu t0,3(s0)
    li t1,128
    bne t0,t1,fail
    lh t0,2(s0)
    li t1,0xffff807f
    bne t0,t1,fail
    lhu t0,2(s0)
    li t1,0x807f
    bne t0,t1,fail
    lw zero,0(s0)
    addi s2,s0,8
    lw t0,0(s2)
    li t1,0x76543210
    bne t0,t1,fail
    lw t0,4(s0)
    lw t1,0(t0)
    bne t1,s1,fail
    lw t0,0(s0)
    lw t1,0(s0)
    lw t2,0(s0)
    bne t0,t1,fail
    bne t1,t2,fail
    li t0,0xab
    sb t0,1(s0)
    lbu t1,1(s0)
    bne t0,t1,fail
    fence
    lw t0,0(s0)
    beq zero,zero,skip_load
    lw t6,0(s0)
skip_load:
    li t6,0x2468
    BAD_LOAD lw,4,0x10000001
    BAD_LOAD lw,5,0x10004000
    BAD_LOAD lb,5,0x40000000
    li t0,0x2468
    bne t0,t6,fail
    li t0,3
    bne x25,t0,fail
    li s3,0x40000004
    li x20,0x8000000b
    li t0,0x800
    csrw mie,t0
    li t0,8
    csrw mstatus,t0
    li t0,1
    sw t0,0(s3)
    li a1,64
irq_loop:
    lw a0,0(s0)
    addi a1,a1,-1
    bnez a1,irq_loop
    csrw mie,zero
    li t0,1
    bne x24,t0,fail
    li t0,2
    sw t0,0(s3)
    li a1,64
halt_loop:
    lw a0,0(s0)
    addi a1,a1,-1
    bnez a1,halt_loop
    li t0,3
    sw t0,0(s3)
host_loop:
    lw t0,0(s0)
    li t1,0x11223344
    bne t0,t1,host_loop
    lw t0,0(s0)
    bne t0,t1,fail
    li x27,1
    li x26,1
1:  j 1b
trap:
    csrr x18,mcause
    bne x18,x20,fail
    bltz x18,irq_trap
    csrr x18,mepc
    bne x18,x22,fail
    csrr x18,mtval
    bne x18,x21,fail
    csrw mepc,x23
    addi x25,x25,1
    mret
irq_trap:
    addi x24,x24,1
    mret
fail:
    li x27,0
    li x26,1
2:  j 2b
