/*
 * 模块说明：tinyriscv_lab_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：tinyriscv_lab_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
`ifndef LAB_CLOCK_HZ
`define LAB_CLOCK_HZ 27000000
`endif

module tinyriscv_lab_tb #(
    parameter integer CLOCK_HZ = `LAB_CLOCK_HZ,
    parameter integer DEFAULT_MAX_CYCLES = 250000,
    parameter DEFAULT_IMAGE = "",
    parameter DEFAULT_MODE = "protocol"
);
    reg clk = 0, rst = 0;
    always #(500000000.0 / CLOCK_HZ) clk = ~clk;
    string image_path;
    string mode = DEFAULT_MODE;
    string received = "";
    string expected = "";
    string uart_log_path;
    string uart_line = "";
    integer uart_log_fd = 0;
    bit coremark_crc_reported = 0;
    reg uart_rx = 1;
    wire uart_tx, spi_mosi, spi_miso, spi_ss, spi_clk;
`ifdef LAB_PORT
    wire [15:0] gpio_pins;
`else
    wire [1:0] gpio_pins;
`endif
    reg gpio_drive = 0;
    assign gpio_pins[1] = (mode == "gpio") ? gpio_drive : 1'bz;
    assign spi_miso = (mode == "spi") ? spi_mosi : 1'b0;
    tinyriscv_soc_top dut (
        .clk(clk),
        .rst(rst),
        .uart_debug_pin(1'b0),
        .uart_rx_pin(uart_rx),
        .uart_tx_pin(uart_tx),
        .gpio(gpio_pins),
        .jtag_TCK(1'b0),
        .jtag_TMS(1'b1),
        .jtag_TDI(1'b0),
        .jtag_TDO(),
        .spi_miso(spi_miso),
        .spi_mosi(spi_mosi),
        .spi_ss(spi_ss),
        .spi_clk(spi_clk),
        .over(),
        .succ(),
        .halted_ind()
    );

    wire [31:0] pc = dut.u_tinyriscv.pc_pc_o;
    wire [31:0] fetch_inst = dut.m1_data_o;
    wire [31:0] id_pc = dut.u_tinyriscv.if_inst_addr_o;
    wire [31:0] id_inst = dut.u_tinyriscv.if_inst_o;
    wire [31:0] ex_pc = dut.u_tinyriscv.ie_inst_addr_o;
    wire [31:0] ex_inst = dut.u_tinyriscv.ie_inst_o;
    wire wb_we = dut.u_tinyriscv.ex_reg_we_o;
    wire [4:0] wb_rd = dut.u_tinyriscv.ex_reg_waddr_o;
    wire [31:0] wb_data = dut.u_tinyriscv.ex_reg_wdata_o;
    wire [2:0] hold_flag = dut.u_tinyriscv.ctrl_hold_flag_o;
    wire jump_flag = dut.u_tinyriscv.ex_jump_flag_o;
    wire [31:0] jump_addr = dut.u_tinyriscv.ex_jump_addr_o;
    wire [31:0] x1 = dut.u_tinyriscv.u_regs.regs[1];
    wire [31:0] x2 = dut.u_tinyriscv.u_regs.regs[2];
    wire [31:0] x3 = dut.u_tinyriscv.u_regs.regs[3];
    wire [31:0] x4 = dut.u_tinyriscv.u_regs.regs[4];
    wire [31:0] x5 = dut.u_tinyriscv.u_regs.regs[5];
    wire [31:0] x6 = dut.u_tinyriscv.u_regs.regs[6];
    wire [31:0] x26 = dut.u_tinyriscv.u_regs.regs[26];
    wire [31:0] x27 = dut.u_tinyriscv.u_regs.regs[27];
    wire mem_req = dut.m0_req_i;
    wire mem_we = dut.m0_we_i;
    wire [31:0] mem_addr = dut.m0_addr_i;
    wire [31:0] mem_wdata = dut.m0_data_i;
    wire [31:0] mem_rdata = dut.m0_data_o;
    wire [31:0] gpio_ctrl = dut.gpio_0.gpio_ctrl;
    wire [31:0] gpio_data = dut.gpio_0.gpio_data;
    wire [31:0] timer_ctrl = dut.timer_0.timer_ctrl;
    wire [31:0] timer_count = dut.timer_0.timer_count;
    wire [31:0] timer_value = dut.timer_0.timer_value;
    wire timer_int = dut.timer0_int;
    wire [31:0] mtvec = dut.u_tinyriscv.u_csr_reg.mtvec;
    wire [31:0] mepc = dut.u_tinyriscv.u_csr_reg.mepc;
    wire [31:0] uart_status = dut.uart_0.uart_status;
    wire [31:0] uart_baud = dut.uart_0.uart_baud;
    wire [3:0] uart_state = dut.uart_0.state;
    wire [3:0] uart_bit = dut.uart_0.bit_cnt;
    wire [31:0] spi_status = dut.spi_0.spi_status;
    reg passed = 0, finished = 0;
    integer cycles = 0;
    integer interrupt_edges = 0;
    integer spi_frames = 0;
    integer max_cycles = DEFAULT_MAX_CYCLES;
    integer ignored, i;
    integer expected_gpio_writes = -1, gpio_writes = 0;
`ifdef LAB_PORT
    integer retired_count = 0, branch_count = 0, mispredict_count = 0;
`endif

    task automatic fail(input string why);
        if (!finished) begin
            finished = 1;
            $display("LAB_FAIL mode=%s cycles=%0d pc=%h reason=%s x3=%h x4=%h x5=%h", mode, cycles,
                     pc, why, x3, x4, x5);
            if (uart_log_fd != 0) $fclose(uart_log_fd);
            $finish;
        end
    endtask
    task automatic complete(input string why);
        if (!finished) begin
            if (expected_gpio_writes >= 0 && gpio_writes != expected_gpio_writes)
                $fatal(
                    1,
                    "GPIO side-effect count: expected %0d got %0d",
                    expected_gpio_writes,
                    gpio_writes
                );
            passed   = 1;
            finished = 1;
            $display("LAB_PASS mode=%s cycles=%0d timer_irqs=%0d spi_frames=%0d %s", mode, cycles,
                     interrupt_edges, spi_frames, why);
`ifdef LAB_PORT
            $display("LAB_STATS retired=%0d branches=%0d branch_mispredicts=%0d", retired_count,
                     branch_count, mispredict_count);
`endif
            if (uart_log_fd != 0) $fclose(uart_log_fd);
            $finish;
        end
    endtask

    always @(posedge timer_int) if (rst) interrupt_edges = interrupt_edges + 1;
    always @(posedge dut.spi_0.en) if (rst) spi_frames = spi_frames + 1;

`ifdef LAB_PORT
    // Sample at the committing edge, before nonblocking pipeline updates.
    // A detached divider has its own valid owner while EX contains bubbles.
    reg expected_if_valid = 0;
    always @(posedge clk) begin
        if (!rst) expected_if_valid = 0;
        else begin
            if (dut.u_tinyriscv.if_valid_o !== expected_if_valid)
                fail("IF validity disagrees with previous fetch/flush decision");
`ifdef LAB_WAIT_MEMORY
            if (dut.u_tinyriscv.pipe_control >= 3'd2) expected_if_valid = 0;
            else if (!(dut.u_tinyriscv.memory_wait || dut.u_tinyriscv.debug_pause))
                expected_if_valid = dut.u_tinyriscv.fetch_valid && dut.u_tinyriscv.fetch_consume;
`else
            expected_if_valid = (hold_flag < 3'd2) && !dut.u_tinyriscv.rib_hold_flag_i &&
                !dut.u_tinyriscv.jtag_halt_flag_i && !dut.u_tinyriscv.jtag_reset_flag_i;
`endif
        end
    end
    always @(posedge clk)
        if (rst && !finished) begin
            if (dut.s4_we_o) gpio_writes = gpio_writes + 1;
            if (dut.u_tinyriscv.retire_valid) retired_count = retired_count + 1;
            if (dut.u_tinyriscv.branch_resolve) branch_count = branch_count + 1;
            if (dut.u_tinyriscv.branch_mispredict) mispredict_count = mispredict_count + 1;
            if (dut.u_tinyriscv.trap_valid &&
                (wb_we || mem_req || mem_we || dut.u_tinyriscv.ex_csr_we_o ||
                 dut.u_tinyriscv.retire_valid))
                fail("trapping instruction produced effects or retired");
            if (!dut.u_tinyriscv.ie_valid_o) begin
                if (mem_req || mem_we || dut.u_tinyriscv.ex_csr_we_o)
                    fail("invalid EX instruction produced memory/CSR effects");
                if (wb_we && !(dut.u_tinyriscv.div_pending && dut.u_tinyriscv.div_ready_o))
                    fail("invalid EX instruction produced unowned writeback");
            end
        end
`endif

    initial begin
        ignored = $value$plusargs("MODE=%s", mode);
        ignored = $value$plusargs("GPIO_EXPECT_WRITES=%d", expected_gpio_writes);
        ignored = $value$plusargs("MAX_CYCLES=%d", max_cycles);
        if ($value$plusargs("UART_LOG=%s", uart_log_path)) begin
            uart_log_fd = $fopen(uart_log_path, "wb");
            if (uart_log_fd == 0) $fatal(1, "Cannot open UART_LOG");
        end
        if (!$value$plusargs("IMAGE=%s", image_path)) image_path = DEFAULT_IMAGE;
        if (image_path == "") $fatal(1, "IMAGE is required");
        // The reference xprintf.h sets _CR_CRLF=0.
        if (mode == "uart_tx") expected = "hello world\n";
        if (mode == "uart_rx") expected = "K";
        // The board ROM also has its own time-zero boot.mem initialization.
        // Override it deterministically while reset is still asserted.
        #1;
        for (i = 0; i < 4096; i = i + 1) dut.u_rom._rom[i] = 32'h00000013;
        $readmemh(image_path, dut.u_rom._rom);
        repeat (3) @(negedge clk);
        rst = 1;
    end

    integer terminal_retire_start;
    initial begin
        wait (rst === 1'b1);
        forever begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            if ((mode == "protocol" || mode == "timer" || mode == "spi" || mode == "coremark" ||
                 mode == "irq") && x26 === 32'd1) begin
`ifdef LAB_WAIT_MEMORY
                terminal_retire_start = retired_count;
                while (retired_count - terminal_retire_start < 2 && cycles < max_cycles) begin
                    @(posedge clk);
                    #1;
                    cycles = cycles + 1;
                end
`else
                repeat (5) @(posedge clk);
                #1;
`endif
                if (x27 !== 32'd1) fail("program reported failure");
                if (mode == "timer" && interrupt_edges < 2) fail("fewer than two timer interrupts");
                if (mode == "spi" && spi_frames != 8) fail("expected eight SPI byte transfers");
                if (mode == "coremark" && !coremark_crc_reported)
                    fail("missing CoreMark CRC success on UART");
                complete("x26=1 x27=1");
            end
            if (cycles >= max_cycles) fail("TIMEOUT");
        end
    end

    // Scoreboard for the unmodified, intentionally endless GPIO example.
    initial begin
        wait (rst === 1'b1);
        if (mode == "gpio") begin
            wait (gpio_ctrl[3:0] === 4'h9);
            repeat (200) @(negedge clk);
            if (gpio_pins[0] !== 0) fail("GPIO0 did not follow low input");
            gpio_drive = 1;
            repeat (200) @(negedge clk);
            if (gpio_pins[0] !== 1) fail("GPIO0 did not follow high input");
            gpio_drive = 0;
            repeat (200) @(negedge clk);
            if (gpio_pins[0] !== 0) fail("GPIO0 did not return low");
            complete("GPIO1 0->1->0 was mirrored on GPIO0");
        end
    end

    // Decode the actual TX wire rather than inspecting the software's intent.
    initial begin : uart_monitor
        reg [7:0] character;
        integer n, bit_cycles;
        wait (rst === 1'b1);
        if (mode == "uart_tx" || mode == "uart_rx" || mode == "coremark") begin
            wait (uart_tx === 1'b1);
            forever begin
                @(negedge uart_tx);
                bit_cycles = uart_baud[15:0] + 1;
                repeat (bit_cycles + bit_cycles / 2) @(posedge clk);
                for (n = 0; n < 8; n = n + 1) begin
                    character[n] = uart_tx;
                    repeat (bit_cycles) @(posedge clk);
                end
                if (uart_tx !== 1'b1) fail("UART stop bit invalid");
                if (mode == "coremark") begin
                    if (uart_log_fd != 0) $fwrite(uart_log_fd, "%c", character);
                    if (character == 8'h0a) begin
                        $display("COREMARK_UART %s", uart_line);
                        if (uart_line == "COREMARK_SMOKE_CRC_PASS (not a reportable score)")
                            coremark_crc_reported = 1;
                        uart_line = "";
                        if (uart_log_fd != 0) $fflush(uart_log_fd);
                    end else if (character != 8'h0d) uart_line = {uart_line, character};
                end else begin
                    received = {received, character};
                    $display("UART_BYTE %02h", character);
                    if (received.len() > expected.len()) fail("extra UART data");
                    if (received.len() == expected.len()) begin
                        if (received != expected) fail("UART text or echo mismatch");
                        complete("UART wire data matched expected text");
                    end
                end
            end
        end
    end

    initial begin : uart_stimulus
        reg [7:0] character;
        integer n, bit_cycles;
        wait (rst === 1'b1);
        if (mode == "uart_rx" || mode == "irq") begin
            wait (dut.uart_0.uart_ctrl[1] === 1'b1);
            repeat (300) @(negedge clk);  // Allow uart_getc to clear the old flag.
            bit_cycles = uart_baud[15:0] + 1;
            character = "K";
            uart_rx = 0;
            repeat (bit_cycles) @(negedge clk);
            for (n = 0; n < 8; n = n + 1) begin
                uart_rx = character[n];
                repeat (bit_cycles) @(negedge clk);
            end
            uart_rx = 1;
        end
    end
endmodule
