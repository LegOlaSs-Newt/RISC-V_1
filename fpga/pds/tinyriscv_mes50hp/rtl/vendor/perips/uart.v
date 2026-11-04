/*
 * 模块说明：UART 收发外设。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 串口模块(默认: 115200, 8 N 1)
// MES50HP port: keep UART timing consistent with the selected board clock.
`include "../../mes50hp_config.vh"
module uart #(
    parameter RESET_TX_HIGH = 0
) (

    input wire clk,
    input wire rst,

    input wire we_i,
    input wire [31:0] addr_i,
    input wire [31:0] data_i,

    output reg [31:0] data_o,
    output wire tx_pin,
    input wire rx_pin,
    output wire rx_int_o

);


    // 50MHz时钟，波特率115200bps对应的分频系数
    localparam BAUD_115200 = `MES50HP_UART_DIV;

    localparam S_IDLE      = 4'b0001;
    localparam S_START     = 4'b0010;
    localparam S_SEND_BYTE = 4'b0100;
    localparam S_STOP      = 4'b1000;

    reg         tx_data_valid;
    reg         tx_data_ready;

    reg  [ 3:0] state;
    reg  [15:0] cycle_cnt;
    reg  [ 3:0] bit_cnt;
    reg  [ 7:0] tx_data;
    reg         tx_reg;

    reg         rx_q0;
    reg         rx_q1;
    wire        rx_negedge;
    reg         rx_start;  // RX使能
    reg  [ 3:0] rx_clk_edge_cnt;  // clk时钟沿的个数
    reg         rx_clk_edge_level;  // clk沿电平
    reg         rx_done;
    reg  [15:0] rx_clk_cnt;
    reg  [15:0] rx_div_cnt;
    reg  [ 7:0] rx_data;
    reg         rx_over;

    localparam UART_CTRL   = 8'h0;
    localparam UART_STATUS = 8'h4;
    localparam UART_BAUD   = 8'h8;
    localparam UART_TXDATA = 8'hc;
    localparam UART_RXDATA = 8'h10;

    // addr: 0x00
    // rw. bit[0]: tx enable, 1 = enable, 0 = disable
    // rw. bit[1]: rx enable, 1 = enable, 0 = disable
    reg [31:0] uart_ctrl;

    // addr: 0x04
    // ro. bit[0]: tx busy, 1 = busy, 0 = idle
    // rw. bit[1]: rx over, 1 = over, 0 = receiving
    // must check this bit before tx data
    reg [31:0] uart_status;

    // addr: 0x08
    // rw. clk div
    reg [31:0] uart_baud;

    // addr: 0x10
    // ro. rx data
    reg [31:0] uart_rx;

    assign tx_pin   = tx_reg;
    // CTRL[2] is disabled on reset; STATUS[1] retains its existing clear rule.
    assign rx_int_o = uart_ctrl[2] && uart_status[1];


    // 写寄存器
    always @(posedge clk) begin
        if (rst == 1'b0) begin
            uart_ctrl <= 32'h0;
            uart_status <= 32'h0;
            uart_rx <= 32'h0;
            uart_baud <= BAUD_115200;
            tx_data_valid <= 1'b0;
        end else begin
            if (we_i == 1'b1) begin
                case (addr_i[7:0])
                    UART_CTRL: begin
                        uart_ctrl <= data_i;
                    end
                    UART_BAUD: begin
                        uart_baud <= data_i;
                    end
                    UART_STATUS: begin
                        uart_status[1] <= data_i[1];
                    end
                    UART_TXDATA: begin
                        if (uart_ctrl[0] == 1'b1 && uart_status[0] == 1'b0) begin
                            tx_data <= data_i[7:0];
                            uart_status[0] <= 1'b1;
                            tx_data_valid <= 1'b1;
                        end
                    end
                endcase
            end else begin
                tx_data_valid <= 1'b0;
                if (tx_data_ready == 1'b1) begin
                    uart_status[0] <= 1'b0;
                end
                if (uart_ctrl[1] == 1'b1) begin
                    if (rx_over == 1'b1) begin
                        uart_status[1] <= 1'b1;
                        uart_rx <= {24'h0, rx_data};
                    end
                end
            end
        end
    end

    // 读寄存器
    always @(*) begin
        if (rst == 1'b0) begin
            data_o = 32'h0;
        end else begin
            case (addr_i[7:0])
                UART_CTRL: begin
                    data_o = uart_ctrl;
                end
                UART_STATUS: begin
                    data_o = uart_status;
                end
                UART_BAUD: begin
                    data_o = uart_baud;
                end
                UART_RXDATA: begin
                    data_o = uart_rx;
                end
                default: begin
                    data_o = 32'h0;
                end
            endcase
        end
    end

    // *************************** TX发送 ****************************

    always @(posedge clk) begin
        if (rst == 1'b0) begin
            state <= S_IDLE;
            cycle_cnt <= 16'd0;
            tx_reg <= RESET_TX_HIGH ? 1'b1 : 1'b0;
            bit_cnt <= 4'd0;
            tx_data_ready <= 1'b0;
        end else begin
            if (state == S_IDLE) begin
                tx_reg <= 1'b1;
                tx_data_ready <= 1'b0;
                if (tx_data_valid == 1'b1) begin
                    state <= S_START;
                    cycle_cnt <= 16'd0;
                    bit_cnt <= 4'd0;
                    tx_reg <= 1'b0;
                end
            end else begin
                cycle_cnt <= cycle_cnt + 16'd1;
                if (cycle_cnt == uart_baud[15:0]) begin
                    cycle_cnt <= 16'd0;
                    case (state)
                        S_START: begin
                            tx_reg  <= tx_data[bit_cnt];
                            state   <= S_SEND_BYTE;
                            bit_cnt <= bit_cnt + 4'd1;
                        end
                        S_SEND_BYTE: begin
                            bit_cnt <= bit_cnt + 4'd1;
                            if (bit_cnt == 4'd8) begin
                                state  <= S_STOP;
                                tx_reg <= 1'b1;
                            end else begin
                                tx_reg <= tx_data[bit_cnt];
                            end
                        end
                        S_STOP: begin
                            tx_reg <= 1'b1;
                            state <= S_IDLE;
                            tx_data_ready <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end

    // *************************** RX接收 ****************************

    // 下降沿检测(检测起始信号)
    assign rx_negedge = rx_q1 && ~rx_q0;


    always @(posedge clk) begin
        if (rst == 1'b0) begin
            rx_q0 <= 1'b0;
            rx_q1 <= 1'b0;
        end else begin
            rx_q0 <= rx_pin;
            rx_q1 <= rx_q0;
        end
    end

    // 开始接收数据信号，接收期间一直有效
    always @(posedge clk) begin
        if (rst == 1'b0) begin
            rx_start <= 1'b0;
        end else begin
            if (uart_ctrl[1]) begin
                if (rx_negedge) begin
                    rx_start <= 1'b1;
                end else if (rx_clk_edge_cnt == 4'd9) begin
                    rx_start <= 1'b0;
                end
            end else begin
                rx_start <= 1'b0;
            end
        end
    end

    always @(posedge clk) begin
        if (rst == 1'b0) begin
            rx_div_cnt <= 16'h0;
        end else begin
            // 第一个时钟沿只需波特率分频系数的一半
            if (rx_start == 1'b1 && rx_clk_edge_cnt == 4'h0) begin
                rx_div_cnt <= {1'b0, uart_baud[15:1]};
            end else begin
                rx_div_cnt <= uart_baud[15:0];
            end
        end
    end

    // 对时钟进行计数
    always @(posedge clk) begin
        if (rst == 1'b0) begin
            rx_clk_cnt <= 16'h0;
        end else if (rx_start == 1'b1) begin
            // 计数达到分频值
            if (rx_clk_cnt == rx_div_cnt) begin
                rx_clk_cnt <= 16'h0;
            end else begin
                rx_clk_cnt <= rx_clk_cnt + 1'b1;
            end
        end else begin
            rx_clk_cnt <= 16'h0;
        end
    end

    // 每当时钟计数达到分频值时产生一个上升沿脉冲
    always @(posedge clk) begin
        if (rst == 1'b0) begin
            rx_clk_edge_cnt   <= 4'h0;
            rx_clk_edge_level <= 1'b0;
        end else if (rx_start == 1'b1) begin
            // 计数达到分频值
            if (rx_clk_cnt == rx_div_cnt) begin
                // 时钟沿个数达到最大值
                if (rx_clk_edge_cnt == 4'd9) begin
                    rx_clk_edge_cnt   <= 4'h0;
                    rx_clk_edge_level <= 1'b0;
                end else begin
                    // 时钟沿个数加1
                    rx_clk_edge_cnt   <= rx_clk_edge_cnt + 1'b1;
                    // 产生上升沿脉冲
                    rx_clk_edge_level <= 1'b1;
                end
            end else begin
                rx_clk_edge_level <= 1'b0;
            end
        end else begin
            rx_clk_edge_cnt   <= 4'h0;
            rx_clk_edge_level <= 1'b0;
        end
    end

    // bit序列
    always @(posedge clk) begin
        if (rst == 1'b0) begin
            rx_data <= 8'h0;
            rx_over <= 1'b0;
        end else begin
            if (rx_start == 1'b1) begin
                // 上升沿
                if (rx_clk_edge_level == 1'b1) begin
                    case (rx_clk_edge_cnt)
                        // 起始位
                        1: begin

                        end
                        // 数据位
                        2, 3, 4, 5, 6, 7, 8, 9: begin
                            rx_data <= rx_data | (rx_pin << (rx_clk_edge_cnt - 2));
                            // 最后一位接收完成，置位接收完成标志
                            if (rx_clk_edge_cnt == 4'h9) begin
                                rx_over <= 1'b1;
                            end
                        end
                    endcase
                end
            end else begin
                rx_data <= 8'h0;
                rx_over <= 1'b0;
            end
        end
    end

endmodule
