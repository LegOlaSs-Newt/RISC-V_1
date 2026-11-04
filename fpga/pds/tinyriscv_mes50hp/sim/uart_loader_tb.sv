/*
 * 模块说明：uart_loader_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：uart_loader_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
`include "mes50hp_config.vh"
module uart_loader_tb;
    reg clk = 0;
    always #(500000000.0 / `MES50HP_CPU_HZ) clk = ~clk;
    localparam BIT_CYCLES = `MES50HP_UART_DIV + 1;
    reg key1_n = 0, key2_n = 1, uart_rx = 1;
    wire uart_tx;
    wire [7:0] led;
    tinyriscv_mes50hp_top #(
        .POR_CYCLES(8),
        .DEBOUNCE_CYCLES(4)
    ) dut (
        .clk_sys(clk),
        .key1_n(key1_n),
        .key2_n(key2_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led)
    );
    reg [7:0] payload[0:127];
    reg [31:0] program_word[0:7];
    reg monitor_ack = 0;
    integer ack_count = 0;
    reg [7:0] response;
    integer i, b;
    initial
        forever begin
            @(negedge uart_tx);
            if (monitor_ack) begin
                repeat (BIT_CYCLES + BIT_CYCLES / 2) @(posedge clk);
                for (b = 0; b < 8; b = b + 1) begin
                    response[b] = uart_tx;
                    repeat (BIT_CYCLES) @(posedge clk);
                end
                if (response !== 8'h06 || uart_tx !== 1'b1)
                    $fatal(1, "Invalid UART download ACK: %h", response);
                ack_count = ack_count + 1;
            end
        end
    task send_byte(input [7:0] value);
        integer n;
        begin
            @(negedge clk);
            uart_rx = 0;
            repeat (BIT_CYCLES) @(negedge clk);
            for (n = 0; n < 8; n = n + 1) begin
                uart_rx = value[n];
                repeat (BIT_CYCLES) @(negedge clk);
            end
            uart_rx = 1;
            repeat (BIT_CYCLES + 6) @(negedge clk);
        end
    endtask
    task send_packet(input [7:0] number);
        reg [15:0] crc;
        integer n, k;
        begin
            crc = 16'hffff;
            for (n = 0; n < 128; n = n + 1) begin
                crc = crc ^ payload[n];
                for (k = 0; k < 8; k = k + 1)
                if (crc[0]) crc = (crc >> 1) ^ 16'ha001;
                else crc = crc >> 1;
            end
            send_byte(number);
            for (n = 0; n < 128; n = n + 1) send_byte(payload[n]);
            send_byte(crc[7:0]);
            send_byte(crc[15:8]);
        end
    endtask
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
        repeat (4) @(negedge clk);
        key1_n = 1;
        wait (dut.soc_rst_n === 1'b1);
        press_mode();
        if (led[1] !== 1'b1) $fatal(1, "Download mode not enabled");
        repeat (1000) @(negedge clk);
        monitor_ack = 1;
        for (i = 0; i < 128; i = i + 1) payload[i] = 0;
        payload[0]  = "g";
        payload[1]  = "p";
        payload[2]  = "i";
        payload[3]  = "o";
        payload[63] = 32;
        send_packet(0);
        wait (ack_count == 1);
        repeat (1000) @(negedge clk);
        program_word[0] = 32'h400002b7;  // lui t0, 0x40000
        program_word[1] = 32'h00500313;  // addi t1, x0, 5
        program_word[2] = 32'h0062a023;  // sw t1, 0(t0): output mode
        program_word[3] = 32'h00200313;  // addi t1, x0, 2
        program_word[4] = 32'h0062a223;  // sw t1, 4(t0): LED4 on
        program_word[5] = 32'h00100d13;  // completion
        program_word[6] = 32'h00100d93;  // success
        program_word[7] = 32'h0000006f;  // loop
        for (i = 0; i < 128; i = i + 1) payload[i] = 0;
        for (i = 0; i < 32; i = i + 1) payload[i] = program_word[i/4] >> ((i % 4) * 8);
        send_packet(1);
        wait (ack_count == 2);
        repeat (1000) @(negedge clk);
        for (i = 0; i < 8; i = i + 1)
        if (dut.u_soc.u_rom._rom[i] !== program_word[i])
            $fatal(1, "Downloaded word %0d differs: %h", i, dut.u_soc.u_rom._rom[i]);
        monitor_ack = 0;
        press_mode();
        repeat (500) @(negedge clk);
        if (led[3:2] !== 2'b10 || led[5:4] !== 2'b11)
            $fatal(1, "Downloaded program did not execute: LED=%h", led);
        $display(
            "UART_LOADER_PASS: header + payload CRC ACK; 8 ROM words verified; new GPIO program executed"
                );
        $finish;
    end
    initial begin
        #80000000;
        $fatal(1, "UART loader timeout: ACK count=%0d", ack_count);
    end
endmodule
