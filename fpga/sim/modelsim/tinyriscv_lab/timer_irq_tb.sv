/*
 * 模块说明：timer_irq_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：timer_irq_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
// MSIP is independent of timer expiration and its pending latch.
module timer_irq_tb;
    reg clk = 0, rst = 0, we = 0;
    reg [31:0] addr = 0, data = 0;
    wire [31:0] read_data;
    wire timer_irq, software_irq;
    reg passed = 0;
    always #5 clk = ~clk;
    timer dut (
        .clk(clk),
        .rst(rst),
        .data_i(data),
        .addr_i(addr),
        .we_i(we),
        .data_o(read_data),
        .int_sig_o(timer_irq),
        .software_int_o(software_irq)
    );
    task write_reg(input [31:0] a, input [31:0] d);
        @(negedge clk);
        we   = 1;
        addr = a;
        data = d;
        @(negedge clk);
        we = 0;
    endtask
    initial begin
        repeat (2) @(negedge clk);
        rst = 1;
        write_reg(8, 3);
        write_reg(0, 3);
        wait (dut.timer_count == 3);
        @(negedge clk);
        we   = 1;
        addr = 12;
        data = 32'hffffffff;
        @(negedge clk);
        we = 0;
        #1;
        if (!timer_irq || !software_irq || read_data !== 1)
            $fatal(
                1,
                "lost timer expiration on simultaneous MSIP write timer=%b msip=%b read=%h",
                timer_irq,
                software_irq,
                read_data
            );
        write_reg(0, 4);
        #1;
        if (timer_irq || !software_irq) $fatal(1, "timer clear changed software IRQ");
        write_reg(12, 0);
        #1;
        if (software_irq) $fatal(1, "software pending did not clear");
        // An ignored write to COUNT must not erase an independent expiry.
        write_reg(0, 3);
        wait (dut.timer_count == 3);
        @(negedge clk);
        we   = 1;
        addr = 4;
        data = 32'hffffffff;
        @(negedge clk);
        we = 0;
        #1;
        if (!timer_irq || software_irq) $fatal(1, "COUNT write suppressed expiry");
        write_reg(0, 4);
        // Explicit CTRL write still has the inherited priority over expiry.
        write_reg(0, 3);
        wait (dut.timer_count == 3);
        @(negedge clk);
        we   = 1;
        addr = 0;
        data = 2;
        @(negedge clk);
        we = 0;
        #1;
        if (timer_irq) $fatal(1, "CTRL priority changed");
        passed = 1;
        $display("TIMER_IRQ_PASS");
        $finish;
    end
    initial begin
        #10000;
        $fatal(1, "timer unit timeout");
    end
endmodule

