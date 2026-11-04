/*
 * 模块说明：GPIO 端口寄存器。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// GPIO模块
module gpio (

    input wire clk,
    input wire rst,

    input wire we_i,
    input wire [31:0] addr_i,
    input wire [31:0] data_i,

    output reg [31:0] data_o,

    input  wire [15:0] io_pin_i,
    output wire [31:0] reg_ctrl,
    output wire [31:0] reg_data

);


    // GPIO控制寄存器
    localparam GPIO_CTRL = 4'h0;
    // GPIO数据寄存器
    localparam GPIO_DATA = 4'h4;

    // 每2位控制1个IO的模式，最多支持16个IO
    // 0: 高阻，1：输出，2：输入
    reg [31:0] gpio_ctrl;
    // 输入输出数据
    reg [31:0] gpio_data;

    // Two sampling stages precede the input-mode DATA update. An external
    // transition becomes visible in DATA on the third rising edge. Reset
    // and MMIO-write priority retain the original peripheral contract.
    (* ASYNC_REG = "TRUE" *) reg [15:0] io_sync1;
    (* ASYNC_REG = "TRUE" *) reg [15:0] io_sync2;
    integer pin;
    always @(posedge clk) begin
        if (!rst) begin
            io_sync1 <= 16'b0;
            io_sync2 <= 16'b0;
        end else begin
            io_sync1 <= io_pin_i;
            io_sync2 <= io_sync1;
        end
    end


    assign reg_ctrl = gpio_ctrl;
    assign reg_data = gpio_data;


    // 写寄存器
    always @(posedge clk) begin
        if (rst == 1'b0) begin
            gpio_data <= 32'h0;
            gpio_ctrl <= 32'h0;
        end else begin
            if (we_i == 1'b1) begin
                case (addr_i[3:0])
                    GPIO_CTRL: begin
                        gpio_ctrl <= data_i;
                    end
                    GPIO_DATA: begin
                        gpio_data <= data_i;
                    end
                endcase
            end else begin
                for (pin = 0; pin < 16; pin = pin + 1) begin
                    if (gpio_ctrl[pin*2+:2] == 2'b10) gpio_data[pin] <= io_sync2[pin];
                end
            end
        end
    end

    // 读寄存器
    always @(*) begin
        if (rst == 1'b0) begin
            data_o = 32'h0;
        end else begin
            case (addr_i[3:0])
                GPIO_CTRL: begin
                    data_o = gpio_ctrl;
                end
                GPIO_DATA: begin
                    data_o = gpio_data;
                end
                default: begin
                    data_o = 32'h0;
                end
            endcase
        end
    end

endmodule
