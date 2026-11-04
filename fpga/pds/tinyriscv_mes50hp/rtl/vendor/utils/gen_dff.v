/*
 * 模块说明：通用流水寄存器。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 带默认值和控制信号的流水线触发器
module gen_pipe_dff #(
    parameter DW = 32
) (

    input wire clk,
    input wire rst,
    input wire hold_en,

    input  wire [DW-1:0] def_val,
    input  wire [DW-1:0] din,
    output wire [DW-1:0] qout

);

    reg [DW-1:0] qout_r;

    always @(posedge clk) begin
        if (!rst | hold_en) begin
            qout_r <= def_val;
        end else begin
            qout_r <= din;
        end
    end

    assign qout = qout_r;

endmodule

// 复位后输出为0的触发器
module gen_rst_0_dff #(
    parameter DW = 32
) (

    input wire clk,
    input wire rst,

    input  wire [DW-1:0] din,
    output wire [DW-1:0] qout

);

    reg [DW-1:0] qout_r;

    always @(posedge clk) begin
        if (!rst) begin
            qout_r <= {DW{1'b0}};
        end else begin
            qout_r <= din;
        end
    end

    assign qout = qout_r;

endmodule

// 复位后输出为1的触发器
module gen_rst_1_dff #(
    parameter DW = 32
) (

    input wire clk,
    input wire rst,

    input  wire [DW-1:0] din,
    output wire [DW-1:0] qout

);

    reg [DW-1:0] qout_r;

    always @(posedge clk) begin
        if (!rst) begin
            qout_r <= {DW{1'b1}};
        end else begin
            qout_r <= din;
        end
    end

    assign qout = qout_r;

endmodule

// 复位后输出为默认值的触发器
module gen_rst_def_dff #(
    parameter DW = 32
) (

    input wire clk,
    input wire rst,
    input wire [DW-1:0] def_val,

    input  wire [DW-1:0] din,
    output wire [DW-1:0] qout

);

    reg [DW-1:0] qout_r;

    always @(posedge clk) begin
        if (!rst) begin
            qout_r <= def_val;
        end else begin
            qout_r <= din;
        end
    end

    assign qout = qout_r;

endmodule

// 带使能端、复位后输出为0的触发器
module gen_en_dff #(
    parameter DW = 32
) (

    input wire clk,
    input wire rst,

    input wire en,
    input wire [DW-1:0] din,
    output wire [DW-1:0] qout

);

    reg [DW-1:0] qout_r;

    always @(posedge clk) begin
        if (!rst) begin
            qout_r <= {DW{1'b0}};
        end else if (en == 1'b1) begin
            qout_r <= din;
        end
    end

    assign qout = qout_r;

endmodule
