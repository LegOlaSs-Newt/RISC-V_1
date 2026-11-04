/*
 * 模块说明：板级裸机演示或定向负载主程序。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
#include <stdint.h>
#include "../include/memory_stats.h"
#define REG32(a) (*(volatile uint32_t *)(a))
#ifndef UART_DIVIDER
#define UART_DIVIDER 233u
#endif
/* 8 KiB leaves room for the result records, telemetry and stack. The aligned
 * arena is initialized only by stores, so no-write-allocate keeps it cold. */
static volatile uint32_t arena[2048] __attribute__((aligned(1024)));
struct measurement {
    uint32_t cycles, hits, misses, checksum;
};
static struct measurement result[4];
static uint64_t total_before[MEMORY_STAT_COUNT], total_after[MEMORY_STAT_COUNT];
extern void cache_probe_seq(volatile uint32_t *, struct measurement *);
extern void cache_probe_two_way(volatile uint32_t *, struct measurement *);
extern void cache_probe_conflict(volatile uint32_t *, struct measurement *);
extern void cache_probe_bytes(volatile uint32_t *, struct measurement *);
extern uint32_t cache_probe_smc(void);
static void putc_uart(char c) {
    while (REG32(0x30000004u) & 1u) {
    }
    REG32(0x3000000cu) = (uint8_t)c;
}
static void text(const char *p) {
    while (*p)
        putc_uart(*p++);
}
static void hex32(uint32_t value) {
    for (int n = 28; n >= 0; n -= 4)
        putc_uart("0123456789ABCDEF"[(value >> n) & 15u]);
}
static void snapshot(uint64_t *values) {
    for (unsigned n = 0; n < MEMORY_STAT_COUNT; ++n)
        values[n] = memory_stat_read((enum memory_stat_index)n);
}
static uint32_t pattern(unsigned i) {
    return 0x9e3779b9u ^ i;
}
int main(void) {
    REG32(0x30000000u) = 3;
    REG32(0x30000008u) = UART_DIVIDER;
    REG32(0x40000000u) = 5;
    REG32(0x40000004u) = 1;
    text("V3_CACHE_PROBE_BEGIN v1\r\n");
    for (unsigned i = 0; i < 2048; ++i)
        arena[i] = pattern(i);
    snapshot(total_before);
    cache_probe_seq(arena, &result[0]);
    cache_probe_two_way(arena + 512, &result[1]);
    cache_probe_conflict(arena + 1056, &result[2]);
    cache_probe_bytes(arena + 64, &result[3]);
    uint32_t smc = cache_probe_smc();
    snapshot(total_after);
    uint32_t expected[4] = {0, 0, 0, (0x55ccaa00u | (pattern(64) & 255u)) ^ 0x11223344u};
    for (unsigned i = 0; i < 256; ++i)
        expected[0] += pattern(i) * 4u;
    expected[1] = (pattern(512) + pattern(768)) * 32u;
    expected[2] = (pattern(1056) + pattern(1312) + pattern(1568)) * 32u;
    uint32_t pass = smc == 0x00070009u;
    for (unsigned n = 0; n < 4; ++n) {
        pass &= result[n].checksum == expected[n];
        text("WORK ");
        hex32(n);
        text(" cycles=");
        hex32(result[n].cycles);
        text(" dh=");
        hex32(result[n].hits);
        text(" dm=");
        hex32(result[n].misses);
        text(" checksum=");
        hex32(result[n].checksum);
        text(" expected=");
        hex32(expected[n]);
        text("\r\n");
    }
    text("SMC before_after=");
    hex32(smc);
    text("\r\n");
    /* Full 64-bit telemetry is collected without UART in the interval. Each
     * counter has its own high-low-high sampling instant. Deltas include
     * instrumentation, stack and SMC traffic; only WORK dh/dm are exact
     * load-workload counts. They are not pure burst efficiency measures. */
    for (unsigned n = 0; n < MEMORY_STAT_COUNT; ++n) {
        uint64_t delta = total_after[n] - total_before[n];
        text("STAT ");
        hex32(n);
        text(" delta=");
        hex32((uint32_t)(delta >> 32));
        hex32((uint32_t)delta);
        text("\r\n");
    }
    REG32(0x40000004u) = pass ? 2u : 3u;
    text(pass ? "V3_CACHE_PROBE_PASS\r\n" : "V3_CACHE_PROBE_FAIL\r\n");
    if (pass)
        __asm__ volatile("li s11,1\nli s10,1" ::: "s10", "s11");
    else
        __asm__ volatile("li s11,0\nli s10,1" ::: "s10", "s11");
    for (;;)
        __asm__ volatile("nop");
}
