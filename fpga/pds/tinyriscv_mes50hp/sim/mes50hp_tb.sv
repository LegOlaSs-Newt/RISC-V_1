/*
 * 模块说明：mes50hp_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：mes50hp_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
`include "mes50hp_config.vh"
module mes50hp_tb;
    reg clk = 0;
    always #(500000000.0 / `MES50HP_CPU_HZ) clk = ~clk;
    localparam BIT_CYCLES = `MES50HP_UART_DIV + 1;
    reg key1_n = 0;
    reg key2_n = 1;
    wire uart_tx;
    wire [7:0] led;
    tinyriscv_mes50hp_top #(
        .POR_CYCLES(8),
        .DEBOUNCE_CYCLES(4)
    ) dut (
        .clk_sys(clk),
        .key1_n(key1_n),
        .key2_n(key2_n),
        .uart_rx(1'b1),
        .uart_tx(uart_tx),
        .led(led)
    );
    string received = "";
    string expected;
    reg [7:0] character;
    integer bit_index;
    initial begin
        wait (dut.soc_rst_n === 1'b1);
        wait (uart_tx === 1'b1);
        forever begin
            @(negedge uart_tx);
            repeat (BIT_CYCLES + BIT_CYCLES / 2) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                character[bit_index] = uart_tx;
                repeat (BIT_CYCLES) @(posedge clk);
            end
            if (uart_tx !== 1'b1) $fatal(1, "UART stop bit is invalid");
            received = {received, character};
            if (received.len() > expected.len()) $fatal(1, "Unexpected extra UART data");
        end
    end
    task press_mode;
        begin
            @(negedge clk);
            key2_n = 0;
            repeat (12) @(negedge clk);
            key2_n = 1;
            repeat (50) @(negedge clk);
        end
    endtask
    initial begin
        expected = $sformatf(
            "TinyRISC-V UART DEMO V2%c%cfactorial(6)=720 PASS%c%cLED3/LED4 alternate every 250 ms%c%c"
                ,
            13,
            10,
            13,
            10,
            13,
            10
        );
        repeat (4) @(negedge clk);
        key1_n = 1;
        wait (received.len() == expected.len());
        repeat (500) @(negedge clk);
        if (received != expected) $fatal(1, "UART mismatch: %s", received);
        if (led[3:2] !== 2'b01) $fatal(1, "GPIO output mismatch");
        if (led[5:4] !== 2'b11) $fatal(1, "CPU completion flags mismatch");
        $display("UART_AND_CPU_PASS: %s", received);
        press_mode();
        if (led[1] !== 1'b1) $fatal(1, "Cannot enter UART download mode");
        if (dut.u_soc.m3_req_i !== 1'b1) $fatal(1, "UART loader does not own the bus");
        press_mode();
        if (led[1] !== 1'b0) $fatal(1, "Cannot exit UART download mode");
        $display("MODE_SWITCH_PASS: enter/exit and CPU restart");
        $display("MES50HP_SIM_PASS");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1, "Board simulation timed out; UART=%s", received);
    end
endmodule
