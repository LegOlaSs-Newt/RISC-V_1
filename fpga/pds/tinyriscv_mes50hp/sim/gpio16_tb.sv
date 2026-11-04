/*
 * 模块说明：gpio16_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：gpio16_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module gpio16_tb;
    reg clk = 0;
    always #18.5185 clk = ~clk;
    reg reset_n = 0;
    wire [15:0] gpio;
    reg [15:0] drive_en = 0, drive_data = 0;
    wire [7:0] led;
    wire uart_tx;
    reg [31:0] addr = 0, data = 0;
    reg we = 0;
    tinyriscv_mes50hp_top #(
        .POR_CYCLES(2),
        .DEBOUNCE_CYCLES(4)
    ) dut (
        .clk_sys(clk),
        .key1_n(reset_n),
        .key2_n(1'b1),
        .uart_rx(1'b1),
        .uart_tx(uart_tx),
        .gpio(gpio),
        .led(led)
    );
    genvar k;
    generate
        for (k = 0; k < 16; k = k + 1) begin
            assign gpio[k] = drive_en[k] ? drive_data[k] : 1'bz;
        end
    endgenerate
    task tick;
        @(posedge clk);
        #1;
    endtask
    task write_reg(input [31:0] a, input [31:0] d);
        @(negedge clk);
        addr = a;
        data = d;
        we   = 1;
        tick();
        @(negedge clk);
        we = 0;
    endtask
    task check(input bit condition, input string message);
        if (!condition) $fatal(1, "GPIO16_FAIL: %s", message);
    endtask
    task sample (input [31:0] a, input [31:0] expected);
        addr = a;
        #1;
        check(dut.u_soc.s4_data_i === expected, $sformatf(
              "read addr=%h got=%h expected=%h", a, dut.u_soc.s4_data_i, expected));
    endtask
    integer pin, mode;
    reg [31:0] ctrl;
    initial begin
        // Test the real SoC pad generation and explicit board LED connection.
        // Isolate only CPU bus activity; GPIO itself is never forced.
        force dut.u_soc.m0_req_i = 0;
        force dut.u_soc.m1_data_o = 32'h00000013;
        force dut.u_soc.s4_we_o = we;
        force dut.u_soc.s4_addr_o = addr;
        force dut.u_soc.s4_data_o = data;
        repeat (4) tick();
        reset_n = 1;
        wait (dut.soc_rst_n === 1);
        tick();
        check(gpio === 16'hzzzz, "reset all high impedance");
        check(led[3:2] === 0, "reset LED off");
        sample (0, 0);
        sample (4, 0);
        write_reg(4, 32'hdead8001);
        sample (4, 32'hdead8001);
        write_reg(0, 32'h55555555);
        check(gpio === 16'h8001, "all output including bit15");
        check(led[3:2] === 1, "output LED mirrors");
        write_reg(4, 32'hbeef7ffe);
        check(gpio === 16'h7ffe, "output complement");
        check(led[3:2] === 2, "output LED complement");
        write_reg(0, 0);
        check(gpio === 16'hzzzz && led[3:2] === 0, "release all outputs");
        drive_en   = 16'hffff;
        drive_data = 0;
        write_reg(4, 32'hcafe0000);
        write_reg(0, 32'haaaaaaaa);
        repeat (4) tick();
        sample (4, 32'hcafe0000);
        @(negedge clk);
        drive_data = 16'hffff;
        tick();
        sample (4, 32'hcafe0000);
        tick();
        sample (4, 32'hcafe0000);
        tick();
        sample (4, 32'hcafeffff);
        check(led[3:2] === 3, "input LED uses sampled DATA");
        // MMIO write wins even when every pin is configured as input.
        write_reg(4, 32'h12340000);
        sample (4, 32'h12340000);
        tick();
        sample (4, 32'h1234ffff);
        @(negedge clk);
        drive_data = 16'h5aa5;
        repeat (3) tick();
        sample (4, 32'h12345aa5);
        // Every pin independently exercises all four modes, then mixed mode.
        drive_en = 0;
        write_reg(0, 0);
        for (pin = 0; pin < 16; pin = pin + 1) begin
            for (mode = 0; mode < 4; mode = mode + 1) begin
                drive_en   = mode == 2 ? (16'h1 << pin) : 0;
                drive_data = 16'hffff;
                write_reg(4, 32'hffffffff);
                write_reg(0, mode << (pin * 2));
                repeat (4) tick();
                if (mode == 1 || mode == 2) check(gpio[pin] === 1'b1, "per-pin output/input");
                else check(gpio[pin] === 1'bz, "per-pin high impedance/reserved");
                if (pin < 2) check(led[pin+2] === (mode == 1 || mode == 2), "per-pin LED mode");
                write_reg(0, 0);
            end
        end
        ctrl = 0;
        drive_en = 0;
        drive_data = 16'hffff;
        for (pin = 0; pin < 16; pin = pin + 1) begin
            ctrl = ctrl | ((pin % 4) << (pin * 2));
            if (pin % 4 == 2) drive_en[pin] = 1;
        end
        write_reg(4, 32'h1357ffff);
        write_reg(0, ctrl);
        repeat (4) tick();
        sample (0, ctrl);
        sample (4, 32'h1357ffff);
        for (pin = 0; pin < 16; pin = pin + 1)
        check(gpio[pin] === ((pin % 4 == 1 || pin % 4 == 2) ? 1'b1 : 1'bz), "mixed directions");
        sample (8, 0);
        // Reset must release driven pins immediately and clear registers.
        @(negedge clk);
        drive_en = 0;
        reset_n  = 0;
        #1;
        check(gpio === 16'hzzzz && led[3:2] === 0, "reset release and LED off");
        repeat (4) tick();
        sample (0, 0);
        sample (4, 0);
        $display(
            "GPIO16_PASS: 16 pins x 4 modes, bit15, mixed, reset, write priority, 3-edge input latency, board LED mirrors"
                );
        $finish;
    end
    initial begin
        #500000;
        $fatal(1, "GPIO16 timeout");
    end
endmodule
