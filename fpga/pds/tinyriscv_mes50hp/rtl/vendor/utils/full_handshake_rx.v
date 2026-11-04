/*
 * 模块说明：跨时钟全握手接收端。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 数据接收端模块
// 跨时钟域传输，全(四次)握手协议
// req = 1
// ack_o = 1
// req = 0
// ack_o = 0
module full_handshake_rx #(
    parameter DW = 32
) (  // RX要接收数据的位宽

    input wire clk,   // RX端时钟信号
    input wire rst_n, // RX端复位信号

    // from tx
    input wire          req_i,      // TX端请求信号
    input wire [DW-1:0] req_data_i, // TX端输入数据

    // to tx
    output wire ack_o,  // RX端应答TX端信号

    // to rx
    output wire [DW-1:0] recv_data_o,  // RX端接收到的数据
    output wire          recv_rdy_o    // RX端是否接收到数据信号

);

    // ModelSim requires this declaration before the state-machine read below.
    reg req;

    localparam STATE_IDLE     = 2'b01;
    localparam STATE_DEASSERT = 2'b10;

    reg [1:0] state;
    reg [1:0] state_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= state_next;
        end
    end

    always @(*) begin
        case (state)
            // 等待TX请求信号req=1
            STATE_IDLE: begin
                if (req == 1'b1) begin
                    state_next = STATE_DEASSERT;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            // 等待req=0
            STATE_DEASSERT: begin
                if (req) begin
                    state_next = STATE_DEASSERT;
                end else begin
                    state_next = STATE_IDLE;
                end
            end
            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end

    reg req_d;

    // 将请求信号打两拍进行同步
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_d <= 1'b0;
            req   <= 1'b0;
        end else begin
            req_d <= req_i;
            req   <= req_d;
        end
    end

    reg [DW-1:0] recv_data;
    reg recv_rdy;
    reg ack;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ack <= 1'b0;
            recv_rdy <= 1'b0;
            recv_data <= {(DW) {1'b0}};
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (req == 1'b1) begin
                        ack       <= 1'b1;
                        recv_rdy  <= 1'b1;  // 这个信号只会持续一个时钟
                        recv_data <= req_data_i;  // 这个信号只会持续一个时钟
                    end
                end
                STATE_DEASSERT: begin
                    recv_rdy  <= 1'b0;
                    recv_data <= {(DW) {1'b0}};
                    // req撤销后ack也撤销
                    if (req == 1'b0) begin
                        ack <= 1'b0;
                    end
                end
            endcase
        end
    end

    assign ack_o = ack;
    assign recv_rdy_o = recv_rdy;
    assign recv_data_o = recv_data;

endmodule
