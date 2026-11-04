/*
 * 模块说明：cache_probe_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：cache_probe_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module cache_probe_tb;
    parameter CACHE = 1;
    reg clk = 0, rst = 0;
    always #18.5185 clk = ~clk;
    wire tx;
    wire [15:0] gpio;
    reg passed = 0, uart_complete = 0;
    string image, uart_path, line;
    integer fd, ignored, i, cycles = 0, work_lines = 0, stats_lines = 0;
    tinyriscv_soc_top #(
        .MEMORY_SYSTEM(1),
        .CACHE_ENABLE (CACHE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .uart_debug_pin(1'b0),
        .uart_rx_pin(1'b1),
        .uart_tx_pin(tx),
        .gpio(gpio),
        .jtag_TCK(1'b0),
        .jtag_TMS(1'b1),
        .jtag_TDI(1'b0),
        .jtag_TDO(),
        .spi_miso(1'b0),
        .spi_mosi(),
        .spi_ss(),
        .spi_clk(),
        .over(),
        .succ(),
        .halted_ind()
    );
    initial begin
        ignored = $value$plusargs("IMAGE=%s", image);
        ignored = $value$plusargs("UART_LOG=%s", uart_path);
        fd = $fopen(uart_path, "wb");
        if (fd == 0) $fatal(1, "Cannot open UART log");
        #1;
        $readmemh(image, dut.u_rom._rom);
        repeat (4) @(negedge clk);
        rst = 1;
    end
    always @(posedge clk)
        if (rst) begin
            cycles = cycles + 1;
            if (cycles > 12000000) $fatal(1, "Cache probe timeout");
            if (dut.u_tinyriscv.trap_valid)
                $fatal(
                    1,
                    "Cache probe unexpected trap pc=%h cause=%h",
                    dut.u_tinyriscv.ie_inst_addr_o,
                    dut.u_tinyriscv.trap_cause
                );
            if (dut.u_tinyriscv.test_x26_o == 1 && uart_complete) begin
                if (dut.u_tinyriscv.test_x27_o !== 1 || work_lines != 4 || stats_lines != 15)
                    $fatal(1, "Cache probe result or UART record incomplete");
                passed = 1;
                $fclose(fd);
                $display("CACHE_PROBE_PASS cache=%0d cycles=%0d", CACHE, cycles);
                $finish;
            end
        end
    initial begin : uart_monitor
        reg [7:0] byte_value;
        integer bit_number, bit_cycles;
        wait (rst);
        wait (tx === 1'b1);
        forever begin
            @(negedge tx);
            bit_cycles = dut.uart_0.uart_baud + 1;
            repeat (bit_cycles + bit_cycles / 2) @(posedge clk);
            for (bit_number = 0; bit_number < 8; bit_number = bit_number + 1) begin
                byte_value[bit_number] = tx;
                repeat (bit_cycles) @(posedge clk);
            end
            if (tx !== 1'b1) $fatal(1, "UART stop bit error");
            $fwrite(fd, "%c", byte_value);
            if (byte_value == 10) begin
                if (line == "V3_CACHE_PROBE_PASS") uart_complete = 1;
                if (line.len() >= 5 && line.substr(0, 4) == "WORK ") work_lines = work_lines + 1;
                if (line.len() >= 5 && line.substr(0, 4) == "STAT ") stats_lines = stats_lines + 1;
                $display("PROBE_UART %s", line);
                line = "";
                $fflush(fd);
            end else if (byte_value != 13) line = {line, byte_value};
        end
    end
endmodule
