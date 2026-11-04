/*
 * 模块说明：rom_boot_probe。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Diagnostic only. Fits in the first 256 UART-loaded bytes and dumps the
// untouched V2 image at 0x100..0x2d8, then emits '!'. No GPIO is driven.
    .section .text.init
    .global _start
_start:
    lui x5, 0x30000
    li x6, 3
    sw x6, 0(x5)
    li x6, 233
    sw x6, 8(x5)
    li x12, 0x100
    li x13, 0x2dc
word_loop:
    lw x20, 0(x12)
    li x21, 28
nibble:
    srl x22, x20, x21
    andi x22, x22, 15
    li x23, 10
    bltu x22, x23, digit
    addi x22, x22, 7
digit:
    addi x22, x22, 48
wait_digit:
    lw x6, 4(x5)
    andi x6, x6, 1
    bne x6, zero, wait_digit
    sw x22, 12(x5)
    addi x21, x21, -4
    bge x21, zero, nibble
wait_newline:
    lw x6, 4(x5)
    andi x6, x6, 1
    bne x6, zero, wait_newline
    li x22, 10
    sw x22, 12(x5)
    addi x12, x12, 4
    bltu x12, x13, word_loop
wait_done:
    lw x6, 4(x5)
    andi x6, x6, 1
    bne x6, zero, wait_done
    li x22, 33
    sw x22, 12(x5)
1:  j 1b
