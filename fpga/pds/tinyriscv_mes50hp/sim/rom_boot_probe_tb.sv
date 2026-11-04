/*
 * 模块说明：rom_boot_probe_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：rom_boot_probe_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
`include "mes50hp_config.vh"
module rom_boot_probe_tb;
    reg clk = 0;
    always #(500000000.0 / `MES50HP_CPU_HZ) clk = ~clk;
    localparam BIT_CYCLES = `MES50HP_UART_DIV + 1;
    reg key1_n = 0, key2_n = 1, uart_rx = 1;
    wire uart_tx;
    wire [7:0] led;
    wire [15:0] gpio;
    reg loading = 0;
    integer ack_count = 0, image_bytes, inject_mismatch = 0, ignored;
    reg [7:0] firmware[0:255], payload[0:127];
    reg [31:0] original_rom[0:4095];
    string byte_image, boot_image, expected = "", received = "", word_text;
    tinyriscv_mes50hp_top #(
        .POR_CYCLES(8),
        .DEBOUNCE_CYCLES(4)
    ) dut (
        .clk_sys(clk),
        .key1_n(key1_n),
        .key2_n(key2_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .led(led),
        .gpio(gpio)
    );
    initial begin : monitor
        reg [7:0] c;
        integer b;
        wait (dut.soc_rst_n === 1);
        wait (uart_tx === 1);
        forever begin
            @(negedge uart_tx);
            if (dut.soc_rst_n !== 1) continue;
            repeat (BIT_CYCLES + BIT_CYCLES / 2) @(posedge clk);
            for (b = 0; b < 8; b = b + 1) begin
                c[b] = uart_tx;
                repeat (BIT_CYCLES) @(posedge clk);
            end
            if (dut.soc_rst_n !== 1) continue;
            if (uart_tx !== 1) $fatal(1, "ROM probe UART stop bit invalid");
            if (loading) begin
                if (c !== 6) $fatal(1, "ROM probe ACK invalid");
                ack_count++;
            end else begin
                received = {received, c};
                if (c == "!") begin
                    if (received != expected)
                        $fatal(1, "ROM_PROBE_FAIL: UART dump differs from preserved V2 ROM");
                    if (dut.u_soc.gpio_ctrl !== 0 || gpio !== 16'hzzzz)
                        $fatal(1, "ROM probe drove GPIO");
                    $display(
                        "ROM_PROBE_PASS: 119 words matched over real UART; 3 ACKs; only first 256 bytes overwritten; GPIO high-Z"
                            );
                    $finish;
                end
                if (received.len() > expected.len()) $fatal(1, "ROM probe excess UART data");
            end
        end
    end
    task send_byte(input [7:0] c);
        @(negedge clk);
        uart_rx = 0;
        repeat (BIT_CYCLES) @(negedge clk);
        for (integer b = 0; b < 8; b = b + 1) begin
            uart_rx = c[b];
            repeat (BIT_CYCLES) @(negedge clk);
        end
        uart_rx = 1;
        repeat (BIT_CYCLES + 6) @(negedge clk);
    endtask
    task press_mode;
        @(negedge clk);
        key2_n = 0;
        repeat (12) @(negedge clk);
        key2_n = 1;
        repeat (50) @(negedge clk);
    endtask
    task send_packet(input [7:0] number);
        reg [15:0] crc;
        integer before_ack;
        crc = 16'hffff;
        for (integer n = 0; n < 128; n = n + 1) begin
            crc = crc ^ payload[n];
            for (integer b = 0; b < 8; b = b + 1)
            crc = crc[0] ? ((crc >> 1) ^ 16'ha001) : (crc >> 1);
        end
        before_ack = ack_count;
        send_byte(number);
        for (integer n = 0; n < 128; n = n + 1) send_byte(payload[n]);
        send_byte(crc[7:0]);
        send_byte(crc[15:8]);
        wait (ack_count == before_ack + 1);
        repeat (1000) @(negedge clk);
    endtask
    integer i, p, offset;
    initial begin
        if (!$value$plusargs("PROBE_BYTES=%s", byte_image)) $fatal(1, "PROBE_BYTES required");
        if (!$value$plusargs("BOOT_IMAGE=%s", boot_image)) $fatal(1, "BOOT_IMAGE required");
        if (!$value$plusargs("IMAGE_BYTES=%d", image_bytes)) $fatal(1, "IMAGE_BYTES required");
        ignored = $value$plusargs("INJECT_MISMATCH=%d", inject_mismatch);
        if (image_bytes <= 0 || image_bytes >= 256) $fatal(1, "Invalid probe size");
        $readmemh(boot_image, original_rom);
        $readmemh(byte_image, firmware, 0, image_bytes - 1);
        for (i = 64; i < 183; i = i + 1) begin
            word_text =
                $sformatf("%08h", original_rom[i] ^ ((inject_mismatch && i == 64) ? 32'h1 : 32'h0));
            expected = {expected, word_text.toupper(), 8'h0a};
        end
        expected = {expected, "!"};
        #1;
        for (i = 0; i < 4096; i = i + 1)
        if (dut.u_soc.u_rom._rom[i] !== original_rom[i]) $fatal(1, "Probe TB boot image mismatch");
        repeat (4) @(negedge clk);
        key1_n = 1;
        wait (dut.soc_rst_n === 1);
        press_mode();
        if (led[1] !== 1) $fatal(1, "Probe download mode absent");
        repeat (1000) @(negedge clk);
        loading  = 1;
        received = "";
        for (i = 0; i < 128; i = i + 1) payload[i] = 0;
        payload[0]  = "p";
        payload[63] = image_bytes;
        send_packet(0);
        for (p = 0; p < image_bytes / 128 + 1; p = p + 1) begin
            for (i = 0; i < 128; i = i + 1) begin
                offset = p * 128 + i;
                payload[i] = offset < image_bytes ? firmware[offset] : 0;
            end
            send_packet(p + 1);
        end
        if (ack_count != 3) $fatal(1, "Expected exactly 3 probe ACKs");
        for (i = 64; i < 183; i = i + 1)
        if (dut.u_soc.u_rom._rom[i] !== original_rom[i]) $fatal(1, "Loader overwrote observed ROM");
        loading = 0;
        press_mode();
    end
    initial begin
        #500000000;
        $fatal(1, "ROM probe timeout");
    end
endmodule
