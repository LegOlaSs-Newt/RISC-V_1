/*
 * 模块说明：跨时钟全握手发送端。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 数据发送端模块
// 跨时钟域传输，全(四次)握手协议
// req_o = 1
// ack = 1
// req_o = 0
// ack = 0
module full_handshake_tx #(
    parameter DW = 32
) (  // TX要发送数据的位宽

    input wire clk,   // TX端时钟信号
    input wire rst_n, // TX端复位信号

    // from rx
    input wire ack_i,  // RX端应答信号

    // from tx
    input wire          req_i,      // TX端请求信号，只需持续一个时钟
    input wire [DW-1:0] req_data_i, // TX端要发送的数据，只需持续一个时钟

    // to tx
    output wire idle_o,  // TX端是否空闲信号，空闲才能发数据

    // to rx
    output wire          req_o,      // TX端请求信号
    output wire [DW-1:0] req_data_o  // TX端要发送的数据

);

    // ModelSim requires this declaration before the state-machine read below.
    reg ack;

    localparam STATE_IDLE     = 3'b001;
    localparam STATE_ASSERT   = 3'b010;
    localparam STATE_DEASSERT = 3'b100;

    reg [2:0] state;
    reg [2:0] state_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= state_next;
        end
    end

    always @(*) begin
        case (state)
            STATE_IDLE: begin
                if (req_i == 1'b1) begin
                    state_next = STATE_ASSERT;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            // 等待ack=1
            STATE_ASSERT: begin
                if (!ack) begin
                    state_next = STATE_ASSERT;
                end else begin
                    state_next = STATE_DEASSERT;
                end
            end
            // 等待ack=0
            STATE_DEASSERT: begin
                if (!ack) begin
                    state_next = STATE_IDLE;
                end else begin
                    state_next = STATE_DEASSERT;
                end
            end
            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end

    reg ack_d;

    // 将应答信号打两拍进行同步
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack_d <= 1'b0;
            ack   <= 1'b0;
        end else begin
            ack_d <= ack_i;
            ack   <= ack_d;
        end
    end

    reg req;
    reg [DW-1:0] req_data;
    reg idle;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idle <= 1'b1;
            req <= 1'b0;
            req_data <= {(DW) {1'b0}};
        end else begin
            case (state)
                // 锁存TX请求数据，在收到ack之前一直保持有效
                STATE_IDLE: begin
                    if (req_i == 1'b1) begin
                        idle <= 1'b0;
                        req <= req_i;
                        req_data <= req_data_i;
                    end else begin
                        idle <= 1'b1;
                        req  <= 1'b0;
                    end
                end
                // 收到RX的ack之后撤销TX请求
                STATE_ASSERT: begin
                    if (ack == 1'b1) begin
                        req <= 1'b0;
                        req_data <= {(DW) {1'b0}};
                    end
                end
                STATE_DEASSERT: begin
                    if (!ack) begin
                        idle <= 1'b1;
                    end
                end
            endcase
        end
    end

    assign idle_o = idle;
    assign req_o = req;
    assign req_data_o = req_data;

endmodule
