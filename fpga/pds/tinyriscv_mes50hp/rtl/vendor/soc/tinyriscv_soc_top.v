/*
 * 模块说明：处理器存储及外设集成。
 * 来源说明：基于 TinyRISC-V SoC 对应模块修改扩展，原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：按配置连接 Legacy 或 Wait 后端，集成 TIMER UART GPIO SPI、下载及调试主机。
 * 关键约束：程序及 RAM 各 16 KiB，MMIO 仅登记地址合法。下载和 halt 先停止新请求并排空，恢复执行前失效缓存及预测状态；板级不启用 CPU 软件 JTAG 引脚。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "../core/defines.v"
`include "../../memory_config.vh"

// tinyriscv soc顶层模块
module tinyriscv_soc_top #(
    parameter MEMORY_SYSTEM  = `MES50HP_MEMORY_SYSTEM,
    parameter CACHE_ENABLE   = `MES50HP_CACHE_ENABLE,
    parameter EARLY_D_LOOKUP = `MES50HP_EARLY_D_LOOKUP
) (

    input wire clk,
    input wire rst,

    output reg over,  // 测试是否完成信号
    output reg succ,  // 测试是否成功信号

    output wire halted_ind,  // jtag是否已经halt住CPU信号

    input  wire uart_debug_pin,    // 串口下载使能引脚
    output wire download_active_o,

    output wire uart_tx_pin,  // UART发送引脚
    input wire uart_rx_pin,  // UART接收引脚
    inout wire [15:0] gpio,  // J16 GPIO0..15
    output wire [1:0] gpio_led_o,  // Independent, active-high GPIO0/1 state

    input  wire jtag_TCK,  // JTAG TCK引脚
    input  wire jtag_TMS,  // JTAG TMS引脚
    input  wire jtag_TDI,  // JTAG TDI引脚
    output wire jtag_TDO,  // JTAG TDO引脚

    input  wire spi_miso,  // SPI MISO引脚
    output wire spi_mosi,  // SPI MOSI引脚
    output wire spi_ss,    // SPI SS引脚
    output wire spi_clk    // SPI CLK引脚

);


    // master 0 interface
    wire [`MemAddrBus] m0_addr_i;
    wire [`MemBus] m0_data_i;
    wire [`MemBus] m0_data_o;
    wire m0_req_i;
    wire m0_we_i;

    // master 1 interface
    wire [`MemAddrBus] m1_addr_i;
    wire [`MemBus] m1_data_i;
    wire [`MemBus] m1_data_o;
    wire m1_req_i;
    wire m1_we_i;

    // master 2 interface
    wire [`MemAddrBus] m2_addr_i;
    wire [`MemBus] m2_data_i;
    wire [`MemBus] m2_data_o;
    wire m2_req_i;
    wire m2_we_i;

    // master 3 interface
    wire [`MemAddrBus] m3_addr_i;
    wire [`MemBus] m3_data_i;
    wire [`MemBus] m3_data_o;
    wire m3_req_i;
    wire m3_we_i;

    // slave 0 interface
    wire [`MemAddrBus] s0_addr_o;
    wire [`MemBus] s0_data_o;
    wire [`MemBus] s0_data_i;
    wire s0_we_o;

    // slave 1 interface
    wire [`MemAddrBus] s1_addr_o;
    wire [`MemBus] s1_data_o;
    wire [`MemBus] s1_data_i;
    wire s1_we_o;

    // slave 2 interface
    wire [`MemAddrBus] s2_addr_o;
    wire [`MemBus] s2_data_o;
    wire [`MemBus] s2_data_i;
    wire s2_we_o;

    // slave 3 interface
    wire [`MemAddrBus] s3_addr_o;
    wire [`MemBus] s3_data_o;
    wire [`MemBus] s3_data_i;
    wire s3_we_o;

    // slave 4 interface
    wire [`MemAddrBus] s4_addr_o;
    wire [`MemBus] s4_data_o;
    wire [`MemBus] s4_data_i;
    wire s4_we_o;

    // slave 5 interface
    wire [`MemAddrBus] s5_addr_o;
    wire [`MemBus] s5_data_o;
    wire [`MemBus] s5_data_i;
    wire s5_we_o;

    // rib
    wire rib_hold_flag_o;

    // jtag
    wire jtag_halt_req_o;
    wire jtag_reset_req_o;
    wire [`RegAddrBus] jtag_reg_addr_o;
    wire [`RegBus] jtag_reg_data_o;
    wire jtag_reg_we_o;
    wire [`RegBus] jtag_reg_data_i;

    // tinyriscv
    wire [`INT_BUS] int_flag;

    // timer0
    wire timer0_int;
    wire software_int;
    wire uart_rx_int;
    wire cpu_rst_n, core_quiescent, memory_idle, fence_i;
    wire data_ready, data_valid, data_error, data_response_ready;
    wire lookup_valid, lookup_cancel, lookup_use, lookup_ready, lookup_result_valid, lookup_hit;
    wire [31:0] lookup_address, lookup_result_address, lookup_data;
    wire fetch_ready, fetch_valid, fetch_error, fetch_response_ready;
    wire [3:0] cpu_wstrb, memory_wstrb;
    wire rom_read_en, ram_read_en;
    wire host_ready, host_valid, host_error, host_response_ready;
    wire [31:0] host_data;
    wire uart_req, uart_we, uart_response_ready, uart_idle, uart_complete;
    wire [31:0] uart_addr, uart_data;
    wire jtag_mem_req, jtag_mem_response_ready;
    wire jtag_mem_ready, jtag_mem_valid, jtag_mem_error;
    reg download_active, restart_cpu, invalidate_all, reset_pending, host_busy;
    wire mode_transition = uart_debug_pin != download_active;
    wire host_request = download_active ? uart_req : jtag_mem_req;
    wire host_grant = memory_idle && core_quiescent && !restart_cpu;
    wire cpu_pause = download_active || mode_transition || jtag_halt_req_o || jtag_mem_req ||
        host_busy || reset_pending;
    wire actual_halted = jtag_halt_req_o && memory_idle && core_quiescent;
    assign cpu_rst_n = rst && !(MEMORY_SYSTEM && restart_cpu);
    assign download_active_o = MEMORY_SYSTEM ? download_active : uart_debug_pin;
    assign host_response_ready = download_active ? uart_response_ready : jtag_mem_response_ready;
    assign jtag_mem_ready = MEMORY_SYSTEM && !download_active && host_grant && host_ready;
    assign jtag_mem_valid = MEMORY_SYSTEM && !download_active && host_valid;
    assign jtag_mem_error = host_error;
    always @(posedge clk) begin
        if (!rst) begin
            download_active <= 0;
            restart_cpu <= 0;
            invalidate_all <= 0;
            reset_pending <= 0;
            host_busy <= 0;
        end else if (MEMORY_SYSTEM) begin
            restart_cpu <= 0;
            invalidate_all <= 0;
            if (jtag_reset_req_o) reset_pending <= 1;
            if (host_request && host_grant && host_ready) host_busy <= 1;
            if (host_valid && host_response_ready) host_busy <= 0;
            if ((mode_transition || reset_pending) && memory_idle && core_quiescent && !host_busy &&
                uart_idle) begin
                download_active <= uart_debug_pin;
                restart_cpu <= 1;
                invalidate_all <= 1;
                reset_pending <= 0;
            end
        end
    end

    // gpio
    wire [15:0] io_in;
    wire [31:0] gpio_ctrl;
    wire [31:0] gpio_data;

    assign int_flag   = {5'h0, uart_rx_int, software_int, timer0_int};

    // 低电平点亮LED
    // 低电平表示已经halt住CPU
    assign halted_ind = ~(MEMORY_SYSTEM ? actual_halted : jtag_halt_req_o);


    // MES50HP port: PDS does not synthesize hierarchical register-array reads.
    wire [`RegBus] test_x26;
    wire [`RegBus] test_x27;
    always @(posedge clk) begin
        if (rst == `RstEnable) begin
            over <= 1'b1;
            succ <= 1'b1;
        end else begin
            over <= ~test_x26[0];  // when = 1, run over
            succ <= ~test_x27[0];  // when = 1, run succ, otherwise fail
        end
    end

    // tinyriscv处理器核模块例化
    tinyriscv #(
        .WAIT_MEMORY(MEMORY_SYSTEM),
        .EARLY_D_LOOKUP(EARLY_D_LOOKUP && MEMORY_SYSTEM && CACHE_ENABLE)
    ) u_tinyriscv (
        .clk(clk),
        .rst(cpu_rst_n),
        .rib_ex_addr_o(m0_addr_i),
        .rib_ex_data_i(m0_data_o),
        .rib_ex_data_o(m0_data_i),
        .rib_ex_req_o(m0_req_i),
        .rib_ex_we_o(m0_we_i),
        .rib_ex_wstrb_o(cpu_wstrb),
        .data_req_ready_i(data_ready),
        .data_rsp_valid_i(data_valid),
        .data_rsp_error_i(data_error),
        .data_rsp_ready_o(data_response_ready),
        .data_lookup_valid_o(lookup_valid),
        .data_lookup_cancel_o(lookup_cancel),
        .data_lookup_use_o(lookup_use),
        .data_lookup_addr_o(lookup_address),
        .data_lookup_ready_i(lookup_ready),
        .data_lookup_result_valid_i(lookup_result_valid),
        .data_lookup_hit_i(lookup_hit),
        .data_lookup_result_addr_i(lookup_result_address),
        .data_lookup_data_i(lookup_data),

        .rib_pc_addr_o(m1_addr_i),
        .rib_pc_data_i(m1_data_o),
        .fetch_req_valid_o(m1_req_i),
        .fetch_req_ready_i(fetch_ready),
        .fetch_rsp_valid_i(fetch_valid),
        .fetch_rsp_error_i(fetch_error),
        .fetch_rsp_ready_o(fetch_response_ready),
        .fence_i_o(fence_i),
        .quiescent_o(core_quiescent),
        .prediction_clear_i(MEMORY_SYSTEM &&
                            (invalidate_all || (host_request && host_grant && host_ready &&
                                                (download_active ? uart_we : m2_we_i)))),

        .jtag_reg_addr_i(jtag_reg_addr_o),
        .jtag_reg_data_i(jtag_reg_data_o),
        .jtag_reg_we_i  (jtag_reg_we_o),
        .jtag_reg_data_o(jtag_reg_data_i),

        .rib_hold_flag_i  (rib_hold_flag_o),
        .jtag_halt_flag_i (MEMORY_SYSTEM ? cpu_pause : jtag_halt_req_o),
        .jtag_reset_flag_i(MEMORY_SYSTEM ? 1'b0 : jtag_reset_req_o),

        .int_i(int_flag),
        .test_x26_o(test_x26),
        .test_x27_o(test_x27)
    );

    // rom模块例化
    rom #(
        .SYNC_READ(MEMORY_SYSTEM)
    ) u_rom (
        .clk(clk),
        .rst(rst),
        .we_i(s0_we_o),
        .addr_i(s0_addr_o),
        .data_i(s0_data_o),
        .read_en_i(rom_read_en),
        .wstrb_i(memory_wstrb),
        .data_o(s0_data_i)
    );

    // ram模块例化
    ram #(
        .SYNC_READ(MEMORY_SYSTEM)
    ) u_ram (
        .clk(clk),
        .rst(rst),
        .we_i(s1_we_o),
        .addr_i(s1_addr_o),
        .data_i(s1_data_o),
        .read_en_i(ram_read_en),
        .wstrb_i(memory_wstrb),
        .data_o(s1_data_i)
    );

    // timer模块例化
    timer timer_0 (
        .clk(clk),
        .rst(cpu_rst_n),
        .data_i(s2_data_o),
        .addr_i(s2_addr_o),
        .we_i(s2_we_o),
        .data_o(s2_data_i),
        .int_sig_o(timer0_int),
        .software_int_o(software_int)
    );

    // uart模块例化
    uart #(
        .RESET_TX_HIGH(MEMORY_SYSTEM)
    ) uart_0 (
        .rx_int_o(uart_rx_int),
        .clk(clk),
        .rst(cpu_rst_n),
        .we_i(s3_we_o),
        .addr_i(s3_addr_o),
        .data_i(s3_data_o),
        .data_o(s3_data_i),
        .tx_pin(uart_tx_pin),
        .rx_pin(uart_rx_pin)
    );

    genvar gpio_index;
    generate
        for (gpio_index = 0; gpio_index < 16; gpio_index = gpio_index + 1) begin : gpio_pads
            assign gpio[gpio_index] = rst && (gpio_ctrl[gpio_index*2+:2] == 2'b01) ?
                gpio_data[gpio_index] : 1'bz;
            assign io_in[gpio_index] = gpio[gpio_index];
            if (gpio_index < 2) begin : led_mirror
                assign gpio_led_o[gpio_index] = rst && ((gpio_ctrl[gpio_index*2+:2] == 2'b01) ||
                                                        (gpio_ctrl[gpio_index*2+:2] == 2'b10)) ?
                    gpio_data[gpio_index] : 1'b0;
            end
        end
    endgenerate

    // gpio模块例化
    gpio gpio_0 (
        .clk(clk),
        .rst(cpu_rst_n),
        .we_i(s4_we_o),
        .addr_i(s4_addr_o),
        .data_i(s4_data_o),
        .data_o(s4_data_i),
        .io_pin_i(io_in),
        .reg_ctrl(gpio_ctrl),
        .reg_data(gpio_data)
    );

    // spi模块例化
    spi spi_0 (
        .clk(clk),
        .rst(cpu_rst_n),
        .data_i(s5_data_o),
        .addr_i(s5_addr_o),
        .we_i(s5_we_o),
        .data_o(s5_data_i),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_ss(spi_ss),
        .spi_clk(spi_clk)
    );

    generate
        if (!MEMORY_SYSTEM) begin : legacy_memory
            assign data_ready = 0;
            assign data_valid = 0;
            assign data_error = 0;
            assign lookup_ready = 0;
            assign lookup_result_valid = 0;
            assign lookup_hit = 0;
            assign lookup_result_address = 0;
            assign lookup_data = 0;
            assign fetch_ready = 0;
            assign fetch_valid = 0;
            assign fetch_error = 0;
            assign rom_read_en = 0;
            assign ram_read_en = 0;
            assign memory_wstrb = 4'b1111;
            assign memory_idle = 1;
            assign host_ready = 0;
            assign host_valid = 0;
            assign host_error = 0;
            assign host_data = 0;
            assign uart_idle = 1;
            assign uart_req = 0;
            assign uart_we = 0;
            assign uart_addr = 0;
            assign uart_data = 0;
            assign uart_response_ready = 0;
            assign uart_complete = 0;
            // rib模块例化
            rib u_rib (
                .clk(clk),
                .rst(rst),

                // master 0 interface
                .m0_addr_i(m0_addr_i),
                .m0_data_i(m0_data_i),
                .m0_data_o(m0_data_o),
                .m0_req_i (m0_req_i),
                .m0_we_i  (m0_we_i),

                // master 1 interface
                .m1_addr_i(m1_addr_i),
                .m1_data_i(`ZeroWord),
                .m1_data_o(m1_data_o),
                .m1_req_i (`RIB_REQ),
                .m1_we_i  (`WriteDisable),

                // master 2 interface
                .m2_addr_i(m2_addr_i),
                .m2_data_i(m2_data_i),
                .m2_data_o(m2_data_o),
                .m2_req_i (m2_req_i),
                .m2_we_i  (m2_we_i),

                // master 3 interface
                .m3_addr_i(m3_addr_i),
                .m3_data_i(m3_data_i),
                .m3_data_o(m3_data_o),
                .m3_req_i (m3_req_i),
                .m3_we_i  (m3_we_i),

                // slave 0 interface
                .s0_addr_o(s0_addr_o),
                .s0_data_o(s0_data_o),
                .s0_data_i(s0_data_i),
                .s0_we_o  (s0_we_o),

                // slave 1 interface
                .s1_addr_o(s1_addr_o),
                .s1_data_o(s1_data_o),
                .s1_data_i(s1_data_i),
                .s1_we_o  (s1_we_o),

                // slave 2 interface
                .s2_addr_o(s2_addr_o),
                .s2_data_o(s2_data_o),
                .s2_data_i(s2_data_i),
                .s2_we_o  (s2_we_o),

                // slave 3 interface
                .s3_addr_o(s3_addr_o),
                .s3_data_o(s3_data_o),
                .s3_data_i(s3_data_i),
                .s3_we_o  (s3_we_o),

                // slave 4 interface
                .s4_addr_o(s4_addr_o),
                .s4_data_o(s4_data_o),
                .s4_data_i(s4_data_i),
                .s4_we_o  (s4_we_o),

                // slave 5 interface
                .s5_addr_o(s5_addr_o),
                .s5_data_o(s5_data_o),
                .s5_data_i(s5_data_i),
                .s5_we_o  (s5_we_o),

                .hold_flag_o(rib_hold_flag_o)
            );

            // 串口下载模块例化
            uart_debug u_uart_debug (
                .clk(clk),
                .rst(rst),
                .debug_en_i(uart_debug_pin),
                .req_o(m3_req_i),
                .mem_we_o(m3_we_i),
                .mem_addr_o(m3_addr_i),
                .mem_wdata_o(m3_data_i),
                .mem_rdata_i(m3_data_o)
            );

        end else begin : cached_memory
            wire [31:0] memory_addr, memory_data, peripheral_addr, peripheral_data;
            wire memory_read, memory_write, memory_ram, peripheral_write;
            wire [3:0] peripheral_select;
            assign rib_hold_flag_o = 1'b0;
            assign m3_req_i = download_active;
            assign m3_we_i = uart_we;
            assign m3_addr_i = uart_addr;
            assign m3_data_i = uart_data;
            assign m3_data_o = host_data;
            assign m2_data_o = host_data;
            assign s0_addr_o = {18'b0, memory_addr[13:0]};
            assign s1_addr_o = {18'b0, memory_addr[13:0]};
            assign s0_data_o = memory_data;
            assign s1_data_o = memory_data;
            assign s0_we_o = memory_write && !memory_ram;
            assign s1_we_o = memory_write && memory_ram;
            assign rom_read_en = memory_read && !memory_ram;
            assign ram_read_en = memory_read && memory_ram;
            assign s2_addr_o = peripheral_addr;
            assign s3_addr_o = peripheral_addr;
            assign s4_addr_o = peripheral_addr;
            assign s5_addr_o = peripheral_addr;
            assign s2_data_o = peripheral_data;
            assign s3_data_o = peripheral_data;
            assign s4_data_o = peripheral_data;
            assign s5_data_o = peripheral_data;
            assign s2_we_o = peripheral_write && peripheral_select == 2;
            assign s3_we_o = peripheral_write && peripheral_select == 3;
            assign s4_we_o = peripheral_write && peripheral_select == 4;
            assign s5_we_o = peripheral_write && peripheral_select == 5;
            memory_system #(
                .CACHE_ENABLE  (CACHE_ENABLE),
                .EARLY_D_LOOKUP(EARLY_D_LOOKUP)
            ) u_memory_system (
                .clk(clk),
                .rst(rst),
                .fence_i_i(fence_i),
                .invalidate_all_i(invalidate_all),
                .i_req_valid_i(m1_req_i),
                .i_req_addr_i(m1_addr_i),
                .i_req_ready_o(fetch_ready),
                .i_rsp_valid_o(fetch_valid),
                .i_rsp_error_o(fetch_error),
                .i_rsp_data_o(m1_data_o),
                .i_rsp_ready_i(fetch_response_ready),
                .d_req_valid_i(m0_req_i),
                .d_req_write_i(m0_we_i),
                .d_req_addr_i(m0_addr_i),
                .d_req_wdata_i(m0_data_i),
                .d_req_wstrb_i(cpu_wstrb),
                .d_req_ready_o(data_ready),
                .d_rsp_valid_o(data_valid),
                .d_rsp_error_o(data_error),
                .d_rsp_data_o(m0_data_o),
                .d_rsp_ready_i(data_response_ready),
                .d_lookup_valid_i(lookup_valid),
                .d_lookup_cancel_i(lookup_cancel),
                .d_lookup_use_i(lookup_use),
                .d_lookup_addr_i(lookup_address),
                .d_lookup_ready_o(lookup_ready),
                .d_lookup_result_valid_o(lookup_result_valid),
                .d_lookup_hit_o(lookup_hit),
                .d_lookup_result_addr_o(lookup_result_address),
                .d_lookup_data_o(lookup_data),
                .h_req_valid_i(host_request && host_grant),
                .h_req_write_i(download_active ? uart_we : m2_we_i),
                .h_req_addr_i(download_active ? uart_addr : m2_addr_i),
                .h_req_wdata_i(download_active ? uart_data : m2_data_i),
                .h_req_ready_o(host_ready),
                .h_rsp_valid_o(host_valid),
                .h_rsp_error_o(host_error),
                .h_rsp_data_o(host_data),
                .h_rsp_ready_i(host_response_ready),
                .mem_addr_o(memory_addr),
                .mem_wdata_o(memory_data),
                .mem_wstrb_o(memory_wstrb),
                .mem_read_en_o(memory_read),
                .mem_write_en_o(memory_write),
                .mem_ram_o(memory_ram),
                .mem_rdata_i(memory_ram ? s1_data_i : s0_data_i),
                .mmio_addr_o(peripheral_addr),
                .mmio_wdata_o(peripheral_data),
                .mmio_select_o(peripheral_select),
                .mmio_write_en_o(peripheral_write),
                .timer_rdata_i(s2_data_i),
                .uart_rdata_i(s3_data_i),
                .gpio_rdata_i(s4_data_i),
                .spi_rdata_i(s5_data_i),
                .idle_o(memory_idle)
            );
            uart_debug_wait u_uart_debug_wait (
                .clk(clk),
                .rst(rst),
                .enable_i(download_active),
                .stop_i(!uart_debug_pin),
                .req_valid_o(uart_req),
                .req_write_o(uart_we),
                .req_addr_o(uart_addr),
                .req_wdata_o(uart_data),
                .req_ready_i(download_active && host_grant && host_ready),
                .rsp_valid_i(download_active && host_valid),
                .rsp_error_i(host_error),
                .rsp_data_i(host_data),
                .rsp_ready_o(uart_response_ready),
                .idle_o(uart_idle),
                .image_complete_o(uart_complete)
            );
        end
    endgenerate

    // jtag模块例化
    jtag_top #(
        .DMI_ADDR_BITS(6),
        .DMI_DATA_BITS(32),
        .DMI_OP_BITS  (2),
        .WAIT_MEMORY  (MEMORY_SYSTEM)
    ) u_jtag_top (
        .clk(clk),
        .jtag_rst_n(rst),
        .jtag_pin_TCK(jtag_TCK),
        .jtag_pin_TMS(jtag_TMS),
        .jtag_pin_TDI(jtag_TDI),
        .jtag_pin_TDO(jtag_TDO),
        .reg_we_o(jtag_reg_we_o),
        .reg_addr_o(jtag_reg_addr_o),
        .reg_wdata_o(jtag_reg_data_o),
        .reg_rdata_i(jtag_reg_data_i),
        .mem_we_o(m2_we_i),
        .mem_addr_o(m2_addr_i),
        .mem_wdata_o(m2_data_i),
        .mem_rdata_i(m2_data_o),
        .op_req_o(m2_req_i),
        .mem_req_valid_o(jtag_mem_req),
        .mem_rsp_ready_o(jtag_mem_response_ready),
        .mem_req_ready_i(jtag_mem_ready),
        .mem_rsp_valid_i(jtag_mem_valid),
        .mem_rsp_error_i(jtag_mem_error),
        .halted_i(MEMORY_SYSTEM ? actual_halted : jtag_halt_req_o),
        .halt_req_o(jtag_halt_req_o),
        .reset_req_o(jtag_reset_req_o)
    );

endmodule
