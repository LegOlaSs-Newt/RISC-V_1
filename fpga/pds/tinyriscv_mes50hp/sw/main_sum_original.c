/*
 * 模块说明：main_sum_original。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
#include <stdint.h>
#define REG32(address) (*(volatile uint32_t *)(address))
#define UART_BASE 0x30000000u
#define GPIO_BASE 0x40000000u
#ifndef CPU_FREQ_HZ
#define CPU_FREQ_HZ 27000000u
#endif
#ifndef UART_DIVIDER
#define UART_DIVIDER 233u
#endif

static uint32_t cycles(void) {
    uint32_t value;
    __asm__ volatile("csrr %0, cycle" : "=r"(value));
    return value;
}
static void put_char(char c) {
    while (REG32(UART_BASE + 4) & 1u) {
    }
    REG32(UART_BASE + 12) = (uint8_t)c;
}
static void put_text(const char *text) {
    while (*text)
        put_char(*text++);
}
int main(void) {
    REG32(UART_BASE) = 3;
    REG32(UART_BASE + 8) = UART_DIVIDER;
    REG32(GPIO_BASE) = 5; // Both GPIO pins in output mode.
    REG32(GPIO_BASE + 4) = 1;
    volatile uint32_t sum = 0;
    for (uint32_t i = 1; i <= 10; ++i)
        sum += i;
    put_text("TinyRISC-V on MES50HP\r\n");
    if (sum == 55) {
        put_text("sum(1..10)=55 PASS\r\n");
        __asm__ volatile("li s10, 1\nli s11, 1" ::: "s10", "s11");
    } else
        put_text("sum FAIL\r\n");
    uint32_t pattern = 1;
    for (;;) {
        uint32_t begin = cycles();
        while ((uint32_t)(cycles() - begin) < CPU_FREQ_HZ) {
        }
        pattern = (pattern + 1u) & 3u;
        REG32(GPIO_BASE + 4) = pattern;
    }
}
