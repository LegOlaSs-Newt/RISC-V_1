/*
 * 模块说明：I D Cache 与主机事务仲裁。
 * 来源说明：本项目新增，连接 TinyRISC-V CPU 和片内存储及外设。
 * 主要改动：I、D 和下载调试主机采用事务锁定的轮询仲裁。接受命令时锁存 owner，直到末拍被消费才释放。
 * 关键约束：MMIO 不缓存，仅在接受命令时产生一次副作用；主机写入失效相关缓存状态。反压时保留数据和 owner，错误跟随同一事务返回。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// V3: independent blocking I/D caches and a transaction-locked round-robin bus.
// External arrays are synchronous; MMIO is sampled/written only at command fire.
module memory_system #(
    parameter CACHE_ENABLE = 1,
    EARLY_D_LOOKUP = 0
) (
    input wire clk,
    rst,
    fence_i_i,
    invalidate_all_i,
    input wire i_req_valid_i,
    input wire [31:0] i_req_addr_i,
    output wire i_req_ready_o,
    i_rsp_valid_o,
    i_rsp_error_o,
    output wire [31:0] i_rsp_data_o,
    input wire i_rsp_ready_i,
    input wire d_req_valid_i,
    d_req_write_i,
    input wire [31:0] d_req_addr_i,
    d_req_wdata_i,
    input wire [3:0] d_req_wstrb_i,
    output wire d_req_ready_o,
    d_rsp_valid_o,
    d_rsp_error_o,
    output wire [31:0] d_rsp_data_o,
    input wire d_rsp_ready_i,
    input wire d_lookup_valid_i,
    d_lookup_cancel_i,
    d_lookup_use_i,
    input wire [31:0] d_lookup_addr_i,
    output wire d_lookup_ready_o,
    d_lookup_result_valid_o,
    d_lookup_hit_o,
    output wire [31:0] d_lookup_result_addr_o,
    d_lookup_data_o,
    input wire h_req_valid_i,
    h_req_write_i,
    input wire [31:0] h_req_addr_i,
    h_req_wdata_i,
    output wire h_req_ready_o,
    h_rsp_valid_o,
    h_rsp_error_o,
    output wire [31:0] h_rsp_data_o,
    input wire h_rsp_ready_i,
    output wire [31:0] mem_addr_o,
    mem_wdata_o,
    output wire [3:0] mem_wstrb_o,
    output wire mem_read_en_o,
    mem_write_en_o,
    mem_ram_o,
    input wire [31:0] mem_rdata_i,
    output wire [31:0] mmio_addr_o,
    mmio_wdata_o,
    output wire [3:0] mmio_select_o,
    output wire mmio_write_en_o,
    input wire [31:0] timer_rdata_i,
    uart_rdata_i,
    gpio_rdata_i,
    spi_rdata_i,
    output wire idle_o
);
    wire [1:0] cv, cw, cq, mr;
    wire [31:0] ca0, ca1, cd0, cd1;
    wire [3:0] cs0, cs1, cn0, cn1;
    wire [63:0] ih, im, iw, dh, dm, dwh, dwm, dwait, uncached;
    reg busy, selected_mmio, owner_write;
    reg [1:0] owner, last, select;
    wire request_valid = select == 0 ? cv[0] : select == 1 ? cv[1] : h_req_valid_i;
    wire request_write = select == 0 ? cw[0] : select == 1 ? cw[1] : h_req_write_i;
    wire [31:0] address = select == 0 ? ca0 : select == 1 ? ca1 : h_req_addr_i;
    wire [31:0] write_data = select == 0 ? cd0 : select == 1 ? cd1 : h_req_wdata_i;
    wire [3:0] write_mask = select == 0 ? cs0 : select == 1 ? cs1 : 4'b1111;
    wire [3:0] length = select == 0 ? cn0 : select == 1 ? cn1 : 4'd1;
    wire memory_address = address < 32'h4000 || (address >= 32'h10000000 && address < 32'h10004000);
    wire backend_valid, backend_error, backend_last, backend_ready;
    wire [31:0] backend_data;
    wire ram_valid, ram_error, ram_last, ram_ready;
    wire [31:0] ram_data;
    reg peripheral_valid, peripheral_error;
    reg [31:0] peripheral_data;
    wire take_command = rst && !busy && request_valid &&
        (memory_address ? ram_ready : !peripheral_valid);
    wire host_write = take_command && select == 2 && request_write;
    wire cached_data = d_req_addr_i < 32'h4000 ||
        (d_req_addr_i >= 32'h10000000 && d_req_addr_i < 32'h10004000);
    // A newly presented CPU request must not feed host_write -> invalidate ->
    // hit -> D command -> arbitration. Older accepted D transactions still
    // drain normally. Once any backend transaction is busy, a D request may
    // enter/queue again so continuous host traffic cannot bypass round-robin.
    wire d_cache_ready;
    wire d_front_admit = !h_req_valid_i || busy;
    assign d_req_ready_o = d_cache_ready && d_front_admit;
    // Idle is intrinsic state, not host-dependent front-door readiness:
    // SoC derives host_grant from idle, so using d_req_ready here feeds back.
    assign idle_o = !busy && i_req_ready_o && d_cache_ready && !i_req_valid_i && !d_req_valid_i;
    always @* begin
        case (last)
            0: select = cv[1] ? 1 : h_req_valid_i ? 2 : 0;
            1: select = h_req_valid_i ? 2 : cv[0] ? 0 : 1;
            default: select = cv[0] ? 0 : cv[1] ? 1 : 2;
        endcase
    end
    assign cq[0] = rst && !busy && select == 0 && (memory_address ? ram_ready : !peripheral_valid);
    assign cq[1] = rst && !busy && select == 1 && (memory_address ? ram_ready : !peripheral_valid);
    assign h_req_ready_o = rst && !busy && select == 2 &&
        (memory_address ? ram_ready : !peripheral_valid);
    assign backend_valid = selected_mmio ? peripheral_valid : ram_valid;
    assign backend_error = selected_mmio ? peripheral_error : ram_error;
    assign backend_last = selected_mmio ? 1'b1 : ram_last;
    assign backend_data = selected_mmio ? peripheral_data : ram_data;
    assign backend_ready = busy && (owner == 0 ? mr[0] : owner == 1 ? mr[1] : h_rsp_ready_i);
    assign h_rsp_valid_o = busy && owner == 2 && backend_valid;
    assign h_rsp_error_o = backend_error;
    assign h_rsp_data_o = backend_data;
    two_way_cache #(
        .ENABLE(CACHE_ENABLE),
        .READ_ONLY(1)
    ) u_icache (
        .clk(clk),
        .rst(rst),
        .invalidate_i(fence_i_i || invalidate_all_i || host_write),
        .req_valid_i(i_req_valid_i),
        .req_ready_o(i_req_ready_o),
        .req_write_i(1'b0),
        .req_cacheable_i(1'b1),
        .req_addr_i(i_req_addr_i),
        .req_wdata_i(32'b0),
        .req_wstrb_i(4'b0),
        .rsp_valid_o(i_rsp_valid_o),
        .rsp_ready_i(i_rsp_ready_i),
        .rsp_error_o(i_rsp_error_o),
        .rsp_data_o(i_rsp_data_o),
        .cmd_valid_o(cv[0]),
        .cmd_ready_i(cq[0]),
        .cmd_write_o(cw[0]),
        .cmd_addr_o(ca0),
        .cmd_wdata_o(cd0),
        .cmd_wstrb_o(cs0),
        .cmd_beats_o(cn0),
        .mem_valid_i(busy && owner == 0 && backend_valid),
        .mem_ready_o(mr[0]),
        .mem_error_i(backend_error),
        .mem_last_i(backend_last),
        .mem_data_i(backend_data),
        .read_hits_o(ih),
        .read_misses_o(im),
        .write_hits_o(),
        .write_misses_o(),
        .wait_cycles_o(iw),
        .uncached_o()
    );
    two_way_cache #(
        .ENABLE(CACHE_ENABLE),
        .EARLY_LOOKUP(EARLY_D_LOOKUP)
    ) u_dcache (
        .clk(clk),
        .rst(rst),
        .invalidate_i(invalidate_all_i || host_write),
        .req_valid_i(d_req_valid_i && d_front_admit),
        .req_ready_o(d_cache_ready),
        .req_write_i(d_req_write_i),
        .req_cacheable_i(cached_data),
        .req_addr_i(d_req_addr_i),
        .req_wdata_i(d_req_wdata_i),
        .req_wstrb_i(d_req_wstrb_i),
        .rsp_valid_o(d_rsp_valid_o),
        .rsp_ready_i(d_rsp_ready_i),
        .rsp_error_o(d_rsp_error_o),
        .rsp_data_o(d_rsp_data_o),
        .lookup_valid_i(d_lookup_valid_i),
        .lookup_addr_i(d_lookup_addr_i),
        .lookup_ready_o(d_lookup_ready_o),
        .lookup_cancel_i(d_lookup_cancel_i),
        .lookup_block_i(invalidate_all_i || h_req_valid_i),
        .lookup_result_valid_o(d_lookup_result_valid_o),
        .lookup_hit_o(d_lookup_hit_o),
        .lookup_result_addr_o(d_lookup_result_addr_o),
        .lookup_data_o(d_lookup_data_o),
        .lookup_use_i(d_lookup_use_i),
        .cmd_valid_o(cv[1]),
        .cmd_ready_i(cq[1]),
        .cmd_write_o(cw[1]),
        .cmd_addr_o(ca1),
        .cmd_wdata_o(cd1),
        .cmd_wstrb_o(cs1),
        .cmd_beats_o(cn1),
        .mem_valid_i(busy && owner == 1 && backend_valid),
        .mem_ready_o(mr[1]),
        .mem_error_i(backend_error),
        .mem_last_i(backend_last),
        .mem_data_i(backend_data),
        .read_hits_o(dh),
        .read_misses_o(dm),
        .write_hits_o(dwh),
        .write_misses_o(dwm),
        .wait_cycles_o(dwait),
        .uncached_o(uncached)
    );
    drm_transaction u_drm_transaction (
        .clk(clk),
        .rst(rst),
        .cmd_valid_i(!busy && request_valid && memory_address),
        .cmd_ready_o(ram_ready),
        .cmd_write_i(request_write),
        .cmd_addr_i(address),
        .cmd_wdata_i(write_data),
        .cmd_wstrb_i(write_mask),
        .cmd_beats_i(length),
        .rsp_valid_o(ram_valid),
        .rsp_ready_i(backend_ready && !selected_mmio),
        .rsp_error_o(ram_error),
        .rsp_last_o(ram_last),
        .rsp_data_o(ram_data),
        .mem_addr_o(mem_addr_o),
        .mem_wdata_o(mem_wdata_o),
        .mem_wstrb_o(mem_wstrb_o),
        .mem_read_en_o(mem_read_en_o),
        .mem_write_en_o(mem_write_en_o),
        .mem_ram_o(mem_ram_o),
        .mem_rdata_i(mem_rdata_i),
        .commands_o(),
        .read_beats_o(),
        .write_beats_o(),
        .stalls_o(),
        .active_cycles_o(),
        .line_commands_o()
    );
    // Exact whitelist, including read-only performance counters.
    wire peripheral_address = address == 32'h20000000 || address == 32'h20000004 ||
        address == 32'h20000008 || address == 32'h2000000c || address == 32'h30000000 ||
        address == 32'h30000004 || address == 32'h30000008 || address == 32'h3000000c ||
        address == 32'h30000010 || address == 32'h40000000 || address == 32'h40000004 ||
        address == 32'h50000000 || address == 32'h50000004 || address == 32'h50000008;
    wire stats_address = address >= 32'h60000000 && address < 32'h60000078 && address[1:0] == 0 &&
        !request_write;
    wire peripheral_ok = length == 1 && write_mask == 4'b1111 &&
        (peripheral_address || stats_address);
    assign mmio_addr_o = {4'b0, address[27:0]};
    assign mmio_wdata_o = write_data;
    assign mmio_select_o = address[31:28];
    assign mmio_write_en_o = take_command && !memory_address && peripheral_ok && request_write;
    reg [63:0] commands, read_beats, write_beats, response_stalls, active_cycles, line_commands;
    reg [63:0] statistic;
    always @* begin
        case (address[6:3])
            0: statistic = ih;
            1: statistic = im;
            2: statistic = dh;
            3: statistic = dm;
            4: statistic = iw;
            5: statistic = dwait;
            6: statistic = commands;
            7: statistic = read_beats;
            8: statistic = write_beats;
            9: statistic = response_stalls;
            10: statistic = active_cycles;
            11: statistic = line_commands;
            12: statistic = dwh;
            13: statistic = dwm;
            14: statistic = uncached;
            default: statistic = 0;
        endcase
    end
    wire [31:0] peripheral_read = stats_address ?
        (address[2] ? statistic[63:32] : statistic[31:0]) : address[31:28] == 2 ? timer_rdata_i :
        address[31:28] == 3 ? uart_rdata_i : address[31:28] == 4 ? gpio_rdata_i : spi_rdata_i;
    always @(posedge clk) begin
        if (!rst) begin
            busy <= 0;
            owner <= 0;
            last <= 2;
            selected_mmio <= 0;
            owner_write <= 0;
            peripheral_valid <= 0;
            peripheral_error <= 0;
            peripheral_data <= 0;
            commands <= 0;
            read_beats <= 0;
            write_beats <= 0;
            response_stalls <= 0;
            active_cycles <= 0;
            line_commands <= 0;
        end else begin
            if (take_command || busy) active_cycles <= active_cycles + 1'b1;
            if (take_command) begin
                busy <= 1;
                owner <= select;
                last <= select;
                selected_mmio <= !memory_address;
                owner_write <= request_write;
                commands <= commands + 1'b1;
                if (length == 8 && !request_write) line_commands <= line_commands + 1'b1;
                if (!memory_address) begin
                    peripheral_valid <= 1;
                    peripheral_error <= !peripheral_ok;
                    peripheral_data  <= peripheral_read;
                end
            end
            if (busy && backend_valid && !backend_ready) response_stalls <= response_stalls + 1'b1;
            if (busy && backend_valid && backend_ready) begin
                if (!backend_error) begin
                    if (owner_write) write_beats <= write_beats + 1'b1;
                    else read_beats <= read_beats + 1'b1;
                end
                if (backend_last) busy <= 0;
                if (selected_mmio) peripheral_valid <= 0;
            end
        end
    end
endmodule
