/*
 * 模块说明：程序计数器控制。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "defines.v"

// PC寄存器模块
module pc_reg (

    input wire clk,
    input wire rst,

    input wire                  jump_flag_i,        // 跳转标志
    input wire [  `InstAddrBus] jump_addr_i,        // 跳转地址
    input wire [`Hold_Flag_Bus] hold_flag_i,        // 流水线暂停标志
    input wire                  jtag_reset_flag_i,  // 复位标志
    input wire [          31:0] predicted_next_i,

    output reg [`InstAddrBus] pc_o  // PC指针

);


    always @(posedge clk) begin
        // 复位
        if (rst == `RstEnable || jtag_reset_flag_i == 1'b1) begin
            pc_o <= `CpuResetAddr;
            // 跳转
        end else if (jump_flag_i == `JumpEnable) begin
            pc_o <= jump_addr_i;
            // 暂停
        end else if (hold_flag_i >= `Hold_Pc) begin
            pc_o <= pc_o;
            // 地址加4
        end else begin
            pc_o <= predicted_next_i;
        end
    end

endmodule
