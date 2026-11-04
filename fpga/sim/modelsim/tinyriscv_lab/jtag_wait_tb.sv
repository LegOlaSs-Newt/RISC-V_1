/*
 * 模块说明：jtag_wait_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：jtag_wait_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module jtag_wait_tb;
    reg clk = 0, rst = 0, request = 0, response_ack = 0, halted = 0;
    always #5 clk = ~clk;
    reg [39:0] request_data = 0;
    wire request_ack, response_valid;
    wire [39:0] response_data;
    wire mv, mw, mrr, gwe, halt, reset_cpu;
    wire [31:0] ma, md, gd;
    wire [4:0] ga;
    reg ready = 0, valid = 0, error = 0, busy = 0;
    reg [31:0] rdata = 0, owner_addr, owner_data;
    reg owner_write;
    reg [31:0] memory[0:63], gpr[0:31];
    integer
        delay_count = 0, cycles = 0, requests = 0, responses = 0, stores = 0, reset_count = 0, i;
    reg passed = 0, stalled = 0;
    reg [64:0] held;
    jtag_dm_wait dut (
        .clk(clk),
        .rst_n(rst),
        .dm_ack_o(request_ack),
        .dtm_req_valid_i(request),
        .dtm_req_data_i(request_data),
        .dtm_ack_i(response_ack),
        .dm_resp_valid_o(response_valid),
        .dm_resp_data_o(response_data),
        .dm_reg_we_o(gwe),
        .dm_reg_addr_o(ga),
        .dm_reg_wdata_o(gd),
        .dm_reg_rdata_i(gpr[ga]),
        .dm_mem_req_o(mv),
        .dm_mem_we_o(mw),
        .dm_mem_addr_o(ma),
        .dm_mem_wdata_o(md),
        .dm_mem_ready_i(ready),
        .dm_mem_valid_i(valid),
        .dm_mem_error_i(error),
        .dm_mem_rdata_i(rdata),
        .dm_mem_response_ready_o(mrr),
        .dm_op_req_o(),
        .dm_halt_req_o(halt),
        .dm_reset_req_o(reset_cpu),
        .halted_i(halted)
    );
    task automatic dmi(input [1:0] op, input [5:0] addr, input [31:0] data, input [1:0] code,
                       input bit check_value, input [31:0] expected);
        reg [39:0] saved;
        begin
            @(negedge clk);
            request_data = {addr, data, op};
            request = 1;
            wait (request_ack);
            @(negedge clk);
            request = 0;
            wait (!request_ack);
            wait (response_valid);
            saved = response_data;
            if (saved[39:34] !== addr || saved[1:0] !== code ||
                (check_value && saved[33:2] !== expected))
                $fatal(
                    1,
                    "DMI result addr=%h got=%h expected=%h code=%b",
                    addr,
                    saved[33:2],
                    expected,
                    saved[1:0]
                );
            if (busy) $fatal(1, "DMI acknowledged before memory completed");
            repeat (3) begin
                @(negedge clk);
                if (response_data !== saved || !response_valid) $fatal(1, "DMI response not held");
            end
            response_ack = 1;
            wait (!response_valid);
            @(negedge clk);
            response_ack = 0;
        end
    endtask
    always @(negedge clk) ready = rst && !busy && cycles % 4 == 0;
    always @(posedge clk)
        if (rst) begin
            cycles = cycles + 1;
            if (stalled && (!mv || {mw, ma, md} !== held))
                $fatal(1, "JTAG memory request changed under backpressure");
            stalled = mv && !ready;
            held = {mw, ma, md};
            if (mv && ready) begin
                if (busy) $fatal(1, "JTAG duplicate request");
                busy <= 1;
                owner_addr <= ma;
                owner_data <= md;
                owner_write <= mw;
                delay_count <= 11;
                requests = requests + 1;
            end
            if (busy && !valid) begin
                if (delay_count != 0) delay_count <= delay_count - 1;
                else begin
                    valid <= 1;
                    error <= owner_addr == 32'h100000fc;
                    rdata <= memory[owner_addr[7:2]];
                    if (owner_write && owner_addr != 32'h100000fc) begin
                        memory[owner_addr[7:2]] <= owner_data;
                        stores = stores + 1;
                    end
                end
            end
            if (valid && mrr) begin
                valid <= 0;
                busy  <= 0;
                error <= 0;
                responses = responses + 1;
            end
            if (gwe && ga != 0) gpr[ga] <= gd;
            if (reset_cpu) reset_count = reset_count + 1;
            if (cycles > 30000) $fatal(1, "timeout");
        end
    initial begin
        for (i = 0; i < 64; i = i + 1) memory[i] = i;
        for (i = 0; i < 32; i = i + 1) gpr[i] = 0;
        repeat (4) @(negedge clk);
        rst = 1;
        dmi(2, 6'h38, 32'h00040000, 0, 0, 0);
        dmi(2, 6'h39, 32'h10000010, 0, 0, 0);
        dmi(2, 6'h3c, 32'ha5013412, 0, 0, 0);
        if (memory[4] !== 32'ha5013412 || stores != 1) $fatal(1, "store completion wrong");
        dmi(1, 6'h3c, 0, 0, 1, 32'ha5013412);
        dmi(2, 6'h38, 32'h00050000, 0, 0, 0);
        dmi(2, 6'h39, 32'h10000020, 0, 0, 0);
        dmi(2, 6'h3c, 32'ha5, 0, 0, 0);
        dmi(2, 6'h3c, 32'hb6, 0, 0, 0);
        dmi(1, 6'h39, 0, 0, 1, 32'h10000028);
        dmi(2, 6'h38, 32'h00158000, 0, 0, 0);
        dmi(2, 6'h39, 32'h10000020, 0, 0, 0);
        dmi(1, 6'h3c, 0, 0, 1, 32'ha5);
        dmi(1, 6'h3c, 0, 0, 1, 32'hb6);
        dmi(1, 6'h39, 0, 0, 1, 32'h10000028);
        dmi(2, 6'h38, 32'h00040000, 0, 0, 0);
        dmi(2, 6'h39, 32'h100000fc, 0, 0, 0);
        dmi(2, 6'h3c, 32'hdeadbeef, 2, 0, 0);
        if (memory[63] !== 63) $fatal(1, "faulted write changed memory");
        dmi(2, 6'h10, 32'h80000001, 0, 0, 0);
        if (!halt) $fatal(1, "halt request missing");
        dmi(1, 6'h11, 0, 0, 1, 32'h00430c82);
        halted = 1;
        dmi(1, 6'h11, 0, 0, 1, 32'h00430382);
        dmi(2, 6'h04, 32'h76543210, 0, 0, 0);
        dmi(2, 6'h17, 32'h00231005, 0, 0, 0);
        dmi(2, 6'h17, 32'h00221005, 0, 0, 0);
        dmi(1, 6'h04, 0, 0, 1, 32'h76543210);
        dmi(2, 6'h17, 32'h002307b1, 0, 0, 0);
        if (reset_count != 1 || requests != responses || stores != 3)
            $fatal(1, "completion/side-effect counts incorrect");
        passed = 1;
        $display("JTAG_WAIT_PASS requests=%0d responses=%0d stores=%0d reset_pulses=%0d", requests,
                 responses, stores, reset_count);
        $finish;
    end
endmodule
