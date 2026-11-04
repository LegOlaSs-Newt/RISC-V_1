/*
 * 模块说明：等待接口调试模块。
 * 来源说明：本项目在 TinyRISC-V 调试模块基础上新增。
 * 主要改动：把 DMI 调试请求转换为可等待的存储事务，保存返回与命令归属。
 * 关键约束：访问完成后才返回或推进地址；不能因暂停或反压重复写入。本模块有仿真覆盖，当前板级无 CPU 软件 JTAG 实板验收。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Transaction-aware counterpart of the existing, limited TinyRISC-V DM map.
// Retains GPR/DCSR/DPC control and 32-bit system-bus access. This is not a
// claim of complete RISC-V Debug specification compliance.
module jtag_dm_wait #(
    parameter DMI_ADDR_BITS = 6,
    DMI_DATA_BITS = 32,
    DMI_OP_BITS = 2
) (
    input wire clk,
    rst_n,
    output wire dm_ack_o,
    input wire dtm_req_valid_i,
    input wire [DMI_ADDR_BITS+DMI_DATA_BITS+DMI_OP_BITS-1:0] dtm_req_data_i,
    input wire dtm_ack_i,
    output wire [DMI_ADDR_BITS+DMI_DATA_BITS+DMI_OP_BITS-1:0] dm_resp_data_o,
    output wire dm_resp_valid_o,
    output reg dm_reg_we_o,
    output reg [4:0] dm_reg_addr_o,
    output reg [31:0] dm_reg_wdata_o,
    input wire [31:0] dm_reg_rdata_i,
    output reg dm_mem_req_o,
    dm_mem_we_o,
    output reg [31:0] dm_mem_addr_o,
    dm_mem_wdata_o,
    input wire dm_mem_ready_i,
    dm_mem_valid_i,
    dm_mem_error_i,
    input wire [31:0] dm_mem_rdata_i,
    output wire dm_mem_response_ready_o,
    output wire dm_op_req_o,
    output reg dm_halt_req_o,
    dm_reset_req_o,
    input wire halted_i
);
    localparam WIDTH = DMI_ADDR_BITS + DMI_DATA_BITS + DMI_OP_BITS;
    wire rx_valid, tx_idle;
    wire [WIDTH-1:0] rx_data;
    wire [DMI_OP_BITS-1:0] op = rx_data[DMI_OP_BITS-1:0];
    wire [31:0] value = rx_data[DMI_OP_BITS+31:DMI_OP_BITS];
    wire [DMI_ADDR_BITS-1:0] address = rx_data[WIDTH-1:DMI_DATA_BITS+DMI_OP_BITS];
    reg operation_pending, need_response, response_started, mem_accepted;
    reg [DMI_ADDR_BITS-1:0] response_address;
    reg [31:0] read_data, dmcontrol, sbcs, sbaddress, data0, dcsr, abstractcs, sbdata;
    reg [1:0] response_code, mem_kind;
    reg read_gpr, cached_data;
    wire [31:0] next_address = sbaddress + 4;
    wire [31:0] dmstatus = halted_i ? 32'h00430382 : 32'h00430c82;
    full_handshake_rx #(
        .DW(WIDTH)
    ) rx (
        .clk(clk),
        .rst_n(rst_n),
        .req_i(dtm_req_valid_i && !operation_pending),
        .req_data_i(dtm_req_data_i),
        .ack_o(dm_ack_o),
        .recv_data_o(rx_data),
        .recv_rdy_o(rx_valid)
    );
    full_handshake_tx #(
        .DW(WIDTH)
    ) tx (
        .clk(clk),
        .rst_n(rst_n),
        .ack_i(dtm_ack_i),
        .req_i(need_response),
        .req_data_i({response_address, read_data, response_code}),
        .idle_o(tx_idle),
        .req_o(dm_resp_valid_o),
        .req_data_o(dm_resp_data_o)
    );
    assign dm_mem_response_ready_o = mem_accepted;
    assign dm_op_req_o = operation_pending;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            operation_pending <= 0;
            need_response <= 0;
            response_started <= 0;
            mem_accepted <= 0;
            dm_mem_req_o <= 0;
            dm_mem_we_o <= 0;
            dm_mem_addr_o <= 0;
            dm_mem_wdata_o <= 0;
            dm_reg_we_o <= 0;
            dm_reg_addr_o <= 0;
            dm_reg_wdata_o <= 0;
            dm_halt_req_o <= 0;
            dm_reset_req_o <= 0;
            response_address <= 0;
            read_data <= 0;
            response_code <= 0;
            dmcontrol <= 0;
            sbcs <= 32'h20040404;
            sbaddress <= 0;
            data0 <= 0;
            dcsr <= 0;
            abstractcs <= 32'h01000003;
            sbdata <= 0;
            mem_kind <= 0;
            read_gpr <= 0;
            cached_data <= 0;
        end else begin
            dm_reg_we_o <= 0;
            dm_reset_req_o <= 0;
            if (need_response && tx_idle) begin
                need_response <= 0;
                response_started <= 1;
            end
            if (response_started && tx_idle && !need_response) begin
                operation_pending <= 0;
                response_started  <= 0;
            end
            if (dm_mem_req_o && dm_mem_ready_i) begin
                dm_mem_req_o <= 0;
                mem_accepted <= 1;
            end
            if (mem_accepted && dm_mem_valid_i) begin
                mem_accepted <= 0;
                if (dm_mem_error_i) begin
                    response_code <= 2;
                    read_data <= 0;
                    sbcs[14:12] <= 3'd2;
                    cached_data <= 0;
                    need_response <= 1;
                end else if (mem_kind == 0) begin
                    if (sbcs[16]) sbaddress <= next_address;
                    need_response <= 1;
                end else if (mem_kind == 2) begin
                    sbdata <= dm_mem_rdata_i;
                    cached_data <= 1;
                    need_response <= 1;
                end else begin
                    read_data   <= dm_mem_rdata_i;
                    cached_data <= 0;
                    if (sbcs[16]) sbaddress <= next_address;
                    if (sbcs[15]) begin
                        dm_mem_addr_o <= sbcs[16] ? next_address : sbaddress;
                        dm_mem_we_o <= 0;
                        dm_mem_req_o <= 1;
                        mem_kind <= 2;
                    end else need_response <= 1;
                end
            end
            if (rx_valid) begin
                operation_pending <= 1;
                response_address <= address;
                response_code <= 0;
                read_data <= 0;
                need_response <= 1;
                case (op)
                    1:
                    case (address)
                        6'h11: read_data <= dmstatus;
                        6'h10: read_data <= dmcontrol;
                        6'h12: read_data <= 0;
                        6'h16: read_data <= abstractcs;
                        6'h04: begin
                            read_data <= read_gpr ? dm_reg_rdata_i : data0;
                            read_gpr  <= 0;
                        end
                        6'h38:
                        read_data <= (sbcs & 32'hffdfffff) |
                            ((dm_mem_req_o || mem_accepted) ? 32'h00200000 : 0);
                        6'h39: read_data <= sbaddress;
                        6'h3c: begin
                            if (cached_data) begin
                                read_data   <= sbdata;
                                cached_data <= 0;
                                if (sbcs[16]) sbaddress <= next_address;
                                if (sbcs[15]) begin
                                    dm_mem_addr_o <= sbcs[16] ? next_address : sbaddress;
                                    dm_mem_we_o <= 0;
                                    dm_mem_req_o <= 1;
                                    mem_kind <= 2;
                                    need_response <= 0;
                                end
                            end else begin
                                dm_mem_addr_o <= sbaddress;
                                dm_mem_we_o <= 0;
                                dm_mem_req_o <= 1;
                                mem_kind <= 1;
                                need_response <= 0;
                            end
                        end
                        default: read_data <= 0;
                    endcase
                    2:
                    case (address)
                        6'h10: begin
                            dmcontrol <= value;
                            if (!value[0]) begin
                                dm_halt_req_o <= 0;
                                dcsr <= 32'hc0;
                                sbcs <= 32'h20040404;
                                abstractcs <= 32'h01000003;
                            end else if (value[31]) dm_halt_req_o <= 1;
                            else if (value[30]) dm_halt_req_o <= 0;
                        end
                        6'h04: data0 <= value;
                        6'h38: begin
                            sbcs <= value;
                            cached_data <= 0;
                        end
                        6'h39: begin
                            sbaddress   <= value;
                            cached_data <= 0;
                            if (sbcs[20]) begin
                                dm_mem_addr_o <= value;
                                dm_mem_we_o <= 0;
                                dm_mem_req_o <= 1;
                                mem_kind <= 2;
                                need_response <= 0;
                            end
                        end
                        6'h3c: begin
                            dm_mem_addr_o <= sbaddress;
                            dm_mem_wdata_o <= value;
                            dm_mem_we_o <= 1;
                            dm_mem_req_o <= 1;
                            mem_kind <= 0;
                            cached_data <= 0;
                            need_response <= 0;
                        end
                        6'h17: begin
                            if (value[31:24] != 0 || value[22:20] > 2 || value[18])
                                abstractcs[10:8] <= 2;
                            else begin
                                abstractcs[10:8] <= 0;
                                dm_reg_addr_o <= value[4:0];
                                if (!value[16]) begin
                                    if (value[15:0] == 16'h7b0) begin
                                        data0 <= dcsr;
                                        read_gpr <= 0;
                                    end else if (value[15:0] >= 16'h1000 && value[15:0] < 16'h1020)
                                        read_gpr <= 1;
                                    else abstractcs[10:8] <= 2;
                                end else if (value[15:0] == 16'h7b1) begin
                                    dm_reset_req_o <= 1;
                                    dm_halt_req_o  <= 0;
                                end else if (value[15:0] == 16'h7b0) dcsr <= data0;
                                else if (value[15:0] >= 16'h1000 && value[15:0] < 16'h1020) begin
                                    dm_reg_wdata_o <= data0;
                                    dm_reg_we_o <= 1;
                                end else abstractcs[10:8] <= 2;
                            end
                        end
                        default: begin
                        end
                    endcase
                    default: begin
                    end
                endcase
            end
        end
    end
endmodule
