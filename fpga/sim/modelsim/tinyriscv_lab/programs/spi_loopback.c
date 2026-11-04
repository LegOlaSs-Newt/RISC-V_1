/*
 * 模块说明：spi_loopback。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
#include <stdint.h>
#include "include/spi.h"
#include "include/utils.h"

// The testbench wires MOSI back to MISO. This is not an SPI flash model.
int main(void) {
    const uint32_t values[2] = {0xa5, 0x3c};
    for (uint32_t mode = 0; mode < 4; ++mode) {
        // The register encodes CPOL in bit 1 and CPHA in bit 2.
        SPI_REG(SPI_CTRL) = (mode << 1) | (1u << 8);
        spi_set_ss(0);
        for (uint32_t i = 0; i < 2; ++i) {
            spi_write_byte(values[i]);
            if ((SPI_REG(SPI_DATA) & 0xffu) != values[i]) {
                set_test_fail();
                return 1;
            }
        }
        spi_set_ss(1);
    }
    set_test_pass();
    return 0;
}
