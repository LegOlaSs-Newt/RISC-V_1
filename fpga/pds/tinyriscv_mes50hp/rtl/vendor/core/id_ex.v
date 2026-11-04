/*
 * 模块说明：译码到执行流水寄存器。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "defines.v"

// 将译码结果向执行模块传递
module id_ex (

    input  wire clk,
    input  wire rst,
    input  wire stall_i,
    input  wire fetch_error_i,
    output wire fetch_error_o,

    input wire valid_i,
    output wire valid_o,
    input wire [31:0] predicted_next_i,
    output wire [31:0] predicted_next_o,

    input wire [    `InstBus] inst_i,        // 指令内容
    input wire [`InstAddrBus] inst_addr_i,   // 指令地址
    input wire                reg_we_i,      // 写通用寄存器标志
    input wire [ `RegAddrBus] reg_waddr_i,   // 写通用寄存器地址
    input wire [     `RegBus] reg1_rdata_i,  // 通用寄存器1读数据
    input wire [     `RegBus] reg2_rdata_i,  // 通用寄存器2读数据
    input wire                csr_we_i,      // 写CSR寄存器标志
    input wire [ `MemAddrBus] csr_waddr_i,   // 写CSR寄存器地址
    input wire [     `RegBus] csr_rdata_i,   // CSR寄存器读数据
    input wire [ `MemAddrBus] op1_i,
    input wire [ `MemAddrBus] op2_i,
    input wire [ `MemAddrBus] op1_jump_i,
    input wire [ `MemAddrBus] op2_jump_i,

    input wire [`Hold_Flag_Bus] hold_flag_i,  // 流水线暂停标志

    output wire [ `MemAddrBus] op1_o,
    output wire [ `MemAddrBus] op2_o,
    output wire [ `MemAddrBus] op1_jump_o,
    output wire [ `MemAddrBus] op2_jump_o,
    output wire [    `InstBus] inst_o,        // 指令内容
    output wire [`InstAddrBus] inst_addr_o,   // 指令地址
    output wire                reg_we_o,      // 写通用寄存器标志
    output wire [ `RegAddrBus] reg_waddr_o,   // 写通用寄存器地址
    output wire [     `RegBus] reg1_rdata_o,  // 通用寄存器1读数据
    output wire [     `RegBus] reg2_rdata_o,  // 通用寄存器2读数据
    output wire                csr_we_o,      // 写CSR寄存器标志
    output wire [ `MemAddrBus] csr_waddr_o,   // 写CSR寄存器地址
    output wire [     `RegBus] csr_rdata_o    // CSR寄存器读数据

);

    // Flush has priority; stall retains the complete instruction identity.
    reg [360:0] stage;
    wire hold_en = (hold_flag_i >= `Hold_Id);
    assign {fetch_error_o, valid_o, predicted_next_o, inst_o, inst_addr_o, reg_we_o, reg_waddr_o,
            reg1_rdata_o, reg2_rdata_o, csr_we_o, csr_waddr_o, csr_rdata_o, op1_o, op2_o,
            op1_jump_o, op2_jump_o} = stage;
    always @(posedge clk) begin
        if (!rst || hold_en)
            stage <= {
                1'b0,
                1'b0,
                32'b0,
                `INST_NOP,
                32'b0,
                1'b0,
                5'b0,
                32'b0,
                32'b0,
                1'b0,
                32'b0,
                32'b0,
                32'b0,
                32'b0,
                32'b0,
                32'b0
            };
        else if (!stall_i)
            stage <= {
                fetch_error_i,
                valid_i,
                predicted_next_i,
                inst_i,
                inst_addr_i,
                reg_we_i,
                reg_waddr_i,
                reg1_rdata_i,
                reg2_rdata_i,
                csr_we_i,
                csr_waddr_i,
                csr_rdata_i,
                op1_i,
                op2_i,
                op1_jump_i,
                op2_jump_i
            };
    end
endmodule
