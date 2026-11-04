/*
 * 模块说明：板级裸机演示或定向负载主程序。
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

static void put_uint(uint32_t value) {
    char digits[10];
    uint32_t count = 0;
    do {
        digits[count++] = (char)('0' + value % 10u);
        value /= 10u;
    } while (value != 0u);
    while (count != 0u)
        put_char(digits[--count]);
}

static void wait_cycles(uint32_t duration) {
    uint32_t begin = cycles();
    while ((uint32_t)(cycles() - begin) < duration) {
    }
}

int main(void) {
    REG32(UART_BASE) = 3;
    REG32(UART_BASE + 8) = UART_DIVIDER;
    REG32(GPIO_BASE) = 5; // Both GPIO pins in output mode.
    REG32(GPIO_BASE + 4) = 1;

    put_text("TinyRISC-V UART DEMO V2\r\n");
    // Keep each multiply observable so GCC does not precompute the result.
    volatile uint32_t factorial = 1;
    for (uint32_t i = 2; i <= 6; ++i)
        factorial *= i;
    uint32_t result = factorial;
    put_text("factorial(6)=");
    put_uint(result);
    if (result == 720u) {
        put_text(" PASS\r\n");
        __asm__ volatile("li s10, 1\nli s11, 1" ::: "s10", "s11");
    } else {
        put_text(" FAIL\r\n");
        __asm__ volatile("li s10, 1\nli s11, 0" ::: "s10", "s11");
    }
    put_text("LED3/LED4 alternate every 250 ms\r\n");

    uint32_t pattern = 1;
    uint32_t quarter_seconds = 0;
    for (;;) {
        wait_cycles(CPU_FREQ_HZ / 4u);
        pattern ^= 3u; // 01 <-> 10: alternate LED3 and LED4.
        REG32(GPIO_BASE + 4) = pattern;
        if ((++quarter_seconds & 3u) == 0u)
            put_text("V2 alive\r\n");
    }
}
