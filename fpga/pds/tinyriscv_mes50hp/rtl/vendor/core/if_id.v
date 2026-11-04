/*
 * 模块说明：取指到译码流水寄存器。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "defines.v"

// 将指令向译码模块传递
module if_id (

    input  wire clk,
    input  wire rst,
    input  wire stall_i,
    input  wire fetch_error_i,
    output wire fetch_error_o,

    // A RIB-arbitration placeholder is not an instruction.
    input wire valid_i,
    output wire valid_o,
    input wire [31:0] predicted_next_i,
    output wire [31:0] predicted_next_o,

    input wire [    `InstBus] inst_i,      // 指令内容
    input wire [`InstAddrBus] inst_addr_i, // 指令地址

    input wire [`Hold_Flag_Bus] hold_flag_i,  // 流水线暂停标志

    input  wire [`INT_BUS] int_flag_i,  // 外设中断输入信号
    output wire [`INT_BUS] int_flag_o,

    output wire [    `InstBus] inst_o,      // 指令内容
    output wire [`InstAddrBus] inst_addr_o  // 指令地址

);

    // Flush has priority; stall retains the complete instruction identity.
    reg [105:0] stage;
    wire hold_en = (hold_flag_i >= `Hold_If);
    assign {fetch_error_o, valid_o, predicted_next_o, inst_o, inst_addr_o, int_flag_o} = stage;
    always @(posedge clk) begin
        if (!rst || hold_en) stage <= {1'b0, 1'b0, 32'b0, `INST_NOP, 32'b0, `INT_NONE};
        else if (!stall_i)
            stage <= {fetch_error_i, valid_i, predicted_next_i, inst_i, inst_addr_i, int_flag_i};
    end
endmodule
