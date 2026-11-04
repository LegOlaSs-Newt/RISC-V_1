/*
 * 模块说明：等待接口 UART 下载控制。
 * 来源说明：本项目在 TinyRISC-V UART 下载协议基础上新增。
 * 主要改动：解析主机下载包，通过 ready valid 接口逐字写入程序区。
 * 关键约束：获得独占访问后才写入；地址推进和包 ACK 不早于相应写完成。恢复 CPU 前排空并维护缓存状态。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Transaction-aware implementation of the existing 131-byte UART protocol.
// CRC covers 128 payload bytes. No data write starts before CRC validation;
// the packet ACK is issued only after every payload word has completed.
`include "../../mes50hp_config.vh"
module uart_debug_wait (
    input wire clk,
    rst,
    enable_i,
    stop_i,
    output wire req_valid_o,
    req_write_o,
    output wire [31:0] req_addr_o,
    req_wdata_o,
    input wire req_ready_i,
    rsp_valid_i,
    rsp_error_i,
    input wire [31:0] rsp_data_i,
    output wire rsp_ready_o,
    idle_o,
    output reg image_complete_o
);
    localparam CONFIG = 0, BAUD = 1, CLEAR = 2, POLL = 3, GET = 4, CHECK = 5, WRITE = 6,
        ACK_POLL = 7, ACK = 8, NEW_PACKET = 9;
    reg [3:0] state;
    reg accepted, exposed, header, last_byte;
    reg [7:0] payload[0:127];
    reg [7:0] rx_index, packet_number, expected_packet, crc_lo, crc_hi, ack;
    reg [15:0] crc, remaining;
    reg [31:0] write_address;
    reg [4:0] word_index;
    wire command_state = state == CONFIG || state == BAUD || state == CLEAR || state == POLL ||
        state == GET || state == WRITE || state == ACK_POLL || state == ACK;
    wire [31:0] file_size = {payload[60], payload[61], payload[62], payload[63]};
    wire [6:0] byte_index = {word_index, 2'b00};
    assign req_valid_o = rst && enable_i && command_state && !accepted && (!stop_i || exposed);
    assign req_write_o = state == CONFIG || state == BAUD || state == CLEAR || state == WRITE ||
        state == ACK;
    assign req_addr_o = state == CONFIG ? 32'h30000000 :
        state == BAUD ? 32'h30000008 : (state == CLEAR || state == POLL || state == ACK_POLL) ?
        32'h30000004 : state == GET ? 32'h30000010 : state == ACK ? 32'h3000000c : write_address;
    assign
        req_wdata_o = state == CONFIG ? 32'd3 : state == BAUD ? `MES50HP_UART_DIV : state == ACK ?
        {24'b0, ack} : state == WRITE ? {payload[byte_index+7'd3], payload[byte_index+7'd2],
                                         payload[byte_index+7'd1], payload[byte_index]} : 32'b0;
    assign rsp_ready_o = rst && enable_i && accepted;
    assign idle_o = !accepted && !req_valid_o;
    function [15:0] crc_byte(input [15:0] old_crc, input [7:0] value);
        reg [15:0] next_crc;
        integer n;
        begin
            next_crc = old_crc ^ {8'b0, value};
            for (n = 0; n < 8; n = n + 1)
            next_crc = next_crc[0] ? (next_crc >> 1) ^ 16'ha001 : (next_crc >> 1);
            crc_byte = next_crc;
        end
    endfunction
    always @(posedge clk) begin
        if (!rst || !enable_i) begin
            state <= CONFIG;
            accepted <= 0;
            exposed <= 0;
            header <= 1;
            last_byte <= 0;
            rx_index <= 0;
            packet_number <= 0;
            expected_packet <= 0;
            crc_lo <= 0;
            crc_hi <= 0;
            crc <= 16'hffff;
            remaining <= 0;
            write_address <= 0;
            word_index <= 0;
            ack <= 8'h06;
            image_complete_o <= 0;
        end else begin
            if (req_valid_o) exposed <= 1;
            if (req_valid_o && req_ready_i) begin
                accepted <= 1;
                exposed  <= 0;
            end
            if (rsp_valid_i && rsp_ready_o) begin
                accepted <= 0;
                if (rsp_error_i) begin
                    ack   <= 8'h15;
                    state <= ACK_POLL;
                end else
                    case (state)
                        CONFIG: state <= BAUD;
                        BAUD: state <= CLEAR;
                        CLEAR: state <= last_byte ? CHECK : POLL;
                        POLL: if (rsp_data_i[1]) state <= GET;
                        GET: begin
                            if (rx_index == 0) packet_number <= rsp_data_i[7:0];
                            else if (rx_index <= 128) begin
                                payload[rx_index-1'b1] <= rsp_data_i[7:0];
                                crc <= crc_byte(crc, rsp_data_i[7:0]);
                            end else if (rx_index == 129) crc_lo <= rsp_data_i[7:0];
                            else crc_hi <= rsp_data_i[7:0];
                            last_byte <= rx_index == 130;
                            rx_index <= rx_index + 1'b1;
                            state <= CLEAR;
                        end
                        WRITE: begin
                            write_address <= write_address + 4;
                            if (word_index == 31) begin
                                remaining <= remaining - 1'b1;
                                expected_packet <= expected_packet + 1'b1;
                                ack <= 8'h06;
                                state <= ACK_POLL;
                            end else word_index <= word_index + 1'b1;
                        end
                        ACK_POLL: if (!rsp_data_i[0]) state <= ACK;
                        ACK: begin
                            if (ack == 8'h06 && remaining == 0) begin
                                header <= 1;
                                expected_packet <= 0;
                                image_complete_o <= 1;
                            end
                            state <= NEW_PACKET;
                        end
                        default: state <= CONFIG;
                    endcase
            end
            if (state == CHECK) begin
                if (crc != {crc_hi, crc_lo} || packet_number != expected_packet) begin
                    ack   <= 8'h15;
                    state <= ACK_POLL;
                end else if (header) begin
                    if (file_size == 0 || file_size > 16255) begin
                        ack   <= 8'h15;
                        state <= ACK_POLL;
                    end else begin
                        remaining <= (file_size >> 7) + 1'b1;
                        expected_packet <= 1;
                        header <= 0;
                        write_address <= 0;
                        image_complete_o <= 0;
                        ack <= 8'h06;
                        state <= ACK_POLL;
                    end
                end else begin
                    word_index <= 0;
                    state <= WRITE;
                end
            end
            if (state == NEW_PACKET) begin
                rx_index <= 0;
                crc <= 16'hffff;
                last_byte <= 0;
                state <= POLL;
            end
        end
    end
endmodule
