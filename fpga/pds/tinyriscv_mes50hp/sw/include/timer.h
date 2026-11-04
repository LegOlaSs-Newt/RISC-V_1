/*
 * 模块说明：计时器与机器中断源。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
#ifndef MES50HP_TIMER_H
#define MES50HP_TIMER_H
#include <stdint.h>
#define TIMER0_REG(offset) (*(volatile uint32_t *)(0x20000000u + (offset)))
#define TIMER0_CTRL 0x00u
#define TIMER0_COUNT 0x04u
#define TIMER0_VALUE 0x08u
#define TIMER0_MSIP 0x0cu
static inline void timer0_start_irq(uint32_t period) {
    TIMER0_REG(TIMER0_VALUE) = period;
    TIMER0_REG(TIMER0_CTRL) = 7u;
}
static inline void timer0_ack_restart(void) {
    TIMER0_REG(TIMER0_CTRL) |= 5u;
}
static inline void timer0_stop(void) {
    TIMER0_REG(TIMER0_CTRL) = 4u;
}
static inline void machine_software_irq_set(uint32_t pending) {
    TIMER0_REG(TIMER0_MSIP) = pending & 1u;
}
#endif
