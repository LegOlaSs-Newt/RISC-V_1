/*
 * 模块说明：通用寄存器堆及读旁路。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "defines.v"

// 通用寄存器模块
module regs (

    input wire clk,
    input wire rst,

    // from ex
    input wire               we_i,     // 写寄存器标志
    input wire [`RegAddrBus] waddr_i,  // 写寄存器地址
    input wire [    `RegBus] wdata_i,  // 写寄存器数据

    // from jtag
    input wire               jtag_we_i,    // 写寄存器标志
    input wire [`RegAddrBus] jtag_addr_i,  // 读、写寄存器地址
    input wire [    `RegBus] jtag_data_i,  // 写寄存器数据

    // from id
    input wire [`RegAddrBus] raddr1_i,  // 读寄存器1地址

    // to id
    output reg [`RegBus] rdata1_o,  // 读寄存器1数据

    // from id
    input wire [`RegAddrBus] raddr2_i,  // 读寄存器2地址

    // to id
    output reg [`RegBus] rdata2_o,  // 读寄存器2数据

    // to jtag
    output reg [`RegBus] jtag_data_o,  // 读寄存器数据

    // MES50HP port: explicit outputs replace unsupported cross-module array reads.
    output wire [`RegBus] test_x26_o,
    output wire [`RegBus] test_x27_o

);

    reg [`RegBus] regs[0:`RegNum - 1];
    assign test_x26_o = regs[26];
    assign test_x27_o = regs[27];

    // 写寄存器
    always @(posedge clk) begin
        if (rst == `RstDisable) begin
            // 优先ex模块写操作
            if ((we_i == `WriteEnable) && (waddr_i != `ZeroReg)) begin
                regs[waddr_i] <= wdata_i;
            end else if ((jtag_we_i == `WriteEnable) && (jtag_addr_i != `ZeroReg)) begin
                regs[jtag_addr_i] <= jtag_data_i;
            end
        end
    end

    // 读寄存器1
    always @(*) begin
        if (raddr1_i == `ZeroReg) begin
            rdata1_o = `ZeroWord;
            // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
        end else if (raddr1_i == waddr_i && we_i == `WriteEnable) begin
            rdata1_o = wdata_i;
        end else begin
            rdata1_o = regs[raddr1_i];
        end
    end

    // 读寄存器2
    always @(*) begin
        if (raddr2_i == `ZeroReg) begin
            rdata2_o = `ZeroWord;
            // 如果读地址等于写地址，并且正在写操作，则直接返回写数据
        end else if (raddr2_i == waddr_i && we_i == `WriteEnable) begin
            rdata2_o = wdata_i;
        end else begin
            rdata2_o = regs[raddr2_i];
        end
    end

    // jtag读寄存器
    always @(*) begin
        if (jtag_addr_i == `ZeroReg) begin
            jtag_data_o = `ZeroWord;
        end else begin
            jtag_data_o = regs[jtag_addr_i];
        end
    end

endmodule
