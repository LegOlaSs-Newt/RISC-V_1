/*
 * 模块说明：同步 DRM 多拍事务适配。
 * 来源说明：本项目新增。
 * 主要改动：接受一次整行读命令后，按字地址连续返回八拍；保持响应直到 ready，末拍携带 last。
 * 关键约束：写响应表示后端写已完成；读数据暂停和错误不能改变 owner。命令数、有效拍与占用周期分别统计。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// Single-outstanding 32-bit synchronous memory adapter. A line read is one
// command followed by eight beats; accepting a beat can issue the next read.
// The memory output register holds its data whenever read_en_o is low.
module drm_transaction (
    input wire clk,
    rst,
    input wire cmd_valid_i,
    cmd_write_i,
    input wire [31:0] cmd_addr_i,
    cmd_wdata_i,
    input wire [3:0] cmd_wstrb_i,
    cmd_beats_i,
    output wire cmd_ready_o,
    output wire rsp_valid_o,
    rsp_error_o,
    rsp_last_o,
    output wire [31:0] rsp_data_o,
    input wire rsp_ready_i,
    output wire [31:0] mem_addr_o,
    mem_wdata_o,
    output wire [3:0] mem_wstrb_o,
    output wire mem_read_en_o,
    mem_write_en_o,
    mem_ram_o,
    input wire [31:0] mem_rdata_i,
    output reg [63:0] commands_o,
    read_beats_o,
    write_beats_o,
    output reg [63:0] stalls_o,
    active_cycles_o,
    line_commands_o
);
    reg busy, writing, issued, response_valid, response_last, error;
    reg [31:0] next_addr, write_data;
    reg [3:0] write_mask, remaining;
    wire region_ok = cmd_addr_i < 32'h4000 ||
        (cmd_addr_i >= 32'h10000000 && cmd_addr_i < 32'h10004000);
    wire
        shape_ok = (cmd_beats_i == 1 || (!cmd_write_i && cmd_beats_i == 8 && cmd_addr_i[4:0] == 0));
    wire first_read = cmd_valid_i && cmd_ready_o && !cmd_write_i && region_ok && shape_ok;
    wire first_write = cmd_valid_i && cmd_ready_o && cmd_write_i && region_ok && shape_ok;
    wire consume = response_valid && rsp_ready_i;
    wire read_issue = busy && !writing && !error && remaining != 0 &&
        (!response_valid || rsp_ready_i);
    wire write_issue = busy && writing && !error && !issued;
    assign cmd_ready_o = rst && !busy;
    assign rsp_valid_o = rst && response_valid;
    assign rsp_last_o = response_last;
    assign rsp_error_o = error;
    assign rsp_data_o = (writing || error) ? 32'b0 : mem_rdata_i;
    // The command payload is stable at its accepting edge, so it can drive
    // that edge's synchronous RAM operation directly. No extra launch clock.
    assign mem_addr_o = (first_read || first_write) ? {cmd_addr_i[31:2], 2'b00} : next_addr;
    assign mem_wdata_o = first_write ? cmd_wdata_i : write_data;
    assign mem_wstrb_o = first_write ? cmd_wstrb_i : write_mask;
    assign mem_read_en_o = rst && (read_issue || first_read);
    assign mem_write_en_o = rst && (write_issue || first_write);
    assign mem_ram_o = mem_addr_o[28];
    always @(posedge clk) begin
        if (!rst) begin
            busy <= 0;
            writing <= 0;
            issued <= 0;
            response_valid <= 0;
            response_last <= 0;
            error <= 0;
            next_addr <= 0;
            write_data <= 0;
            write_mask <= 0;
            remaining <= 0;
            commands_o <= 0;
            read_beats_o <= 0;
            write_beats_o <= 0;
            stalls_o <= 0;
            active_cycles_o <= 0;
            line_commands_o <= 0;
        end else begin
            if (busy || (cmd_valid_i && cmd_ready_o)) active_cycles_o <= active_cycles_o + 1'b1;
            if (response_valid && !rsp_ready_i) stalls_o <= stalls_o + 1'b1;
            if (cmd_valid_i && cmd_ready_o) begin
                busy <= 1;
                writing <= cmd_write_i;
                issued <= first_write;
                next_addr <= first_read ? cmd_addr_i + 4 : {cmd_addr_i[31:2], 2'b00};
                write_data <= cmd_wdata_i;
                write_mask <= cmd_wstrb_i;
                remaining <= first_read ? cmd_beats_i - 1'b1 : cmd_beats_i;
                error <= !region_ok || !shape_ok;
                response_valid <= 1;
                response_last <= !region_ok || !shape_ok || cmd_beats_i == 1;
                commands_o <= commands_o + 1'b1;
                if (cmd_beats_i == 8 && !cmd_write_i) line_commands_o <= line_commands_o + 1'b1;
                if (first_write) write_beats_o <= write_beats_o + 1'b1;
            end
            if (consume) begin
                response_valid <= 0;
                if (!error && !writing) read_beats_o <= read_beats_o + 1'b1;
                if (response_last) busy <= 0;
            end
            if (read_issue) begin
                response_valid <= 1;
                response_last <= remaining == 1;
                remaining <= remaining - 1'b1;
                next_addr <= next_addr + 4;
            end
            if (write_issue) begin
                issued <= 1;
                response_valid <= 1;
                response_last <= 1;
                write_beats_o <= write_beats_o + 1'b1;
            end
        end
    end
endmodule
