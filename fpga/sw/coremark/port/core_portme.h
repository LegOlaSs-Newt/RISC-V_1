/*
 * 模块说明：CoreMark 平台计时与有效性检查。
 * 来源说明：本项目 CoreMark 平台移植；固定算法保存在 sw/coremark/upstream。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
#ifndef TINYRISCV_CORE_PORTME_H
#define TINYRISCV_CORE_PORTME_H
#include <stdint.h>
#include <stddef.h>
#include "build_config.h"

#define HAS_FLOAT 0
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 0
#define HAS_PRINTF 0
#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STATIC
#define MEM_LOCATION "Code: 16KiB on-chip ROM; data: 16KiB RAM; memory:core 1:1; no cache"
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK 0
#define USE_SOCKET 0
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0
#define COMPILER_VERSION "GCC " __VERSION__

typedef uint8_t ee_u8;
typedef int16_t ee_s16;
typedef uint16_t ee_u16;
typedef int32_t ee_s32;
typedef uint32_t ee_u32;
typedef double ee_f32;
typedef uintptr_t ee_ptr_int;
typedef size_t ee_size_t;
typedef uint64_t CORE_TICKS;
#define align_mem(x) ((void *)(((ee_ptr_int)(x) + 3u) & ~(ee_ptr_int)3u))

typedef struct CORE_PORTABLE_S {
    ee_u8 portable_id;
} core_portable;
extern ee_u32 default_num_contexts;
void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
int ee_printf(const char *fmt, ...);
void coremark_putc(char c);
#endif
