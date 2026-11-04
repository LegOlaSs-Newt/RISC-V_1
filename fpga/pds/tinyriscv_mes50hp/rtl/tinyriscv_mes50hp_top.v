/*
 * 模块说明：PGL50H 板级顶层。
 * 来源说明：本项目板级适配。
 * 主要改动：连接 27 MHz 时钟、复位、KEY1 KEY2、LED 和 UART；KEY2 切换下载模式。
 * 关键约束：按键经过同步和消抖。CPU 局部复位不擦程序存储器；下载完成的 BIN 与 FPGA 配置位流是不同层次，掉电启动尚未验收。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// MES50HP adapter for the local Apache-2.0 TinyRISC-V reference core.
// Board: PGL50H-6IFBG484, configurable board oscillator, active-high LEDs.
`include "mes50hp_config.vh"
`include "memory_config.vh"
module tinyriscv_mes50hp_top #(
    parameter POR_CYCLES = 65536,
    parameter DEBOUNCE_CYCLES = 1000000,
    parameter MEMORY_SYSTEM = `MES50HP_MEMORY_SYSTEM,
    parameter CACHE_ENABLE = `MES50HP_CACHE_ENABLE
) (
    input wire clk_sys,
    input wire key1_n,
    input wire key2_n,
    input wire uart_rx,
    output wire uart_tx,
    output wire [7:0] led,
    inout wire [15:0] gpio
);
    reg [16:0] por_count = 0;
    reg [ 1:0] reset_release = 0;
    always @(posedge clk_sys or negedge key1_n) begin
        if (!key1_n) begin
            por_count <= 0;
            reset_release <= 0;
        end else begin
            if (por_count < POR_CYCLES) por_count <= por_count + 1'b1;
            reset_release <= {reset_release[0], (por_count == POR_CYCLES)};
        end
    end
    wire board_rst_n = reset_release[1];

    reg [1:0] key2_sync;
    reg key2_stable;
    reg [20:0] debounce_count;
    reg download_mode;
    reg [4:0] restart_count;
    always @(posedge clk_sys) begin
        if (!board_rst_n) begin
            key2_sync <= 2'b11;
            key2_stable <= 1'b1;
            debounce_count <= 0;
            download_mode <= 0;
            restart_count <= 5'd31;
        end else begin
            key2_sync <= {key2_sync[0], key2_n};
            if (restart_count != 0) restart_count <= restart_count - 1'b1;
            if (key2_sync[1] == key2_stable) begin
                debounce_count <= 0;
            end else if (debounce_count == DEBOUNCE_CYCLES - 1) begin
                debounce_count <= 0;
                key2_stable <= key2_sync[1];
                if (!key2_sync[1]) begin
                    download_mode <= ~download_mode;
                    if (!MEMORY_SYSTEM) restart_count <= 5'd31;
                end
            end else debounce_count <= debounce_count + 1'b1;
        end
    end
    wire soc_rst_n = board_rst_n && (restart_count == 0);

    reg [24:0] heartbeat_count;
    reg heartbeat;
    always @(posedge clk_sys) begin
        if (!board_rst_n) begin
            heartbeat_count <= 0;
            heartbeat <= 0;
        end else if (heartbeat_count == (`MES50HP_CPU_HZ / 2 - 1)) begin
            heartbeat_count <= 0;
            heartbeat <= ~heartbeat;
        end else heartbeat_count <= heartbeat_count + 1'b1;
    end

    wire over_n;
    wire success_n;
    wire actual_download_mode;
    // GPIO0..15 go to J16. LED3/4 mirror GPIO0/1 through explicit SoC ports.
    tinyriscv_soc_top #(
        .MEMORY_SYSTEM(MEMORY_SYSTEM),
        .CACHE_ENABLE (CACHE_ENABLE)
    ) u_soc (
        .clk(clk_sys),
        .rst(soc_rst_n),
        .over(over_n),
        .succ(success_n),
        .halted_ind(),
        .uart_debug_pin(download_mode),
        .download_active_o(actual_download_mode),
        .uart_rx_pin(uart_rx),
        .uart_tx_pin(uart_tx),
        .gpio(gpio),
        .gpio_led_o(led[3:2]),
        .jtag_TCK(1'b0),
        .jtag_TMS(1'b1),
        .jtag_TDI(1'b0),
        .jtag_TDO(),
        .spi_miso(1'b0),
        .spi_mosi(),
        .spi_ss(),
        .spi_clk()
    );
    assign led[0] = heartbeat;
    assign led[1] = actual_download_mode;
    assign led[4] = ~over_n;
    assign led[5] = ~success_n;
    assign led[6] = ~uart_tx;
    assign led[7] = soc_rst_n;
endmodule
