/*
 * 模块说明：CoreMark 平台计时与有效性检查。
 * 来源说明：本项目 CoreMark 平台移植；固定算法保存在 sw/coremark/upstream。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
#include "coremark.h"
#define REG32(a) (*(volatile uint32_t *)(a))

#if VALIDATION_RUN
volatile ee_s32 seed1_volatile = 0x3415, seed2_volatile = 0x3415;
#else
volatile ee_s32 seed1_volatile = 0, seed2_volatile = 0;
#endif
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

/* Symbols are retained for waveform/debugger observation. */
volatile uint32_t coremark_phase;
volatile uint32_t coremark_crc_ok, coremark_duration_ok, coremark_formal_valid;
volatile uint32_t coremark_iterations, coremark_cycles_hi, coremark_cycles_lo;
static CORE_TICKS t0, t1;

static uint64_t read_cycles(void) {
    uint32_t hi, lo, again;
    do {
        __asm__ volatile("csrr %0, cycleh" : "=r"(hi));
        __asm__ volatile("csrr %0, cycle" : "=r"(lo));
        __asm__ volatile("csrr %0, cycleh" : "=r"(again));
    } while (hi != again);
    return ((uint64_t)hi << 32) | lo;
}
void start_time(void) {
    coremark_phase = 2;
    t0 = read_cycles();
}
void stop_time(void) {
    t1 = read_cycles();
    coremark_phase = 3;
}
CORE_TICKS get_time(void) {
    return t1 - t0;
}
secs_ret time_in_secs(CORE_TICKS ticks) {
    return (secs_ret)(ticks / COREMARK_CPU_HZ);
}

void portable_init(core_portable *p, int *argc, char *argv[]) {
    (void)argc;
    (void)argv;
    p->portable_id = 1;
    REG32(0x30000000u) = 3;
    REG32(0x30000008u) = COREMARK_UART_DIV;
    REG32(0x40000000u) = 5;
    REG32(0x40000004u) = 1;
    coremark_phase = 1;
    ee_printf("\nTinyRISC-V CoreMark 1.0 build=%s profile=%s run=%s hz=%u\n", COREMARK_BUILD_ID,
              COREMARK_PROFILE, COREMARK_RUN_NAME, COREMARK_CPU_HZ);
}

void portable_fini(core_portable *p) {
    core_results *r = (core_results *)((unsigned char *)p - offsetof(core_results, port));
    uint64_t ticks = get_time();
#if VALIDATION_RUN
    const uint16_t list = 0xe3c1, matrix = 0x0747, state = 0x8d84;
    const int32_t seed = 0x3415;
#else
    const uint16_t list = 0xe714, matrix = 0x1fd7, state = 0x8e3a;
    const int32_t seed = 0;
#endif
    uint32_t crc_ok = r->seed1 == seed && r->seed2 == seed && r->seed3 == 0x66 && r->size == 666 &&
                      r->execs == ALL_ALGORITHMS_MASK && r->iterations > 0 && r->crclist == list &&
                      r->crcmatrix == matrix && r->crcstate == state && r->err == 0 &&
                      check_data_types() == 0;
    coremark_crc_ok = crc_ok;
    coremark_duration_ok = ticks >= (uint64_t)COREMARK_CPU_HZ * 10u;
    coremark_formal_valid = crc_ok && coremark_duration_ok && !COREMARK_SMOKE;
    coremark_iterations = r->iterations;
    coremark_cycles_hi = (uint32_t)(ticks >> 32);
    coremark_cycles_lo = (uint32_t)ticks;
    coremark_phase = 4;
    ee_printf(
        "CM_RESULT build=%s profile=%s run=%s iterations=%u cycles_hi=%u cycles_lo=%u hz=%u crc_ok=%u duration_ok=%u formal_valid=%u\n",
        COREMARK_BUILD_ID, COREMARK_PROFILE, COREMARK_RUN_NAME, r->iterations, coremark_cycles_hi,
        coremark_cycles_lo, COREMARK_CPU_HZ, coremark_crc_ok, coremark_duration_ok,
        coremark_formal_valid);
    if (COREMARK_SMOKE && crc_ok)
        ee_printf("COREMARK_SMOKE_CRC_PASS (not a reportable score)\n");
    else if (coremark_formal_valid)
        ee_printf("COREMARK_FORMAL_VALID\n");
    else
        ee_printf("COREMARK_CHECK_FAILED\n");
    while (REG32(0x30000004u) & 1u) {
    }
    uint32_t success = COREMARK_SMOKE ? crc_ok : coremark_formal_valid;
    REG32(0x40000004u) = success ? 3u : 2u;
    if (success)
        __asm__ volatile("li s11,1\nli s10,1" ::: "memory");
    else
        __asm__ volatile("li s11,0\nli s10,1" ::: "memory");
}
