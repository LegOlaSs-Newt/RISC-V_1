/*
 * 模块说明：gpio_console_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：gpio_console_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
`include "mes50hp_config.vh"
module gpio_console_tb;
    reg clk = 0;
    always #(500000000.0 / `MES50HP_CPU_HZ) clk = ~clk;
    localparam BIT_CYCLES = `MES50HP_UART_DIV + 1;
    reg key1_n = 0, key2_n = 1, uart_rx = 1;
    wire uart_tx;
    wire [7:0] led;
    wire [15:0] gpio;
    reg [15:0] drive_en = 0, drive_data = 0;
    reg loopback = 0, fault_inject = 0;
    reg loading = 0;
    integer ack_count = 0;
    integer download = 0, image_bytes, ignored;
    string image, byte_image;
    reg [7:0] firmware[0:16254];
    reg [7:0] payload[0:127];
    string lines[$];
    string line_rx = "";
    integer serial_epoch = 0;
    always @(negedge dut.u_soc.cpu_rst_n) serial_epoch = serial_epoch + 1;
    tinyriscv_mes50hp_top #(
        .POR_CYCLES(8),
        .DEBOUNCE_CYCLES(4)
    ) dut (
        .clk_sys(clk),
        .key1_n(key1_n),
        .key2_n(key2_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .gpio(gpio),
        .led(led)
    );
    genvar g;
    generate
        for (g = 0; g < 16; g = g + 1) begin
            assign gpio[g] = drive_en[g] ? drive_data[g] :
                (fault_inject && dut.u_soc.gpio_ctrl[g*2+:2] == 2'b10 ? 1'b0 : 1'bz);
            if (g < 8) tranif1 loop_wire (gpio[g], gpio[g+8], loopback);
        end
    endgenerate
    initial begin : monitor
        reg [7:0] c;
        integer bit_index;
        integer frame_epoch;
        wait (dut.soc_rst_n === 1);
        wait (uart_tx === 1);
        forever begin
            @(negedge uart_tx);
            // Reset drives TX low too; it is not a UART start bit.
            if (dut.u_soc.cpu_rst_n !== 1) continue;
            frame_epoch = serial_epoch;
            repeat (BIT_CYCLES + BIT_CYCLES / 2) @(posedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                c[bit_index] = uart_tx;
                repeat (BIT_CYCLES) @(posedge clk);
            end
            if (dut.u_soc.cpu_rst_n !== 1 || frame_epoch != serial_epoch) continue;
            if (uart_tx !== 1) $fatal(1, "Console TX stop bit invalid");
            if (loading) begin
                if (c !== 6) $fatal(1, "Console loader ACK invalid %h", c);
                ack_count++;
            end else if (c == 10) begin
                $display("CONSOLE_UART %s", line_rx);
                lines.push_back(line_rx);
                line_rx = "";
            end else if (c != 13) line_rx = {line_rx, c};
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
    task expect_line(input string expected);
        string actual;
        wait (lines.size() > 0);
        actual = lines.pop_front();
        if (actual != expected) $fatal(1, "Console expected [%s], got [%s]", expected, actual);
    endtask
    task send_line(input string s);
        for (integer b = 0; b < s.len(); b = b + 1) send_byte(s[b]);
        send_byte(10);
    endtask
    task command(input string s, input string expected);
        send_line(s);
        expect_line(expected);
    endtask
    task bad_command(input string s);
        reg [31:0] old_ctrl, old_data;
        old_ctrl = dut.u_soc.gpio_ctrl;
        old_data = dut.u_soc.gpio_data;
        command(s, "ERR COMMAND");
        if (dut.u_soc.gpio_ctrl !== old_ctrl || dut.u_soc.gpio_data !== old_data)
            $fatal(1, "Invalid command changed GPIO state");
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
        integer previous;
        crc = 16'hffff;
        for (integer n = 0; n < 128; n = n + 1) begin
            crc = crc ^ payload[n];
            for (integer b = 0; b < 8; b = b + 1)
            crc = crc[0] ? ((crc >> 1) ^ 16'ha001) : (crc >> 1);
        end
        previous = ack_count;
        send_byte(number);
        for (integer n = 0; n < 128; n = n + 1) send_byte(payload[n]);
        send_byte(crc[7:0]);
        send_byte(crc[15:8]);
        wait (ack_count == previous + 1);
        repeat (1000) @(negedge clk);
    endtask
    integer i, p, offset, mismatches;
    string actual;
    initial begin
        if (!$value$plusargs("CONSOLE_MEM=%s", image)) $fatal(1, "CONSOLE_MEM required");
        if (!$value$plusargs("CONSOLE_BYTES=%s", byte_image)) $fatal(1, "CONSOLE_BYTES required");
        if (!$value$plusargs("IMAGE_BYTES=%d", image_bytes)) $fatal(1, "IMAGE_BYTES required");
        ignored = $value$plusargs("DOWNLOAD=%d", download);
        #1;
        if (!download) $readmemh(image, dut.u_soc.u_rom._rom);
        else $readmemh(byte_image, firmware, 0, image_bytes - 1);
        repeat (4) @(negedge clk);
        key1_n = 1;
        wait (dut.soc_rst_n === 1);
        if (download) begin
            press_mode();
            if (led[1] !== 1) $fatal(1, "Download mode not enabled");
            repeat (1000) @(negedge clk);
            lines.delete();
            line_rx = "";
            loading = 1;
            for (i = 0; i < 128; i = i + 1) payload[i] = 0;
            payload[0]  = "c";
            payload[1]  = "o";
            payload[2]  = "n";
            payload[60] = image_bytes >> 24;
            payload[61] = image_bytes >> 16;
            payload[62] = image_bytes >> 8;
            payload[63] = image_bytes;
            send_packet(0);
            for (p = 0; p < image_bytes / 128 + 1; p = p + 1) begin
                for (i = 0; i < 128; i = i + 1) begin
                    offset = p * 128 + i;
                    payload[i] = offset < image_bytes ? firmware[offset] : 0;
                end
                send_packet(p + 1);
            end
            for (i = 0; i < image_bytes; i = i + 1)
            if (((dut.u_soc.u_rom._rom[i/4] >> ((i % 4) * 8)) & 255) !== {24'b0, firmware[i]})
                $fatal(1, "Downloaded console differs byte %0d", i);
            loading = 0;
            press_mode();
        end
        expect_line("RISC-V GPIO CONSOLE V1 115200 8N1");
        expect_line("READY CTRL=00000000");
        if (gpio !== 16'hzzzz || led[3:2] !== 0) $fatal(1, "Console startup must be high-Z");
        command("HELP", "HELP | MODE <hex32> | WRITE <hex16> | READ | SELFTEST");
        command("MODE 55555555", "OK MODE=55555555");
        command("WRITE 8001", "OK WRITE=8001");
        if (gpio !== 16'h8001 || led[3:2] !== 1) $fatal(1, "Console output mismatch");
        command("READ", "OK CTRL=55555555 DATA=8001");
        bad_command("MODE 100000000");
        bad_command("WRITE 10000");
        bad_command("MODE -1");
        bad_command("WRITE 0x");
        bad_command("WRITE ZZZZ");
        bad_command("WRITE FFFF extra");
        bad_command("MODE");
        bad_command("READ 1");
        bad_command("HELP extra");
        bad_command("SELFTEST extra");
        bad_command("help");
        bad_command("");
        for (i = 0; i < 70; i = i + 1) send_byte("A");
        send_byte(10);
        expect_line("ERR LINE");
        send_byte(0);
        send_line("WRITE FFFF");
        expect_line("ERR LINE");
        if (gpio !== 16'h8001 || dut.u_soc.gpio_ctrl !== 32'h55555555)
            $fatal(1, "Bad line mutated GPIO");
        // CRLF is a single command, and parsing recovers after bad lines.
        send_byte("R");
        send_byte("E");
        send_byte("A");
        send_byte("D");
        send_byte(13);
        send_byte(10);
        expect_line("OK CTRL=55555555 DATA=8001");
        command("MODE 00000000", "OK MODE=00000000");
        drive_en   = 16'hffff;
        drive_data = 16'ha55a;
        command("MODE AAAAAAAA", "OK MODE=AAAAAAAA");
        command("READ", "OK CTRL=AAAAAAAA DATA=A55A");
        if (led[3:2] !== 2) $fatal(1, "Console input LED mismatch");
        drive_data = 16'h5aa5;
        command("READ", "OK CTRL=AAAAAAAA DATA=5AA5");
        command("MODE FFFFFFFF", "OK MODE=FFFFFFFF");
        drive_en = 0;
        repeat (8) @(negedge clk);
        if (gpio !== 16'hzzzz || led[3:2] !== 0) $fatal(1, "Reserved mode drives pad/LED");
        command("MODE 0x00000000", "OK MODE=00000000");
        loopback = 1;
        command("SELFTEST", "OK SELFTEST 40/40 CTRL=00000000");
        if (dut.u_soc.gpio_ctrl !== 0 || gpio !== 16'hzzzz)
            $fatal(1, "SELFTEST did not release outputs");
        loopback = 0;
        fault_inject = 1;
        send_line("SELFTEST");
        mismatches = 0;
        forever begin
            wait (lines.size() > 0);
            actual = lines.pop_front();
            if (actual == "ERR SELFTEST CTRL=00000000") break;
            if (actual.len() < 8 || actual.substr(0, 7) != "MISMATCH")
                $fatal(1, "Bad fault response %s", actual);
            mismatches++;
        end
        if (mismatches != 38 || dut.u_soc.gpio_ctrl !== 0)
            $fatal(1, "Fault injection/release not detected: %0d", mismatches);
        fault_inject = 0;
        command("READ", "OK CTRL=00000000 DATA=7F00");
        $display(
            "GPIO_CONSOLE_PASS download=%0d ACKs=%0d: real UART command/error/input/loopback/fault recovery",
            download, ack_count);
        $finish;
    end
    initial begin
        #2000000000;
        $fatal(1, "Console timeout");
    end
endmodule
