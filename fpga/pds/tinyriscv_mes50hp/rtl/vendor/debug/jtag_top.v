/*
 * 模块说明：CPU 调试模块连接。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "../core/defines.v"

// JTAG顶层模块
module jtag_top #(
    parameter DMI_ADDR_BITS = 6,
    parameter DMI_DATA_BITS = 32,
    parameter DMI_OP_BITS   = 2,
    parameter WAIT_MEMORY   = 0
) (

    input wire clk,
    input wire jtag_rst_n,

    input  wire jtag_pin_TCK,
    input  wire jtag_pin_TMS,
    input  wire jtag_pin_TDI,
    output wire jtag_pin_TDO,

    output wire reg_we_o,
    output wire [4:0] reg_addr_o,
    output wire [31:0] reg_wdata_o,
    input wire [31:0] reg_rdata_i,
    output wire mem_we_o,
    output wire [31:0] mem_addr_o,
    output wire [31:0] mem_wdata_o,
    input wire [31:0] mem_rdata_i,
    output wire op_req_o,
    output wire mem_req_valid_o,
    mem_rsp_ready_o,
    input wire mem_req_ready_i,
    mem_rsp_valid_i,
    mem_rsp_error_i,
    halted_i,

    output wire halt_req_o,
    output wire reset_req_o

);

    parameter DM_RESP_BITS = DMI_ADDR_BITS + DMI_DATA_BITS + DMI_OP_BITS;
    parameter DTM_REQ_BITS = DMI_ADDR_BITS + DMI_DATA_BITS + DMI_OP_BITS;

    // jtag_driver
    wire dtm_ack_o;
    wire dtm_req_valid_o;
    wire [DTM_REQ_BITS - 1:0] dtm_req_data_o;

    // jtag_dm
    wire dm_ack_o;
    wire [DM_RESP_BITS-1:0] dm_resp_data_o;
    wire dm_resp_valid_o;
    wire dm_op_req_o;
    wire dm_halt_req_o;
    wire dm_reset_req_o;

    jtag_driver #(
        .DMI_ADDR_BITS(DMI_ADDR_BITS),
        .DMI_DATA_BITS(DMI_DATA_BITS),
        .DMI_OP_BITS  (DMI_OP_BITS)
    ) u_jtag_driver (
        .rst_n(jtag_rst_n),
        .jtag_TCK(jtag_pin_TCK),
        .jtag_TDI(jtag_pin_TDI),
        .jtag_TMS(jtag_pin_TMS),
        .jtag_TDO(jtag_pin_TDO),
        .dm_resp_i(dm_resp_valid_o),
        .dm_resp_data_i(dm_resp_data_o),
        .dtm_ack_o(dtm_ack_o),
        .dm_ack_i(dm_ack_o),
        .dtm_req_valid_o(dtm_req_valid_o),
        .dtm_req_data_o(dtm_req_data_o)
    );

    generate
        if (WAIT_MEMORY) begin : wait_dm
            jtag_dm_wait #(
                .DMI_ADDR_BITS(DMI_ADDR_BITS),
                .DMI_DATA_BITS(DMI_DATA_BITS),
                .DMI_OP_BITS  (DMI_OP_BITS)
            ) u_jtag_dm_wait (
                .clk(clk),
                .rst_n(jtag_rst_n),
                .dm_ack_o(dm_ack_o),
                .dtm_req_valid_i(dtm_req_valid_o),
                .dtm_req_data_i(dtm_req_data_o),
                .dtm_ack_i(dtm_ack_o),
                .dm_resp_data_o(dm_resp_data_o),
                .dm_resp_valid_o(dm_resp_valid_o),
                .dm_reg_we_o(reg_we_o),
                .dm_reg_addr_o(reg_addr_o),
                .dm_reg_wdata_o(reg_wdata_o),
                .dm_reg_rdata_i(reg_rdata_i),
                .dm_mem_req_o(mem_req_valid_o),
                .dm_mem_we_o(mem_we_o),
                .dm_mem_addr_o(mem_addr_o),
                .dm_mem_wdata_o(mem_wdata_o),
                .dm_mem_ready_i(mem_req_ready_i),
                .dm_mem_valid_i(mem_rsp_valid_i),
                .dm_mem_error_i(mem_rsp_error_i),
                .dm_mem_rdata_i(mem_rdata_i),
                .dm_mem_response_ready_o(mem_rsp_ready_o),
                .dm_op_req_o(op_req_o),
                .dm_halt_req_o(halt_req_o),
                .dm_reset_req_o(reset_req_o),
                .halted_i(halted_i)
            );
        end else begin : legacy_dm
            assign mem_req_valid_o = 1'b0;
            assign mem_rsp_ready_o = 1'b0;
            jtag_dm #(
                .DMI_ADDR_BITS(DMI_ADDR_BITS),
                .DMI_DATA_BITS(DMI_DATA_BITS),
                .DMI_OP_BITS  (DMI_OP_BITS)
            ) u_jtag_dm (
                .clk(clk),
                .rst_n(jtag_rst_n),
                .dm_ack_o(dm_ack_o),
                .dtm_req_valid_i(dtm_req_valid_o),
                .dtm_req_data_i(dtm_req_data_o),
                .dtm_ack_i(dtm_ack_o),
                .dm_resp_data_o(dm_resp_data_o),
                .dm_resp_valid_o(dm_resp_valid_o),
                .dm_reg_we_o(reg_we_o),
                .dm_reg_addr_o(reg_addr_o),
                .dm_reg_wdata_o(reg_wdata_o),
                .dm_reg_rdata_i(reg_rdata_i),
                .dm_mem_we_o(mem_we_o),
                .dm_mem_addr_o(mem_addr_o),
                .dm_mem_wdata_o(mem_wdata_o),
                .dm_mem_rdata_i(mem_rdata_i),
                .dm_op_req_o(op_req_o),
                .dm_halt_req_o(halt_req_o),
                .dm_reset_req_o(reset_req_o)
            );
        end
    endgenerate

endmodule
