/*
 * 模块说明：板级裸机演示或定向负载主程序。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// RISC-V UART digital I/O terminal. Independent from the V2 demo.
#include <stdint.h>
#define REG32(a) (*(volatile uint32_t *)(a))
#define CTRL REG32(0x40000000u)
#define DATA REG32(0x40000004u)
#define UART REG32(0x30000000u)
#define STATUS REG32(0x30000004u)
#define BAUD REG32(0x30000008u)
#define TX REG32(0x3000000cu)
#define RX REG32(0x30000010u)
#ifndef UART_DIVIDER
#define UART_DIVIDER 233u
#endif

static void putc_uart(char c) {
    while (STATUS & 1u) {
    }
    TX = (uint8_t)c;
}
static void puts_uart(const char *s) {
    while (*s)
        putc_uart(*s++);
}
static uint8_t getc_uart(void) {
    while (!(STATUS & 2u)) {
    }
    uint8_t c = (uint8_t)RX;
    STATUS = 0; // Acknowledge the single-byte RX register before waiting again.
    return c;
}
static void hex(uint32_t v, unsigned digits) {
    static const char h[] = "0123456789ABCDEF";
    while (digits) {
        --digits;
        putc_uart(h[(v >> (digits * 4u)) & 15u]);
    }
}
static int equal(const char *a, const char *b) {
    while (*a && *a == *b) {
        ++a;
        ++b;
    }
    return *a == *b;
}
static int space(char c) {
    return c == ' ' || c == '\t';
}
static int value(const char *s, unsigned maxdigits, uint32_t *out) {
    uint32_t n = 0;
    unsigned count = 0;
    while (space(*s))
        ++s;
    if (s[0] == '0' && (s[1] == 'x' || s[1] == 'X'))
        s += 2;
    while (*s && !space(*s)) {
        unsigned d;
        if (*s >= '0' && *s <= '9')
            d = (unsigned)(*s - '0');
        else if (*s >= 'a' && *s <= 'f')
            d = (unsigned)(*s - 'a') + 10u;
        else if (*s >= 'A' && *s <= 'F')
            d = (unsigned)(*s - 'A') + 10u;
        else
            return 0;
        if (++count > maxdigits)
            return 0;
        n = (n << 4) | d;
        ++s;
    }
    while (space(*s))
        ++s;
    if (!count || *s)
        return 0;
    *out = n;
    return 1;
}
static void settle(void) {
    // Far longer than two synchronizers plus the DATA sampling edge.
    for (volatile unsigned i = 0; i < 32; ++i)
        __asm__ volatile("nop");
}
static int selftest(void) {
    static const uint8_t patterns[] = {0x00, 0xff, 0x55, 0xaa, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20,
                                       0x40, 0x80, 0xfe, 0xfd, 0xfb, 0xf7, 0xef, 0xdf, 0xbf, 0x7f};
    int ok = 1;
    for (unsigned reverse = 0; reverse < 2; ++reverse) {
        CTRL = 0; // Break before make, also on test entry.
        DATA = 0;
        settle();
        CTRL = reverse ? 0x5555aaaau : 0xaaaa5555u;
        for (unsigned p = 0; p < sizeof(patterns); ++p) {
            unsigned expected = patterns[p];
            DATA = reverse ? expected << 8 : expected;
            settle();
            uint32_t observed = DATA;
            unsigned sample = reverse ? (observed & 255u) : ((observed >> 8) & 255u);
            if (sample != expected) {
                ok = 0;
                puts_uart("MISMATCH DIR=");
                hex(reverse, 1);
                puts_uart(" EXPECT=");
                hex(expected, 2);
                puts_uart(" GOT=");
                hex(sample, 2);
                puts_uart("\r\n");
            }
        }
    }
    CTRL = 0; // Always release outputs, including failure.
    return ok;
}
static void command(char *line) {
    uint32_t v;
    char *arg = line;
    while (*arg && !space(*arg))
        ++arg;
    if (*arg) {
        *arg++ = 0;
        while (space(*arg))
            ++arg;
    }
    if (equal(line, "MODE") && value(arg, 8, &v)) {
        CTRL = v;
        puts_uart("OK MODE=");
        hex(v, 8);
        puts_uart("\r\n");
    } else if (equal(line, "WRITE") && value(arg, 4, &v)) {
        DATA = v;
        puts_uart("OK WRITE=");
        hex(v, 4);
        puts_uart("\r\n");
    } else if (*arg)
        puts_uart("ERR COMMAND\r\n");
    else if (equal(line, "HELP")) {
        puts_uart("HELP | MODE <hex32> | WRITE <hex16> | READ | SELFTEST\r\n");
    } else if (equal(line, "READ")) {
        v = DATA;
        puts_uart("OK CTRL=");
        hex(CTRL, 8);
        puts_uart(" DATA=");
        hex(v & 65535u, 4);
        puts_uart("\r\n");
    } else if (equal(line, "SELFTEST")) {
        int ok = selftest();
        puts_uart(ok ? "OK SELFTEST 40/40 CTRL=00000000\r\n" : "ERR SELFTEST CTRL=00000000\r\n");
    } else
        puts_uart("ERR COMMAND\r\n");
}
int main(void) {
    char line[64];
    unsigned used = 0, invalid = 0, previous_cr = 0;
    CTRL = 0;
    DATA = 0;
    UART = 3;
    BAUD = UART_DIVIDER;
    STATUS = 0;
    puts_uart("RISC-V GPIO CONSOLE V1 115200 8N1\r\nREADY CTRL=00000000\r\n");
    for (;;) {
        uint8_t c = getc_uart();
        if (c == '\n' && previous_cr) {
            previous_cr = 0;
            continue;
        }
        previous_cr = c == '\r';
        if (c == '\r' || c == '\n') {
            line[used] = 0;
            if (invalid)
                puts_uart("ERR LINE\r\n");
            else
                command(line);
            used = invalid = 0;
        } else if (c < 32u && c != '\t')
            invalid = 1;
        else if (c > 126u)
            invalid = 1;
        else if (used == sizeof(line) - 1)
            invalid = 1;
        else if (!invalid)
            line[used++] = (char)c;
    }
}
