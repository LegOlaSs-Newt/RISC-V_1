/*
 * 模块说明：memory_system_cpu_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：memory_system_cpu_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module memory_system_cpu_tb #(
    parameter integer CACHE = 1,
    SEED = 1,
    FAULTS = 0
);
    reg clk = 0, rst = 0;
    always #5 clk = ~clk;
    wire [31:0] ia, idata, da, wd, ddata, x26, x27;
    wire iq, irdy, iv, ie, ir, dq, dw, dready, dv, de, dr, fence_i;
    wire [3:0] be;
    wire [31:0] ma, md, qr, qp, pa, pd;
    wire [3:0] ms, ps;
    wire mr, mw, ram_select, pw;
    integer i, cycles = 0, accepted = 0, responses = 0, terminal_retires = 0, mmio_writes = 0;
    reg passed = 0, pending = 0;
    reg [31:0] owner_pc;
    string image;
    tinyriscv #(
        .WAIT_MEMORY(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rib_ex_addr_o(da),
        .rib_ex_data_o(wd),
        .rib_ex_data_i(ddata),
        .rib_ex_req_o(dq),
        .rib_ex_we_o(dw),
        .rib_ex_wstrb_o(be),
        .data_req_ready_i(dready),
        .data_rsp_valid_i(dv),
        .data_rsp_error_i(de),
        .data_rsp_ready_o(dr),
        .rib_pc_addr_o(ia),
        .rib_pc_data_i(idata),
        .fetch_req_valid_o(iq),
        .fetch_req_ready_i(irdy),
        .fetch_rsp_valid_i(iv),
        .fetch_rsp_error_i(ie),
        .fetch_rsp_ready_o(ir),
        .fence_i_o(fence_i),
        .jtag_reg_addr_i(5'b0),
        .jtag_reg_data_i(32'b0),
        .jtag_reg_we_i(1'b0),
        .jtag_reg_data_o(),
        .prediction_clear_i(1'b0),
        .rib_hold_flag_i(1'b0),
        .jtag_halt_flag_i(1'b0),
        .jtag_reset_flag_i(1'b0),
        .int_i(8'b0),
        .test_x26_o(x26),
        .test_x27_o(x27)
    );
    memory_system #(
        .CACHE_ENABLE(CACHE)
    ) memory (
        .clk(clk),
        .rst(rst),
        .fence_i_i(fence_i),
        .invalidate_all_i(1'b0),
        .i_req_valid_i(iq),
        .i_req_addr_i(ia),
        .i_req_ready_o(irdy),
        .i_rsp_valid_o(iv),
        .i_rsp_error_o(ie),
        .i_rsp_data_o(idata),
        .i_rsp_ready_i(ir),
        .d_req_valid_i(dq),
        .d_req_write_i(dw),
        .d_req_addr_i(da),
        .d_req_wdata_i(wd),
        .d_req_wstrb_i(be),
        .d_req_ready_o(dready),
        .d_rsp_valid_o(dv),
        .d_rsp_error_o(de),
        .d_rsp_data_o(ddata),
        .d_rsp_ready_i(dr),
        .h_req_valid_i(1'b0),
        .h_req_write_i(1'b0),
        .h_req_addr_i(32'b0),
        .h_req_wdata_i(32'b0),
        .h_req_ready_o(),
        .h_rsp_valid_o(),
        .h_rsp_error_o(),
        .h_rsp_data_o(),
        .h_rsp_ready_i(1'b1),
        .mem_addr_o(ma),
        .mem_wdata_o(md),
        .mem_wstrb_o(ms),
        .mem_read_en_o(mr),
        .mem_write_en_o(mw),
        .mem_ram_o(ram_select),
        .mem_rdata_i(ram_select ? qr : qp),
        .mmio_addr_o(pa),
        .mmio_wdata_o(pd),
        .mmio_select_o(ps),
        .mmio_write_en_o(pw),
        .timer_rdata_i(32'b0),
        .uart_rdata_i(32'b0),
        .gpio_rdata_i(32'b0),
        .spi_rdata_i(32'b0),
        .idle_o()
    );
    ram #(
        .SYNC_READ(1)
    ) uram (
        .clk(clk),
        .rst(rst),
        .we_i(mw && ram_select),
        .addr_i({18'b0, ma[13:0]}),
        .data_i(md),
        .read_en_i(mr && ram_select),
        .wstrb_i(ms),
        .data_o(qr)
    );
    rom #(
        .SYNC_READ(1)
    ) urom (
        .clk(clk),
        .rst(rst),
        .we_i(mw && !ram_select),
        .addr_i({18'b0, ma[13:0]}),
        .data_i(md),
        .read_en_i(mr && !ram_select),
        .wstrb_i(ms),
        .data_o(qp)
    );
    initial begin
        #1;
        for (i = 0; i < 4096; i = i + 1) begin
            uram._ram[i] = 0;
            urom._rom[i] = 32'h13;
        end
        if (!$value$plusargs("IMAGE=%s", image)) $fatal(1, "IMAGE missing");
        $readmemh(image, urom._rom);
        repeat (4) @(negedge clk);
        rst = 1;
    end
    always @(posedge clk)
        if (rst) begin
            cycles = cycles + 1;
            if (dq && dready) begin
                if (pending) $fatal(1, "duplicate memory request");
                pending  <= 1;
                owner_pc <= dut.ie_inst_addr_o;
                accepted = accepted + 1;
            end
            if (dv && dr) begin
                pending <= 0;
                responses = responses + 1;
            end
            if (pending && (!dut.ie_valid_o || dut.ie_inst_addr_o !== owner_pc))
                $fatal(1, "owner lost");
            if (pending && !dv &&
                (dut.retire_valid || dut.ex_reg_we_o || dut.ex_csr_we_o || dut.trap_valid))
                $fatal(1, "premature commit");
            if (pw && ps == 4) mmio_writes = mmio_writes + 1;
            if (x26 == 1 && dut.retire_valid) terminal_retires = terminal_retires + 1;
            if (x26 == 1 && terminal_retires >= 2) begin
                if (x27 !== 1)
                    $fatal(1, "software failed pc=%h x3=%h", dut.pc_pc_o, dut.u_regs.regs[3]);
                if (accepted != responses || pending) $fatal(1, "incomplete memory transactions");
                passed = 1;
                $display(
                    "MEMORY_SYSTEM_CPU_PASS cache=%0d cycles=%0d commands=%0d I_hit=%0d I_miss=%0d D_hit=%0d D_miss=%0d MMIO_writes=%0d",
                    CACHE, cycles, memory.commands, memory.ih, memory.im, memory.dh, memory.dm,
                    mmio_writes);
                $finish;
            end
            if (cycles > 200000) $fatal(1, "timeout pc=%h", dut.pc_pc_o);
        end
endmodule
