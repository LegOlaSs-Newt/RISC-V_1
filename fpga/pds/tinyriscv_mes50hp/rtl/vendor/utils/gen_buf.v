/*
 * 模块说明：通用组合缓冲。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 将输入打DP拍后输出
module gen_ticks_sync #(
    parameter DP = 2,
    parameter DW = 32
) (

    input wire rst,
    input wire clk,

    input  wire [DW-1:0] din,
    output wire [DW-1:0] dout

);

    wire [DW-1:0] sync_dat[DP-1:0];

    genvar i;

    generate
        for (i = 0; i < DP; i = i + 1) begin : dp_width
            if (i == 0) begin : dp_is_0
                gen_rst_0_dff #(DW) rst_0_dff (
                    clk,
                    rst,
                    din,
                    sync_dat[0]
                );
            end else begin : dp_is_not_0
                gen_rst_0_dff #(DW) rst_0_dff (
                    clk,
                    rst,
                    sync_dat[i-1],
                    sync_dat[i]
                );
            end
        end
    endgenerate

    assign dout = sync_dat[DP-1];

endmodule
