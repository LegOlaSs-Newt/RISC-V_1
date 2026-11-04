/*
 * 模块说明：measure。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
    .section .text
    .balign 32
    # All cacheable data reads inside a measurement are explicit below.
    # Stack saves/restores and result stores lie outside the counter interval.
    # Low-word subtraction is modulo 2^32; each interval is far below one wrap.
    .macro BEGIN name
    .globl \name
    .type \name,@function
\name:
    addi sp,sp,-16
    sw s0,0(sp)
    sw s1,4(sp)
    sw s2,8(sp)
    sw s3,12(sp)
    mv s0,a1
    li t5,0x60000000
    lw s1,0x10(t5)
    lw s2,0x18(t5)
    csrr s3,cycle
    li a2,0
    .endm
    .macro END name
    csrr t6,cycle
    lw t1,0x10(t5)
    lw t2,0x18(t5)
    sub t6,t6,s3
    sub t1,t1,s1
    sub t2,t2,s2
    sw t6,0(s0)
    sw t1,4(s0)
    sw t2,8(s0)
    sw a2,12(s0)
    lw s0,0(sp)
    lw s1,4(sp)
    lw s2,8(sp)
    lw s3,12(sp)
    addi sp,sp,16
    ret
    .size \name,.-\name
    .endm

    BEGIN cache_probe_seq
    li a3,4
1:  mv t0,a0
    li a4,256
2:  lw t3,0(t0)
    add a2,a2,t3
    addi t0,t0,4
    addi a4,a4,-1
    bnez a4,2b
    addi a3,a3,-1
    bnez a3,1b
    END cache_probe_seq

    BEGIN cache_probe_two_way
    li a3,32
1:  lw t3,0(a0)
    lw t4,1024(a0)
    add a2,a2,t3
    add a2,a2,t4
    addi a3,a3,-1
    bnez a3,1b
    END cache_probe_two_way

    BEGIN cache_probe_conflict
    li a3,32
1:  lw t3,0(a0)
    lw t4,1024(a0)
    add a2,a2,t3
    add a2,a2,t4
    addi t0,a0,1024
    lw t3,1024(t0)
    add a2,a2,t3
    addi a3,a3,-1
    bnez a3,1b
    END cache_probe_conflict

    BEGIN cache_probe_bytes
    # Warm this line, then change one byte and one halfword.
    lw t3,0(a0)
    li t4,0xaa
    sb t4,1(a0)
    li t4,0x55cc
    sh t4,2(a0)
    lw a2,0(a0)
    # The distant store must not allocate a line. Its following load misses.
    li t3,0x11223344
    li t4,7168
    add t4,t4,a0
    sw t3,0(t4)
    lw t3,0(t4)
    xor a2,a2,t3
    END cache_probe_bytes

    .balign 32
    .globl cache_probe_smc
    .type cache_probe_smc,@function
cache_probe_smc:
    addi sp,sp,-16
    sw ra,12(sp)
    # Restore the original instruction too, so KEY1 can rerun the same image.
    la t0,cache_probe_smc_target
    li t1,0x00700513
    sw t1,0(t0)
    .word 0x0000100f
    call cache_probe_smc_target
    mv t2,a0
    la t0,cache_probe_smc_target
    li t1,0x00900513
    sw t1,0(t0)
    .word 0x0000100f
    call cache_probe_smc_target
    slli t2,t2,16
    or a0,a0,t2
    lw ra,12(sp)
    addi sp,sp,16
    ret
    .size cache_probe_smc,.-cache_probe_smc
    .balign 32
    .globl cache_probe_smc_target
cache_probe_smc_target:
    addi a0,zero,7
    ret
