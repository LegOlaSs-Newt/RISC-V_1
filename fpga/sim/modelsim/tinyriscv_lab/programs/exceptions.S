/*
 * 模块说明：exceptions。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// V0.4 precise synchronous traps. All expected values are architectural.
    .section .text.init
    .global _start
    .macro BAD_WORD word
        li x20, 2
        li x21, \word
        la x22, .Lbad\@
        la x23, .Lafter\@
.Lbad\@:
        .word \word
.Lafter\@:
    .endm
    .macro BAD_ACCESS op, cause, address
        li x5, \address
        li x20, \cause
        mv x21, x5
        la x22, .Lbad\@
        la x23, .Lafter\@
.Lbad\@:
        \op x6, 0(x5)
.Lafter\@:
    .endm
_start:
    li x26, 0
    li x27, 0
    li x24, 0
    la x5, trap
    csrw mtvec, x5
    csrw mie, zero
    csrw mstatus, zero
    li x6, 0x76543210

    BAD_WORD 0xffffffff
    BAD_WORD 0x00000001       // real fetched encoding, never an internal bubble
    BAD_WORD 0x02001293       // illegal RV32 SLLI funct7, rd=x5
    BAD_WORD 0x402012b3       // SUB funct7 is illegal for SLL
    BAD_WORD 0x000012e7       // illegal JALR funct3
    BAD_WORD 0x00002263       // illegal branch funct3
    BAD_WORD 0x00003283       // illegal load funct3
    BAD_WORD 0x00003223       // illegal store funct3
    BAD_WORD 0x999022f3       // nonexistent CSR
    BAD_WORD 0xc00012f3       // write read-only cycle
    li x1, 0
    BAD_WORD 0xc000a2f3       // non-x0 zero-valued source still writes cycle
    BAD_WORD 0x10200073       // unsupported SRET

    BAD_ACCESS lw, 4, 0x10000001
    BAD_ACCESS lh, 4, 0x10000001
    BAD_ACCESS sw, 6, 0x10000002
    BAD_ACCESS sh, 6, 0x10000001
    BAD_ACCESS lw, 5, 0x10004000
    BAD_ACCESS sw, 7, 0x10004000
    BAD_ACCESS lb, 5, 0x00004000
    BAD_ACCESS sb, 7, 0x00004000
#ifdef LAB_MEMORY_SYSTEM
    BAD_ACCESS lw, 5, 0x60000078 // V0.5: first reserved statistics slot
#else
    BAD_ACCESS lw, 5, 0x60000000
#endif
    BAD_ACCESS sw, 7, 0x60000000
    BAD_ACCESS lw, 5, 0x30000100 // low-byte register alias must be rejected
    BAD_ACCESS sw, 7, 0x40000008 // undefined GPIO register
    BAD_ACCESS lb, 5, 0x30000000 // MMIO is word-only
    BAD_ACCESS sh, 7, 0x40000000
    BAD_ACCESS lw, 4, 0x30000001 // alignment precedes access error
    li x5, 0x76543210
    bne x5, x6, fail           // trapping loads never overwrite rd

    li x5, 0x10003ffc
    sw x6, 0(x5)
    lw x7, 0(x5)
    bne x6, x7, fail
    lbu x7, 3(x5)
    li x8, 0x76
    bne x7, x8, fail
    lhu x7, 2(x5)
    li x8, 0x7654
    bne x7, x8, fail

    li x20, 0
    la x22, bad_jal
    addi x21, x22, 2
    la x23, after_jal
    li x1, 0x1357
bad_jal:
    .word 0x002000ef
after_jal:
    li x5, 0x1357
    bne x1, x5, fail
    la x22, bad_beq
    addi x21, x22, 2
    la x23, after_beq
bad_beq:
    .word 0x00000163
after_beq:
    .word 0x00001163          // not-taken BNE with misaligned target is legal

    li x20, 0
    li x21, 18
    la x22, bad_jalr
    la x23, after_jalr
    li x5, 19
bad_jalr:
    jalr x1, 0(x5)
after_jalr:
    li x5, 0x1357
    bne x1, x5, fail

    // Aligned unavailable targets fail on fetch, after the jump retires.
    li x20, 1
    li x21, 0x4000
    mv x22, x21
    la x23, after_fetch
    jalr x1, 0(x21)
after_fetch:
    li x21, 0x30000000
    mv x22, x21
    la x23, after_mmio_fetch
    jalr x1, 0(x21)
after_mmio_fetch:
    li x20, 11
    li x21, 0
    la x22, ecall_site
    la x23, after_ecall
ecall_site:
    ecall
after_ecall:
    li x20, 3
    la x22, ebreak_site
    la x23, after_ebreak
ebreak_site:
    ebreak
after_ebreak:
    li x5, 34
    bne x24, x5, fail
    li x27, 1
    li x26, 1
1:  j 1b
trap:
    csrr x28, mcause
    bne x28, x20, fail
    csrr x28, mtval
    bne x28, x21, fail
    csrr x28, mepc
    bne x28, x22, fail
    csrr x28, mstatus
    andi x28, x28, 8
    bne x28, zero, fail
    addi x24, x24, 1
    csrw mepc, x23
    mret
fail:
    li x27, 0
    li x26, 1
2:  j 2b

