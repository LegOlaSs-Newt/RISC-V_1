/*
 * 模块说明：等待接口取指事务。
 * 来源说明：本项目新增。
 * 主要改动：保存取指请求及返回归属，提供前端缓冲并处理同步取指错误。
 * 关键约束：重定向或清空优先于安装旧路径返回；已接受的旧事务排空后丢弃，不能把旧响应当成新 PC 的指令。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// One outstanding fetch with stable owner and stale-response draining.
module fetch_transaction (
    input wire clk,
    rst,
    input wire enable_i,
    flush_i,
    consume_i,
    input wire redirect_i,
    input wire [31:0] redirect_pc_i,
    input wire [31:0] pc_i,
    predicted_next_i,
    output wire req_valid_o,
    input wire req_ready_i,
    output wire [31:0] req_addr_o,
    input wire rsp_valid_i,
    rsp_error_i,
    input wire [31:0] rsp_data_i,
    output wire rsp_ready_o,
    output wire valid_o,
    error_o,
    output wire [31:0] data_o,
    pc_o,
    predicted_next_o,
    output wire [31:0] lookup_pc_o,
    output wire busy_o
);
    reg sending, waiting, poison, local_fault;
    reg [31:0] owner_pc, owner_prediction;
    wire completed = waiting && ((local_fault && (poison || flush_i || consume_i)) ||
                                 (!local_fault && rsp_valid_i && rsp_ready_o));
    wire
        launch = rst && enable_i && (!flush_i || redirect_i) && !sending && (!waiting || completed);
    // A known redirect may replace a result being discarded at this edge.
    // After an earlier redirect's drain, PC holds the latest recovery target.
    wire [31:0] candidate_pc = redirect_i ? redirect_pc_i :
        poison ? pc_i : waiting ? owner_prediction : pc_i;
    wire candidate_fault = |candidate_pc[1:0] || candidate_pc >= 32'h4000;
    // Query the predictor for the successor while the current owner returns.
    // The CPU's PC still advances only when that owner's result is consumed.
    assign lookup_pc_o = sending ? owner_pc : candidate_pc;
    assign req_valid_o = rst && (sending || (launch && !candidate_fault));
    assign req_addr_o = sending ? owner_pc : candidate_pc;
    assign busy_o = sending || waiting || launch;
    assign valid_o = waiting && (local_fault || rsp_valid_i) && !poison && !flush_i;
    assign error_o = local_fault || rsp_error_i;
    assign data_o = local_fault ? 32'b0 : rsp_data_i;
    assign pc_o = owner_pc;
    assign predicted_next_o = owner_prediction;
    assign rsp_ready_o = rst && waiting && !local_fault && (poison || flush_i || consume_i);
    always @(posedge clk) begin
        if (!rst) begin
            sending <= 0;
            waiting <= 0;
            poison <= 0;
            local_fault <= 0;
            owner_pc <= 0;
            owner_prediction <= 0;
        end else begin
            if (completed) begin
                waiting <= 0;
                poison <= 0;
                local_fault <= 0;
            end
            if (sending && req_ready_i) begin
                sending <= 0;
                waiting <= 1;
            end
            // A result can complete and its successor can start at this same
            // edge. If the request is stalled, capture every exposed field.
            if (launch) begin
                owner_pc <= candidate_pc;
                owner_prediction <= predicted_next_i;
                poison <= 0;
                local_fault <= candidate_fault;
                sending <= !candidate_fault && !req_ready_i;
                waiting <= candidate_fault || req_ready_i;
            end
            // Never retract an exposed request: accept then discard its response.
            if (flush_i && (sending || waiting) && !launch) poison <= 1;
        end
    end
endmodule
