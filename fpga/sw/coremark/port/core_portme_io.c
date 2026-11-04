/*
 * 模块说明：CoreMark 串口格式化输出。
 * 来源说明：本项目 CoreMark 平台移植；固定算法保存在 sw/coremark/upstream。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
#include <stdarg.h>
#include <stdint.h>
#include <stddef.h>
#include "core_portme.h"

#define REG32(a) (*(volatile uint32_t *)(a))
void coremark_putc(char c) {
    if (c == '\n')
        coremark_putc('\r');
    while (REG32(0x30000004u) & 1u) {
    }
    REG32(0x3000000cu) = (uint8_t)c;
}

static void print_unsigned(uint32_t n, unsigned base, unsigned width, char pad) {
    char digits[32];
    unsigned count = 0;
    do {
        unsigned d = n % base;
        digits[count++] = "0123456789abcdef"[d];
        n /= base;
    } while (n);
    while (width > count) {
        coremark_putc(pad);
        --width;
    }
    while (count)
        coremark_putc(digits[--count]);
}

/* CoreMark HAS_FLOAT=0 uses only integer/string conversions here. */
int ee_printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    while (*fmt) {
        if (*fmt != '%') {
            coremark_putc(*fmt++);
            continue;
        }
        ++fmt;
        char pad = ' ';
        unsigned width = 0;
        if (*fmt == '0') {
            pad = '0';
            ++fmt;
        }
        while (*fmt >= '0' && *fmt <= '9')
            width = width * 10u + (unsigned)(*fmt++ - '0');
        int long_arg = 0;
        if (*fmt == 'l') {
            long_arg = 1;
            ++fmt;
        }
        char kind = *fmt++;
        if (kind == 's') {
            const char *s = va_arg(ap, const char *);
            if (!s)
                s = "(null)";
            while (*s)
                coremark_putc(*s++);
        } else if (kind == 'c')
            coremark_putc((char)va_arg(ap, int));
        else if (kind == '%')
            coremark_putc('%');
        else if (kind == 'd' || kind == 'i') {
            int32_t v = long_arg ? (int32_t)va_arg(ap, long) : (int32_t)va_arg(ap, int);
            uint32_t u = (uint32_t)v;
            if (v < 0) {
                coremark_putc('-');
                u = 0u - u;
            }
            print_unsigned(u, 10, width, pad);
        } else if (kind == 'u' || kind == 'x' || kind == 'X') {
            uint32_t v = long_arg ? (uint32_t)va_arg(ap, unsigned long) : va_arg(ap, unsigned int);
            print_unsigned(v, kind == 'u' ? 10u : 16u, width, pad);
        } else {
            coremark_putc('?');
        }
    }
    va_end(ap);
    return 0;
}

void *memcpy(void *dst, const void *src, size_t n) {
    unsigned char *d = dst;
    const unsigned char *s = src;
    while (n--)
        *d++ = *s++;
    return dst;
}
void *memset(void *dst, int value, size_t n) {
    unsigned char *d = dst;
    while (n--)
        *d++ = (unsigned char)value;
    return dst;
}
