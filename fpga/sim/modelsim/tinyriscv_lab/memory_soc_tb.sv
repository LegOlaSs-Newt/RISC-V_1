/*
 * 模块说明：memory_soc_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：memory_soc_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
`ifndef LAB_CACHE_ENABLE
`define LAB_CACHE_ENABLE 1
`endif
`ifndef LAB_CLOCK_HZ
`define LAB_CLOCK_HZ 27000000
`endif
module memory_soc_tb #(
    parameter integer CACHE = `LAB_CACHE_ENABLE
);
    reg clk = 0, rst = 0, download = 0;
    always #(500000000.0 / `LAB_CLOCK_HZ) clk = ~clk;
    wire active;
    wire [15:0] gpio;
    reg dmi_request = 0, dmi_ack = 0;
    reg [39:0] dmi_data = 0;
    integer i, cycles = 0, stores = 0, before_store, host_requests = 0, host_responses = 0;
    reg passed = 0;
    string image;
    tinyriscv_soc_top #(
        .MEMORY_SYSTEM(1),
        .CACHE_ENABLE (CACHE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .over(),
        .succ(),
        .halted_ind(),
        .uart_debug_pin(download),
        .download_active_o(active),
        .uart_tx_pin(),
        .uart_rx_pin(1'b1),
        .gpio(gpio),
        .gpio_led_o(),
        .jtag_TCK(1'b0),
        .jtag_TMS(1'b1),
        .jtag_TDI(1'b0),
        .jtag_TDO(),
        .spi_miso(1'b0),
        .spi_mosi(),
        .spi_ss(),
        .spi_clk()
    );
    task automatic dmi(input [1:0] op, input [5:0] addr, input [31:0] data, input bit check_value,
                       input [31:0] expected);
        reg [39:0] saved;
        begin
            @(negedge clk);
            dmi_data = {addr, data, op};
            dmi_request = 1;
            wait (dut.u_jtag_top.dm_ack_o);
            @(negedge clk);
            dmi_request = 0;
            wait (!dut.u_jtag_top.dm_ack_o);
            wait (dut.u_jtag_top.dm_resp_valid_o);
            saved = dut.u_jtag_top.dm_resp_data_o;
            if (saved[39:34] !== addr || saved[1:0] !== 0 ||
                (check_value && saved[33:2] !== expected))
                $fatal(
                    1, "SoC DMI mismatch addr=%h got=%h expected=%h", addr, saved[33:2], expected
                );
            @(negedge clk);
            dmi_ack = 1;
            wait (!dut.u_jtag_top.dm_resp_valid_o);
            @(negedge clk);
            dmi_ack = 0;
        end
    endtask
    always @(posedge clk)
        if (rst) begin
            cycles = cycles + 1;
            if (dut.s1_we_o && dut.s1_addr_o == 0) stores = stores + 1;
            if (dut.host_request && dut.host_grant && dut.host_ready)
                host_requests = host_requests + 1;
            if (dut.host_valid && dut.host_response_ready) host_responses = host_responses + 1;
            if (active && (dut.u_tinyriscv.retire_valid || dut.m0_req_i || dut.m1_req_i))
                $fatal(1, "CPU accessed/retired in download mode");
            if (cycles > 30000)
                $fatal(1, "SoC coordination timeout pc=%h", dut.u_tinyriscv.pc_pc_o);
        end
    initial begin
        // Exercise the real SoC DM/SBA path while keeping the board's unused
        // CPU software-JTAG pins unchanged. This is DMI-level stimulation.
        force dut.u_jtag_top.dtm_req_valid_o = dmi_request;
        force dut.u_jtag_top.dtm_req_data_o = dmi_data;
        force dut.u_jtag_top.dtm_ack_o = dmi_ack;
        #1;
        for (i = 0; i < 4096; i = i + 1) begin
            dut.u_ram._ram[i] = 0;
            dut.u_rom._rom[i] = 32'h13;
        end
        if (!$value$plusargs("IMAGE=%s", image)) $fatal(1, "IMAGE missing");
        $readmemh(image, dut.u_rom._rom);
        repeat (4) @(negedge clk);
        rst = 1;
        wait (dut.u_tinyriscv.data_accepted && dut.u_tinyriscv.raw_mem_we &&
              dut.m0_addr_i == 32'h10000000);
        @(negedge clk);
        before_store = stores;
        download = 1;
        wait (active);
        wait (!dut.restart_cpu);
        @(negedge clk);
        if (stores != before_store + 1)
            $fatal(1, "mode switch lost or repeated accepted CPU store");
        if (dut.cached_memory.u_memory_system.u_icache.valid0 !== 0 ||
            dut.cached_memory.u_memory_system.u_dcache.valid0 !== 0)
            $fatal(1, "mode entry did not invalidate caches");
        wait (dut.cached_memory.u_uart_debug_wait.accepted);
        @(negedge clk);
        download = 0;
        wait (!active);
        wait (dut.cpu_rst_n);
        @(negedge clk);
        if (host_requests != host_responses) $fatal(1, "mode exit dropped a loader transaction");
        wait (dut.u_tinyriscv.div_pending && dut.u_tinyriscv.div_busy_o);
        dmi(2, 6'h10, 32'h80000001, 0, 0);
        wait (dut.actual_halted);
        dmi(1, 6'h11, 0, 1, 32'h00430382);
        dmi(2, 6'h38, 32'h00040000, 0, 0);
        dmi(2, 6'h39, 32'h1000000c, 0, 0);
        dmi(2, 6'h3c, 32'h12345678, 0, 0);
        dmi(1, 6'h3c, 0, 1, 32'h12345678);
        dmi(2, 6'h39, 32'h10000008, 0, 0);
        dmi(2, 6'h3c, 1, 0, 0);
        if (dut.cached_memory.u_memory_system.u_dcache.valid0 !== 0 ||
            dut.cached_memory.u_memory_system.u_dcache.valid1 !== 0)
            $fatal(1, "debug writes left stale D-cache lines");
        if (dut.u_tinyriscv.u_branch_predictor.valid !== 0)
            $fatal(1, "debug writes left stale prediction state");
        dmi(2, 6'h10, 32'h40000001, 0, 0);
        wait (dut.test_x26 == 1);
        repeat (30) @(negedge clk);
        if (dut.test_x27 !== 1 || host_requests != host_responses)
            $fatal(1, "halt/resume/coherence software failed");
        passed = 1;
        $display(
            "MEMORY_SOC_PASS cache=%0d cycles=%0d physical_counter_writes=%0d host_requests=%0d host_responses=%0d",
            CACHE, cycles, stores, host_requests, host_responses);
        $finish;
    end
endmodule
