/*
 * 模块说明：memory_stats。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
#ifndef TINYRISCV_MEMORY_STATS_H
#define TINYRISCV_MEMORY_STATS_H
#include <stdint.h>

#define MEMORY_STATS_BASE 0x60000000u
enum memory_stat_index {
    MEMORY_I_HIT,
    MEMORY_I_MISS,
    MEMORY_D_READ_HIT,
    MEMORY_D_READ_MISS,
    MEMORY_I_WAIT,
    MEMORY_D_WAIT,
    MEMORY_BUS_COMMANDS,
    MEMORY_BUS_READ_BEATS,
    MEMORY_BUS_WRITE_BEATS,
    MEMORY_BUS_RESPONSE_STALLS,
    MEMORY_BUS_ACTIVE,
    MEMORY_BUS_LINE_READS,
    MEMORY_D_WRITE_HIT,
    MEMORY_D_WRITE_MISS,
    MEMORY_UNCACHED_DATA,
    MEMORY_STAT_COUNT
};
/* V0.5 only. Use unsigned differences around the measured section; the
 * observation reads themselves generate uncached bus transactions. */
static inline uint64_t memory_stat_read(enum memory_stat_index index) {
    volatile const uint32_t *word =
        (volatile const uint32_t *)(MEMORY_STATS_BASE + (uint32_t)index * 8u);
    uint32_t high_before, low, high_after;
    do {
        high_before = word[1];
        low = word[0];
        high_after = word[1];
    } while (high_before != high_after);
    return ((uint64_t)high_after << 32) | low;
}
#endif
