/*
 * 模块说明：裸机启动与栈初始化。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
    .section .init, "ax"
    .globl _start
_start:
    .option push
    .option norelax
    la gp, __global_pointer$
    la sp, __stack_top
    .option pop
    li s10, 0
    li s11, 0
    la t0, __data_load
    la t1, __data_start
    la t2, __data_end
1:  bgeu t1, t2, 2f
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    j 1b
2:  la t1, __bss_start
    la t2, __bss_end
3:  bgeu t1, t2, 4f
    sw zero, 0(t1)
    addi t1, t1, 4
    j 3b
4:  call main
5:  j 5b
