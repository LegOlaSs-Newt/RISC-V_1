/*
 * 模块说明：early_cpu_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：early_cpu_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module early_cpu_tb #(
    parameter FAST = 1,
    HOST_LAST = 1
);
    reg clk = 0, rst = 0, halt = 0;
    reg [7:0] interrupts = 0;
    always #5 clk = ~clk;
    wire [31:0] ia, idata, da, wd, ddata, x26, x27;
    wire iq, irdy, iv, ie, ir, dq, dw, dready, dv, de, dr, fi;
    wire [3:0] be;
    wire lv, lc, lu, lr, lrv, lh;
    wire [31:0] la, lra, ld;
    wire [31:0] ma, md, qr, qp, pa, pd, hd;
    wire [3:0] ms, ps;
    wire mr, mw, ram_select, pw, hr, hv, he;
    reg hq = 0;
    integer i, cycles = 0, accepted = 0, responses = 0, fast_uses = 0, normal_hits = 0, queries = 0;
    integer phase = 0, terminal = 0, irq_cancels = 0, halt_cancels = 0;
    reg passed = 0, pending = 0, irq_done = 0, halt_done = 0, host_done = 0;
    reg [31:0] owner;
    string image;
    tinyriscv #(
        .WAIT_MEMORY(1),
        .EARLY_D_LOOKUP(FAST)
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
        .data_lookup_valid_o(lv),
        .data_lookup_cancel_o(lc),
        .data_lookup_use_o(lu),
        .data_lookup_addr_o(la),
        .data_lookup_ready_i(lr),
        .data_lookup_result_valid_i(lrv),
        .data_lookup_hit_i(lh),
        .data_lookup_result_addr_i(lra),
        .data_lookup_data_i(ld),
        .rib_pc_addr_o(ia),
        .rib_pc_data_i(idata),
        .fetch_req_valid_o(iq),
        .fetch_req_ready_i(irdy),
        .fetch_rsp_valid_i(iv),
        .fetch_rsp_error_i(ie),
        .fetch_rsp_ready_o(ir),
        .fence_i_o(fi),
        .jtag_reg_addr_i(5'b0),
        .jtag_reg_data_i(32'b0),
        .jtag_reg_we_i(1'b0),
        .jtag_reg_data_o(),
        .prediction_clear_i(1'b0),
        .rib_hold_flag_i(1'b0),
        .jtag_halt_flag_i(halt),
        .jtag_reset_flag_i(1'b0),
        .int_i(interrupts),
        .test_x26_o(x26),
        .test_x27_o(x27)
    );
    memory_system #(
        .CACHE_ENABLE  (1),
        .EARLY_D_LOOKUP(FAST)
    ) memory (
        .clk(clk),
        .rst(rst),
        .fence_i_i(fi),
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
        .d_lookup_valid_i(lv),
        .d_lookup_cancel_i(lc),
        .d_lookup_use_i(lu),
        .d_lookup_addr_i(la),
        .d_lookup_ready_o(lr),
        .d_lookup_result_valid_o(lrv),
        .d_lookup_hit_o(lh),
        .d_lookup_result_addr_o(lra),
        .d_lookup_data_o(ld),
        .h_req_valid_i(hq),
        .h_req_write_i(1'b1),
        .h_req_addr_i(32'h10000000),
        .h_req_wdata_i(32'h11223344),
        .h_req_ready_o(hr),
        .h_rsp_valid_o(hv),
        .h_rsp_error_o(he),
        .h_rsp_data_o(hd),
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
    // Inject an IRQ before a warm load can commit, not after a slow request.
    initial begin
        wait (rst && phase == 1);
        @(negedge clk);
        while (!(FAST ? dut.early_data_match :
                 dut.ie_valid_o && dut.raw_mem_req && !dut.raw_mem_we && !dut.data_started))
        @(negedge clk);
        interrupts = 8'h04;
        wait (dut.trap_valid && dut.trap_cause == 32'h8000000b);
        @(posedge clk);
        @(negedge clk);
        interrupts = 0;
        irq_done   = 1;
        wait (phase == 2);
        @(negedge clk);
        while (!(FAST ? dut.early_data_match :
                 dut.ie_valid_o && dut.raw_mem_req && !dut.raw_mem_we && !dut.data_started))
        @(negedge clk);
        halt = 1;
        repeat (3) begin
            @(posedge clk);
            if (dut.retire_valid || dq || lu) $fatal(1, "halt leaked an effect");
        end
        @(negedge clk);
        halt = 0;
        halt_done = 1;
        wait (phase == 3);
        @(negedge clk);
        while (memory.busy || pending) @(negedge clk);
        memory.last = HOST_LAST;
        hq = 1;
        @(posedge clk);
        while (!hr) @(posedge clk);
        @(negedge clk);
        hq = 0;
        wait (hv);
        if (he) $fatal(1, "host write error");
        @(posedge clk);
        host_done = 1;
    end
    always @(posedge clk)
        if (rst) begin
            cycles = cycles + 1;
            if (lv && lr) begin
                queries = queries + 1;
                if (memory.cv[1] || !(la < 32'h4000 || (la >= 32'h10000000 && la < 32'h10004000)))
                    $fatal(1, "speculative query reached backend/MMIO");
            end
            if (lu) begin
                fast_uses = fast_uses + 1;
                if (dq || dut.memory_wait || !dut.retire_valid || dut.trap_valid || pending)
                    $fatal(1, "fast load duplicated or prematurely committed");
            end
            if (dut.trap_valid && dut.early_data_match) begin
                irq_cancels = irq_cancels + 1;
                if (lu || dut.ex_reg_we_o) $fatal(1, "trap failed to cancel early effect");
            end
            if (halt && dut.early_owner_valid) halt_cancels = halt_cancels + 1;
            if (hq && (lh || lrv)) $fatal(1, "host failed to block early data");
            if (dq && dready) begin
                if (pending) $fatal(1, "duplicate normal request");
                pending <= 1;
                owner   <= dut.ie_inst_addr_o;
                accepted = accepted + 1;
                if (!dw && memory.u_dcache.request_hit) normal_hits = normal_hits + 1;
            end
            if (dv && dr) begin
                pending <= 0;
                responses = responses + 1;
            end
            if (pending && (!dut.ie_valid_o || dut.ie_inst_addr_o !== owner))
                $fatal(1, "normal owner lost");
            if (pending && !dv && (dut.retire_valid || dut.ex_reg_we_o || dut.trap_valid))
                $fatal(1, "normal request committed early");
            if (pw && ps == 4) phase = pd;
            if (x26 == 1 && dut.retire_valid) terminal = terminal + 1;
            if (x26 == 1 && terminal >= 2) begin
                if (x27 !== 1 || !irq_done || !halt_done || !host_done)
                    $fatal(
                        1,
                        "software/supervisor failed pc=%h phase=%0d pass=%h irq/halt/host=%b%b%b irq_count=%h fault_count=%h cause=%h mepc=%h"
                            ,
                        dut.ie_inst_addr_o,
                        phase,
                        x27,
                        irq_done,
                        halt_done,
                        host_done,
                        dut.u_regs.regs[24],
                        dut.u_regs.regs[25],
                        dut.u_csr_reg.mcause,
                        dut.u_csr_reg.mepc
                    );
                if (accepted != responses || pending || memory.dh != normal_hits + fast_uses)
                    $fatal(1, "transaction/hit accounting failed");
                if (FAST && (fast_uses < 10 || irq_cancels < 1))
                    $fatal(1, "early-path coverage absent");
                if (!FAST && (fast_uses || queries)) $fatal(1, "disabled feature active");
                passed = 1;
                $display(
                    "EARLY_CPU_PASS fast=%0d host_last=%0d cycles=%0d queries=%0d fast_uses=%0d normal_requests=%0d dh=%0d irq_cancels=%0d",
                    FAST, HOST_LAST, cycles, queries, fast_uses, accepted, memory.dh, irq_cancels);
                $finish;
            end
            if (cycles > 30000)
                $fatal(1, "timeout pc=%h phase=%0d fast=%0d", dut.ie_inst_addr_o, phase, FAST);
        end
endmodule
