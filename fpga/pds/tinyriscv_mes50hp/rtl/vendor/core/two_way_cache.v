/*
 * 模块说明：两路组相联 Cache。
 * 来源说明：本项目新增，构建于 TinyRISC-V SoC 等待接口。
 * 主要改动：每个 I/D 实例 2 KiB，32 组、每行八字；地址 tag 为 [31:10]、组为 [9:5]、字为 [4:2]。同步数据阵列由 DRM 实现，复位只清有效位。
 * 关键约束：读命中或完整补行后更新 LRU；写直达且不写分配，后端完成后才确认。提前查询只读，不能接受事务；取消、失效或归属不匹配时回退普通请求。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 2 KiB, two ways, 32 sets, eight words/line. Blocking, synchronous data
// lookup. D writes are write-through/no-write-allocate and acknowledge only
// after the backend completes. READ_ONLY selects the instruction instance.
module two_way_cache #(
    parameter ENABLE = 1,
    READ_ONLY = 0,
    EARLY_LOOKUP = 0
) (
    input wire clk,
    rst,
    invalidate_i,
    input wire req_valid_i,
    req_write_i,
    req_cacheable_i,
    input wire [31:0] req_addr_i,
    req_wdata_i,
    input wire [3:0] req_wstrb_i,
    output wire req_ready_o,
    output wire rsp_valid_o,
    rsp_error_o,
    output wire [31:0] rsp_data_o,
    input wire rsp_ready_i,
    // Read-only ID lookup. It never accepts an architectural transaction.
    input wire lookup_valid_i,
    lookup_cancel_i,
    lookup_block_i,
    lookup_use_i,
    input wire [31:0] lookup_addr_i,
    output wire lookup_ready_o,
    lookup_result_valid_o,
    lookup_hit_o,
    output wire [31:0] lookup_result_addr_o,
    lookup_data_o,
    output wire cmd_valid_o,
    cmd_write_o,
    output wire [31:0] cmd_addr_o,
    cmd_wdata_o,
    output wire [3:0] cmd_wstrb_o,
    cmd_beats_o,
    input wire cmd_ready_i,
    input wire mem_valid_i,
    mem_error_i,
    mem_last_i,
    input wire [31:0] mem_data_i,
    output wire mem_ready_o,
    output reg [63:0] read_hits_o,
    read_misses_o,
    write_hits_o,
    output reg [63:0] write_misses_o,
    wait_cycles_o,
    uncached_o
);
    localparam IDLE = 0, LOOKUP = 1, COMMAND = 2, MEMORY = 3, RESPONSE = 4;
    reg [ 2:0] state;
    reg [31:0] data0 [0:255]  /* synthesis syn_ramstyle="block_ram" */;
    reg [31:0] data1 [0:255]  /* synthesis syn_ramstyle="block_ram" */;
    reg [21:0] tag0[0:31], tag1[0:31];
    reg [31:0] valid0, valid1, lru;
    reg [31:0] q0, q1;
    reg [31:0] address, write_data, result;
    reg [3:0] write_mask;
    reg writing, cached, hit, way, victim, poison, refill_error, result_error;
    reg [2:0] beat;
    reg lookup_result_valid, lookup_saved_hit, lookup_saved_way;
    reg [31:0] lookup_saved_address;
    wire [4:0] set_index = address[9:5];
    wire [7:0] word_index = address[9:2];
    wire request_hit0 = valid0[req_addr_i[9:5]] && tag0[req_addr_i[9:5]] == req_addr_i[31:10];
    wire request_hit1 = valid1[req_addr_i[9:5]] && tag1[req_addr_i[9:5]] == req_addr_i[31:10];
    wire request_cached = ENABLE && req_cacheable_i;
    wire request_hit = request_cached && !invalidate_i && (request_hit0 || request_hit1);
    wire read_hit_response = state == LOOKUP && !writing && hit;
    wire same_set_turnover = READ_ONLY && read_hit_response && rsp_ready_i &&
        req_addr_i[9:5] == set_index;
    wire request_victim = !valid0[req_addr_i[9:5]] ? 1'b0 :
        !valid1[req_addr_i[9:5]] ? 1'b1 : same_set_turnover ? !way : lru[req_addr_i[9:5]];
    wire fill = cached && !writing && !hit;
    wire request_fill = request_cached && !req_write_i && !request_hit;
    wire request_memory = !(READ_ONLY && req_write_i) && (!request_hit || req_write_i);
    wire direct_command = req_valid_i && req_ready_o && request_memory;
    wire final_response = state == MEMORY && mem_valid_i && mem_last_i;
    assign req_ready_o = rst && (state == IDLE || (READ_ONLY && read_hit_response && rsp_ready_i));
    assign rsp_valid_o = rst && (state == RESPONSE || read_hit_response || final_response);
    assign rsp_error_o = state == RESPONSE ? result_error :
        final_response && (refill_error || mem_error_i || (fill && beat != 7));
    assign rsp_data_o = read_hit_response ? (way ? q1 : q0) :
        final_response && !writing && (!fill || beat == address[4:2]) ? mem_data_i : result;
    assign cmd_valid_o = rst && (state == COMMAND || direct_command);
    assign cmd_write_o = direct_command ? req_write_i : writing;
    assign cmd_addr_o = direct_command ?
        (request_fill ? {req_addr_i[31:5], 5'b0} : {req_addr_i[31:2], 2'b0}) :
        fill ? {address[31:5], 5'b0} : {address[31:2], 2'b0};
    assign cmd_wdata_o = direct_command ? req_wdata_i : write_data;
    assign cmd_wstrb_o = direct_command ? req_wstrb_i : write_mask;
    assign cmd_beats_o = (direct_command ? request_fill : fill) ? 4'd8 : 4'd1;
    assign mem_ready_o = rst && state == MEMORY;
    wire fill_write = state == MEMORY && mem_valid_i && mem_ready_o && !mem_error_i && fill;
    wire store_write = state == MEMORY && mem_valid_i && mem_ready_o && !mem_error_i &&
        !READ_ONLY && writing && hit && mem_last_i && !refill_error && !poison && !invalidate_i;
    // Host-valid/global-invalidate block the result independently of bus
    // arbitration; no feedback through a suppressed normal CPU request.
    assign lookup_ready_o = rst && ENABLE && EARLY_LOOKUP && !READ_ONLY && state == IDLE &&
        !req_valid_i && !invalidate_i && !lookup_block_i && !lookup_cancel_i;
    wire lookup_fire = lookup_valid_i && lookup_ready_o;
    wire lookup_now_hit0 = valid0[lookup_addr_i[9:5]] &&
        tag0[lookup_addr_i[9:5]] == lookup_addr_i[31:10];
    wire lookup_now_hit1 = valid1[lookup_addr_i[9:5]] &&
        tag1[lookup_addr_i[9:5]] == lookup_addr_i[31:10];
    assign lookup_result_valid_o = EARLY_LOOKUP && ENABLE && lookup_result_valid && state == IDLE &&
        !lookup_block_i;
    assign lookup_hit_o = lookup_result_valid_o && lookup_saved_hit &&
        (lookup_saved_way ? valid1[lookup_saved_address[9:5]] && tag1[lookup_saved_address[9:5]] ==
         lookup_saved_address[31:10] : valid0[lookup_saved_address[9:5]] &&
         tag0[lookup_saved_address[9:5]] == lookup_saved_address[31:10]);
    assign lookup_result_addr_o = lookup_saved_address;
    assign lookup_data_o = lookup_saved_way ? q1 : q0;
    always @(posedge clk) begin
        if (!rst || !EARLY_LOOKUP || invalidate_i || lookup_cancel_i) begin
            lookup_result_valid <= 0;
            lookup_saved_hit <= 0;
            lookup_saved_way <= 0;
            lookup_saved_address <= 0;
        end else begin
            lookup_result_valid <= lookup_fire;
            if (lookup_fire) begin
                lookup_saved_address <= lookup_addr_i;
                lookup_saved_hit <= lookup_now_hit0 || lookup_now_hit1;
                lookup_saved_way <= lookup_now_hit1;
            end
        end
    end
    wire [7:0] array_write_address = fill_write ? {set_index, beat} : word_index;
    wire [31:0] array_write_data = fill_write ? mem_data_i : write_data;
    wire [3:0] array_write_mask = fill_write ? 4'b1111 : write_mask;
    wire array_write_way = fill_write ? victim : way;
    wire normal_array_read = req_valid_i && req_ready_o;
    wire array_read_enable = normal_array_read || lookup_fire;
    wire [7:0] array_read_address = normal_array_read ? req_addr_i[9:2] : lookup_addr_i[9:2];
    // One read address and one muxed write address per way. Keeping refill and
    // store as separate array write ports prevents ADS from inferring an SDP RAM.
    always @(posedge clk) begin
        if (array_read_enable) begin
            q0 <= data0[array_read_address];
            q1 <= data1[array_read_address];
        end
    end
    generate
        if (READ_ONLY) begin : instruction_data_write
            always @(posedge clk)
                if (fill_write) begin
                    if (array_write_way) data1[array_write_address] <= array_write_data;
                    else data0[array_write_address] <= array_write_data;
                end
        end else begin : byte_data_write
            always @(posedge clk)
                if (fill_write || store_write) begin
                    if (array_write_way) begin
                        if (array_write_mask[0])
                            data1[array_write_address][7:0] <= array_write_data[7:0];
                        if (array_write_mask[1])
                            data1[array_write_address][15:8] <= array_write_data[15:8];
                        if (array_write_mask[2])
                            data1[array_write_address][23:16] <= array_write_data[23:16];
                        if (array_write_mask[3])
                            data1[array_write_address][31:24] <= array_write_data[31:24];
                    end else begin
                        if (array_write_mask[0])
                            data0[array_write_address][7:0] <= array_write_data[7:0];
                        if (array_write_mask[1])
                            data0[array_write_address][15:8] <= array_write_data[15:8];
                        if (array_write_mask[2])
                            data0[array_write_address][23:16] <= array_write_data[23:16];
                        if (array_write_mask[3])
                            data0[array_write_address][31:24] <= array_write_data[31:24];
                    end
                end
        end
    endgenerate
    always @(posedge clk) begin
        if (!rst) begin
            state <= IDLE;
            valid0 <= 0;
            valid1 <= 0;
            lru <= 0;
            address <= 0;
            write_data <= 0;
            write_mask <= 0;
            writing <= 0;
            cached <= 0;
            hit <= 0;
            way <= 0;
            victim <= 0;
            poison <= 0;
            refill_error <= 0;
            result_error <= 0;
            result <= 0;
            beat <= 0;
            read_hits_o <= 0;
            read_misses_o <= 0;
            write_hits_o <= 0;
            write_misses_o <= 0;
            wait_cycles_o <= 0;
            uncached_o <= 0;
        end else begin
            if (state != IDLE) wait_cycles_o <= wait_cycles_o + 1'b1;
            case (state)
                IDLE: begin
                end
                LOOKUP: begin
                    if (READ_ONLY && writing) begin
                        result <= 0;
                        result_error <= 1;
                        state <= RESPONSE;
                    end else if (read_hit_response) begin
                        if (rsp_ready_i) begin
                            if (!poison && !invalidate_i) lru[set_index] <= !way;
                            state <= IDLE;
                        end
                    end else state <= COMMAND;
                end
                COMMAND:  if (cmd_ready_i) state <= MEMORY;
                MEMORY:
                if (mem_valid_i && mem_ready_o) begin
                    if (mem_error_i) refill_error <= 1;
                    if (!writing && (!fill || beat == address[4:2])) result <= mem_data_i;
                    if (mem_last_i) begin
                        result_error <= refill_error || mem_error_i || (fill && beat != 7);
                        if (fill && !refill_error && !mem_error_i && beat == 7 && !poison &&
                            !invalidate_i) begin
                            if (victim) begin
                                tag1[set_index]   <= address[31:10];
                                valid1[set_index] <= 1;
                            end else begin
                                tag0[set_index]   <= address[31:10];
                                valid0[set_index] <= 1;
                            end
                            lru[set_index] <= !victim;
                        end
                        if (writing && hit) begin
                            if (refill_error || mem_error_i) begin
                                if (way) valid1[set_index] <= 0;
                                else valid0[set_index] <= 0;
                            end else if (!poison && !invalidate_i) lru[set_index] <= !way;
                        end
                        // Forward the actual final completion to the CPU. If
                        // it cannot accept, retain the same data/error in the
                        // existing response register on the next cycle.
                        state <= rsp_ready_i ? IDLE : RESPONSE;
                    end else beat <= beat + 1'b1;
                end
                RESPONSE: if (rsp_ready_i) state <= IDLE;
                default:  state <= IDLE;
            endcase
            // The old hit's data is consumed before this clock reads the new
            // address. No refill/store array write occurs in LOOKUP, so this
            // preserves the synchronous SDP collision rules.
            if (EARLY_LOOKUP && lookup_use_i && lookup_hit_o) begin
                read_hits_o <= read_hits_o + 1'b1;
                lru[lookup_saved_address[9:5]] <= !lookup_saved_way;
            end
            if (req_valid_i && req_ready_o) begin
                address <= req_addr_i;
                write_data <= req_wdata_i;
                write_mask <= req_wstrb_i;
                writing <= req_write_i;
                cached <= request_cached;
                hit <= request_hit;
                way <= request_hit1;
                victim <= request_victim;
                poison <= invalidate_i;
                refill_error <= 0;
                result_error <= 0;
                beat <= 0;
                if (!request_cached) uncached_o <= uncached_o + 1'b1;
                else if (req_write_i) begin
                    if (request_hit) write_hits_o <= write_hits_o + 1'b1;
                    else write_misses_o <= write_misses_o + 1'b1;
                end else begin
                    if (request_hit) read_hits_o <= read_hits_o + 1'b1;
                    else begin
                        read_misses_o <= read_misses_o + 1'b1;
                        if (request_victim) valid1[req_addr_i[9:5]] <= 0;
                        else valid0[req_addr_i[9:5]] <= 0;
                    end
                end
                state <= request_memory ? (cmd_ready_i ? MEMORY : COMMAND) : LOOKUP;
            end
            if (invalidate_i) begin
                valid0 <= 0;
                valid1 <= 0;
                if (state != IDLE) poison <= 1;
            end
        end
    end
endmodule
