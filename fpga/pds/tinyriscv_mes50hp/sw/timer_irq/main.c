/*
 * 模块说明：板级裸机演示或定向负载主程序。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Port-owned V0.4 example; the frozen/reference example remains unchanged.
#include <stdint.h>
#include "../include/machine.h"
#include "../include/timer.h"
static volatile uint32_t count;
int main(void) {
    count = 0;
    machine_enable_timer_irq();
    // Leave time for the complete C trap prologue/epilogue with the
    // synchronous, uncached instruction path as well as the cached path.
    // A 500-cycle restart could expire inside the handler and starve main.
    timer0_start_irq(5000u);
    while (count < 2u) {
        __asm__ volatile("nop");
    }
    timer0_stop();
    __asm__ volatile("li x27, 1");
    return 0;
}
void timer0_irq_handler(void) {
    timer0_ack_restart();
    ++count;
}
