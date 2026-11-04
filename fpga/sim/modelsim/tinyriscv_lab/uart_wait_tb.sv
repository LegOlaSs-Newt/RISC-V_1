/*
 * 模块说明：uart_wait_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：uart_wait_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module uart_wait_tb #(
    parameter integer SEED = 1
);
    reg clk = 0, rst = 0, enable = 0, stop = 0;
    always #5 clk = ~clk;
    wire valid, write_req, rsp_ready, idle, complete;
    wire [31:0] address, data;
    reg response_valid = 0, response_error = 0, pending = 0, byte_read = 0;
    reg [31:0] response_data = 0, owner_address, owner_data, rng = SEED;
    reg owner_write;
    reg [7:0] bytes[0:392], payload[0:127];
    reg [31:0] memory[0:31];
    integer
        cycles = 0,
        delay_count = 0,
        rx_position = 0,
        stores = 0,
        acks = 0,
        naks = 0,
        requests = 0,
        responses = 0;
    wire ready = rst && !pending && cycles > 12 && rng[0];
    integer i, j, k, packet_base;
    reg [15:0] crc;
    reg passed = 0, pause_checked = 0;
    reg stalled = 0;
    reg [64:0] stalled_payload;
    uart_debug_wait dut (
        .clk(clk),
        .rst(rst),
        .enable_i(enable),
        .stop_i(stop),
        .req_valid_o(valid),
        .req_write_o(write_req),
        .req_addr_o(address),
        .req_wdata_o(data),
        .req_ready_i(ready),
        .rsp_valid_i(response_valid),
        .rsp_error_i(response_error),
        .rsp_data_i(response_data),
        .rsp_ready_o(rsp_ready),
        .idle_o(idle),
        .image_complete_o(complete)
    );
    task automatic build_packet(input integer base, input [7:0] number, input bit corrupt);
        integer n, b;
        reg [15:0] value;
        begin
            bytes[base] = number;
            value = 16'hffff;
            for (n = 0; n < 128; n = n + 1) begin
                bytes[base+n+1] = payload[n];
                value = value ^ payload[n];
                for (b = 0; b < 8; b = b + 1)
                value = value[0] ? (value >> 1) ^ 16'ha001 : (value >> 1);
            end
            bytes[base+129] = value[7:0];
            bytes[base+130] = value[15:8] ^ (corrupt ? 8'h01 : 8'h00);
        end
    endtask
    initial begin
        for (i = 0; i < 128; i = i + 1) payload[i] = 0;
        payload[63] = 32;
        build_packet(0, 0, 0);
        for (i = 0; i < 128; i = i + 1) payload[i] = i;
        build_packet(131, 1, 1);
        build_packet(262, 1, 0);
        for (i = 0; i < 32; i = i + 1) memory[i] = 32'hffffffff;
        repeat (4) @(negedge clk);
        rst = 1;
        enable = 1;
        wait (valid && !ready);
        @(negedge clk);
        stop = 1;
        wait (idle);
        repeat (3) @(negedge clk);
        stop = 0;
        pause_checked = 1;
    end
    always @(posedge clk)
        if (rst) begin
            cycles = cycles + 1;
            rng <= {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            if (stalled && (!valid || {write_req, address, data} !== stalled_payload))
                $fatal(1, "UART request changed under backpressure/stop");
            stalled = valid && !ready;
            stalled_payload = {write_req, address, data};
            if (valid && ready) begin
                if (pending) $fatal(1, "duplicate UART request");
                pending <= 1;
                owner_address <= address;
                owner_data <= data;
                owner_write <= write_req;
                delay_count <= 1 + int'(rng[5:3]);
                requests = requests + 1;
            end
            if (pending && !response_valid) begin
                if (delay_count != 0) delay_count <= delay_count - 1;
                else begin
                    response_valid <= 1;
                    response_data  <= 0;
                    if (owner_write) begin
                        case (owner_address)
                            32'h30000004:
                            if (byte_read) begin
                                rx_position = rx_position + 1;
                                byte_read   = 0;
                            end
                            32'h3000000c: begin
                                if (owner_data == 6) begin
                                    acks = acks + 1;
                                    if ((acks == 1 && stores != 0) || (acks == 2 && stores != 32))
                                        $fatal(1, "ACK before completed writes");
                                end else if (owner_data == 21) begin
                                    naks = naks + 1;
                                    if (stores != 0) $fatal(1, "bad CRC wrote memory");
                                end else $fatal(1, "unknown protocol response");
                            end
                            default:
                            if (owner_address < 128) begin
                                stores = stores + 1;
                                memory[owner_address/4] = owner_data;
                            end
                        endcase
                    end else if (owner_address == 32'h30000004)
                        response_data <= rx_position < 393 ? 32'd2 : 32'd0;
                    else if (owner_address == 32'h30000010) begin
                        response_data <= {24'b0, bytes[rx_position]};
                        byte_read = 1;
                    end
                end
            end
            if (response_valid && rsp_ready) begin
                response_valid <= 0;
                pending <= 0;
                responses = responses + 1;
            end
            if (complete && idle) begin
                if (!pause_checked || acks != 2 || naks != 1 || stores != 32 ||
                    requests != responses)
                    $fatal(1, "protocol/count mismatch");
                for (j = 0; j < 32; j = j + 1)
                if (memory[j] !==
                    {bytes[262+j*4+4], bytes[262+j*4+3], bytes[262+j*4+2], bytes[262+j*4+1]})
                    $fatal(1, "payload word mismatch");
                passed = 1;
                $display(
                    "UART_WAIT_PASS seed=%0d cycles=%0d ACK=%0d NAK=%0d stores=%0d requests=%0d responses=%0d stop_drain=%b",
                    SEED, cycles, acks, naks, stores, requests, responses, pause_checked);
                $finish;
            end
            if (cycles > 100000) $fatal(1, "timeout rx=%0d state=%0d", rx_position, dut.state);
        end
endmodule
