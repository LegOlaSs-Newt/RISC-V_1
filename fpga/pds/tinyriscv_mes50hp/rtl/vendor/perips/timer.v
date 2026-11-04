/*
 * 模块说明：计时器与机器中断源。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "../core/defines.v"


// 32 bits count up timer module
module timer (

    input wire clk,
    input wire rst,

    input wire [31:0] data_i,
    input wire [31:0] addr_i,
    input wire we_i,

    output reg [31:0] data_o,
    output wire int_sig_o,
    output wire software_int_o

);

    localparam REG_CTRL  = 4'h0;
    localparam REG_COUNT = 4'h4;
    localparam REG_VALUE = 4'h8;

    // [0]: timer enable
    // [1]: timer int enable
    // [2]: timer int pending, write 1 to clear it
    // addr offset: 0x00
    reg [31:0] timer_ctrl;

    // timer current count, read only
    // addr offset: 0x04
    reg [31:0] timer_count;

    // timer expired value
    // addr offset: 0x08
    reg [31:0] timer_value;
    reg msip;
    assign software_int_o = msip;
    always @(posedge clk) begin
        if (!rst) msip <= 1'b0;
        else if (we_i && addr_i == 32'hc) msip <= data_i[0];
    end


    assign int_sig_o = ((timer_ctrl[2] == 1'b1) && (timer_ctrl[1] == 1'b1)) ? `INT_ASSERT :
        `INT_DEASSERT;

    // counter
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            timer_count <= `ZeroWord;
        end else begin
            if (timer_ctrl[0] == 1'b1) begin
                timer_count <= timer_count + 1'b1;
                if (timer_count >= timer_value) begin
                    timer_count <= `ZeroWord;
                end
            end else begin
                timer_count <= `ZeroWord;
            end
        end
    end

    // write regs
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            timer_ctrl  <= `ZeroWord;
            timer_value <= `ZeroWord;
        end else begin
            // MSIP and read-only/unknown register writes are independent of
            // timer expiration. Only CTRL/VALUE retain the original priority.
            if (we_i == `WriteEnable && (addr_i == 32'h0 || addr_i == 32'h8)) begin
                case (addr_i[3:0])
                    REG_CTRL: begin
                        timer_ctrl <= {data_i[31:3], (timer_ctrl[2] & (~data_i[2])), data_i[1:0]};
                    end
                    REG_VALUE: begin
                        timer_value <= data_i;
                    end
                endcase
            end else begin
                if ((timer_ctrl[0] == 1'b1) && (timer_count >= timer_value)) begin
                    timer_ctrl[0] <= 1'b0;
                    timer_ctrl[2] <= 1'b1;
                end
            end
        end
    end

    // read regs
    always @(*) begin
        if (rst == `RstEnable) begin
            data_o = `ZeroWord;
        end else begin
            case (addr_i[3:0])
                4'hc: data_o = {31'b0, msip};
                REG_VALUE: begin
                    data_o = timer_value;
                end
                REG_CTRL: begin
                    data_o = timer_ctrl;
                end
                REG_COUNT: begin
                    data_o = timer_count;
                end
                default: begin
                    data_o = `ZeroWord;
                end
            endcase
        end
    end

endmodule
