/*
 * 模块说明：动态分支预测与返回栈。
 * 来源说明：本项目新增。
 * 主要改动：带标签的 128 项 BTB 配合二位饱和方向计数器和八级 RAS；目标 PC 与预测取指配对。
 * 关键约束：只使用有效提交的分支训练，clear 优先于同拍训练。RAS 在提交时更新，返回提示不匹配的间接跳转使用 BTB。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Experimental configurable direct-mapped tagged BTB; 128 entries here.
// Cold entries are invalid. Allocation starts weakly in the resolved direction.
// Only committed valid resolutions train; clear wins over simultaneous update.
module branch_predictor #(
    parameter integer ENABLE = 1,
    parameter integer INDEX_BITS = 7,
    parameter integer RAS_ENABLE = 1
) (
    input wire clk,
    rst,
    clear_i,
    input wire [31:0] fetch_pc_i,
    output wire [31:0] predicted_next_o,
    output wire hit_o,
    taken_o,
    input wire resolve_i,
    input wire [31:0] resolve_pc_i,
    target_i,
    input wire [31:0] resolve_inst_i,
    input wire conditional_i,
    jal_i,
    taken_i
);
    localparam integer ENTRIES = 1 << INDEX_BITS;
    reg [ENTRIES-1:0] valid;
    reg [29-INDEX_BITS:0] tag[0:ENTRIES-1];
    reg [31:0] target[0:ENTRIES-1];
    reg [1:0] counter[0:ENTRIES-1];
    reg [ENTRIES-1:0] unconditional;
    reg [ENTRIES-1:0] return_entry;
    reg [31:0] ras[0:7];
    reg [3:0] ras_count;
    integer n;
    wire rd_link = resolve_inst_i[11:7] == 1 || resolve_inst_i[11:7] == 5;
    wire rs1_link = resolve_inst_i[19:15] == 1 || resolve_inst_i[19:15] == 5;
    wire jalr = resolve_inst_i[6:0] == 7'h67;
    wire call_event = (resolve_inst_i[6:0] == 7'h6f || jalr) && rd_link;
    // Standard zero-offset x1/x5 return hints; other indirects use the BTB.
    wire return_event = jalr && rs1_link && resolve_inst_i[31:20] == 0 &&
        (!rd_link || resolve_inst_i[11:7] != resolve_inst_i[19:15]);
    wire [INDEX_BITS-1:0] fi = fetch_pc_i[INDEX_BITS+1:2];
    wire [INDEX_BITS-1:0] ri = resolve_pc_i[INDEX_BITS+1:2];
    wire same_entry = valid[ri] && tag[ri] == resolve_pc_i[31:INDEX_BITS+2] &&
        unconditional[ri] == jal_i;
    assign hit_o = ENABLE != 0 && valid[fi] && tag[fi] == fetch_pc_i[31:INDEX_BITS+2];
    assign taken_o = hit_o && (unconditional[fi] || counter[fi][1]);
    assign predicted_next_o = taken_o ? (RAS_ENABLE && return_entry[fi] && ras_count != 0 ? ras[0] :
                                         target[fi]) : fetch_pc_i + 32'd4;
    always @(posedge clk) begin
        if (!rst || clear_i || ENABLE == 0) begin
            valid <= 0;
            unconditional <= 0;
            return_entry <= 0;
            ras_count <= 0;
        end else if (resolve_i) begin
            // Only committed instructions update the stack, so redirects do
            // not require speculative push/pop rollback. Overflow drops oldest.
            if (RAS_ENABLE) begin
                if (call_event && return_event) begin
                    ras[0] <= resolve_pc_i + 32'd4;
                    if (ras_count == 0) ras_count <= 1;
                end else if (call_event) begin
                    for (n = 7; n > 0; n = n - 1) ras[n] <= ras[n-1];
                    ras[0] <= resolve_pc_i + 32'd4;
                    if (ras_count < 8) ras_count <= ras_count + 1'b1;
                end else if (return_event && ras_count != 0) begin
                    for (n = 0; n < 7; n = n + 1) ras[n] <= ras[n+1];
                    ras_count <= ras_count - 1'b1;
                end
            end
            if (conditional_i || jal_i) begin
                valid[ri] <= 1'b1;
                tag[ri] <= resolve_pc_i[31:INDEX_BITS+2];
                target[ri] <= target_i;
                unconditional[ri] <= jal_i;
                return_entry[ri] <= return_event;
                if (!same_entry) counter[ri] <= taken_i ? 2'b10 : 2'b01;
                else if (taken_i && counter[ri] != 2'b11) counter[ri] <= counter[ri] + 1'b1;
                else if (!taken_i && counter[ri] != 2'b00) counter[ri] <= counter[ri] - 1'b1;
            end else if (valid[ri] && tag[ri] == resolve_pc_i[31:INDEX_BITS+2]) begin
                // A replaced/self-modified non-branch must not keep a stale BTB.
                valid[ri] <= 1'b0;
            end
        end
    end
endmodule

