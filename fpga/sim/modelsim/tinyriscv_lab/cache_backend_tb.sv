/*
 * 模块说明：cache_backend_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：cache_backend_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module cache_backend_tb #(
    parameter integer CACHE = 1,
    READ_ONLY = 0
);
    reg clk = 0, rst = 0;
    always #5 clk = ~clk;
    reg direct = 1, invalidate = 0, inject = 0, inject_store = 0;
    reg cv = 0, cw = 0, cc = 1, cr = 0;
    reg [31:0] ca = 0, cd = 0;
    reg [3:0] cs = 0;
    wire cq, rv, re;
    wire [31:0] rd;
    wire bcv, bcw, bcq, brv, bre, brl, brr;
    wire [31:0] bca, bcd, brd;
    wire [3:0] bcs, bcn;
    reg xv = 0, xw = 0, xr = 0;
    reg [31:0] xa = 0, xd = 0;
    reg [3:0] xs = 0, xn = 1;
    wire [31:0] ma, md, qr, qp;
    wire [3:0] ms;
    wire mr, mw, ram_select;
    wire [63:0] commands, beats, writes, stalls, active, lines;
    wire [63:0] rh, rm, wh, wm, waits, bypasses;
    integer cycles = 0, i, single_cycles, burst_cycles, start_cycle;
    reg passed = 0;
    reg [63:0] saved_commands, saved_lines;
    reg [63:0] start_active, single_active, burst_active;
    reg held;
    reg [31:0] held_data;
    two_way_cache #(
        .ENABLE(CACHE),
        .READ_ONLY(READ_ONLY)
    ) cache (
        .clk(clk),
        .rst(rst),
        .invalidate_i(invalidate),
        .req_valid_i(cv),
        .req_write_i(cw),
        .req_cacheable_i(cc),
        .req_addr_i(ca),
        .req_wdata_i(cd),
        .req_wstrb_i(cs),
        .req_ready_o(cq),
        .rsp_valid_o(rv),
        .rsp_error_o(re),
        .rsp_data_o(rd),
        .rsp_ready_i(cr),
        .cmd_valid_o(bcv),
        .cmd_write_o(bcw),
        .cmd_addr_o(bca),
        .cmd_wdata_o(bcd),
        .cmd_wstrb_o(bcs),
        .cmd_beats_o(bcn),
        .cmd_ready_i(bcq && !direct),
        .mem_valid_i(brv && !direct),
        .mem_error_i(bre || (inject && cache.beat == 3) || inject_store),
        .mem_last_i(brl),
        .mem_data_i(brd),
        .mem_ready_o(brr),
        .read_hits_o(rh),
        .read_misses_o(rm),
        .write_hits_o(wh),
        .write_misses_o(wm),
        .wait_cycles_o(waits),
        .uncached_o(bypasses)
    );
    drm_transaction backend (
        .clk(clk),
        .rst(rst),
        .cmd_valid_i(direct ? xv : bcv),
        .cmd_ready_o(bcq),
        .cmd_write_i(direct ? xw : bcw),
        .cmd_addr_i(direct ? xa : bca),
        .cmd_wdata_i(direct ? xd : bcd),
        .cmd_wstrb_i(direct ? xs : bcs),
        .cmd_beats_i(direct ? xn : bcn),
        .rsp_valid_o(brv),
        .rsp_error_o(bre),
        .rsp_last_o(brl),
        .rsp_data_o(brd),
        .rsp_ready_i(direct ? xr : brr),
        .mem_addr_o(ma),
        .mem_wdata_o(md),
        .mem_wstrb_o(ms),
        .mem_read_en_o(mr),
        .mem_write_en_o(mw),
        .mem_ram_o(ram_select),
        .mem_rdata_i(ram_select ? qr : qp),
        .commands_o(commands),
        .read_beats_o(beats),
        .write_beats_o(writes),
        .stalls_o(stalls),
        .active_cycles_o(active),
        .line_commands_o(lines)
    );
    ram #(
        .SYNC_READ(1)
    ) uram (
        .clk(clk),
        .rst(rst),
        .we_i(mw && ram_select),
        .addr_i({18'b0, ma[13:0]}),
        .data_i(md),
        .read_en_i(mr && ram_select),
        .wstrb_i(ms),
        .data_o(qr)
    );
    rom #(
        .SYNC_READ(1)
    ) urom (
        .clk(clk),
        .rst(rst),
        .we_i(mw && !ram_select),
        .addr_i({18'b0, ma[13:0]}),
        .data_i(md),
        .read_en_i(mr && !ram_select),
        .wstrb_i(ms),
        .data_o(qp)
    );
    function automatic [31:0] initial_word(input integer index);
        initial_word = 32'ha5000000 + index;
    endfunction
    task automatic raw_read(input [31:0] addr, input integer count, input bit backpressure);
        integer n, ticks;
        reg [31:0] prior;
        reg prior_stalled;
        begin
            xa = addr;
            xn = count;
            xw = 0;
            xv = 1;
            xr = 0;
            do @(posedge clk); while (!bcq);
            @(negedge clk);
            xv = 0;
            n = 0;
            ticks = 0;
            prior_stalled = 0;
            while (n < count) begin
                xr = !backpressure || ticks % 4 != 1;
                @(posedge clk);
                if (prior_stalled && (!brv || brd !== prior))
                    $fatal(1, "backend response changed under backpressure");
                if (brv) begin
                    if (bre || brd !== initial_word(
                            (addr - 32'h10000000) / 4 + n
                        ) || brl !== (n == count - 1))
                        $fatal(
                            1,
                            "backend beat mismatch addr=%h n=%0d got=%h last=%b",
                            addr,
                            n,
                            brd,
                            brl
                        );
                    if (xr) n = n + 1;
                end
                prior_stalled = brv && !xr;
                prior = brd;
                @(negedge clk);
                ticks = ticks + 1;
            end
            xr = 0;
        end
    endtask
    task automatic access_word(input bit write_req, input [31:0] addr, input [31:0] data,
                               input [3:0] mask, input bit cacheable, input [31:0] expected,
                               input bit error_expected);
        reg [31:0] stable_data;
        integer k;
        begin
            @(negedge clk);
            cv = 1;
            cw = write_req;
            ca = addr;
            cd = data;
            cs = mask;
            cc = cacheable;
            cr = 0;
            do @(posedge clk); while (!cq);
            @(negedge clk);
            cv = 0;
            while (!rv) @(negedge clk);
            stable_data = rd;
            repeat (4) begin
                @(posedge clk);
                if (!rv || rd !== stable_data || re !== error_expected)
                    $fatal(1, "cache response not stable/correct under backpressure");
                @(negedge clk);
            end
            if (re !== error_expected || (!write_req && !error_expected && rd !== expected))
                $fatal(1, "cache result addr=%h got=%h expected=%h err=%b", addr, rd, expected, re);
            cr = 1;
            @(posedge clk);
            @(negedge clk);
            cr = 0;
        end
    endtask
    task automatic instruction_hit_stream;
        integer sent, received, begin_cycle, stream_cycles;
        reg [63:0] before_commands;
        begin
            sent = 0;
            received = 0;
            before_commands = commands;
            @(negedge clk);
            cv = 1;
            cw = 0;
            cc = 1;
            cr = 1;
            ca = 32'h10002000;
            begin_cycle = cycles;
            while (received < 64) begin
                @(posedge clk);
                if (received > 0 && !rv) $fatal(1, "bubble in resident instruction-hit stream");
                if (rv && cr) begin
                    if (re || rd !== initial_word(2048 + received))
                        $fatal(1, "hit stream owner/data mismatch");
                    received = received + 1;
                end
                if (cv && cq) sent = sent + 1;
                @(negedge clk);
                cv = sent < 64;
                ca = 32'h10002000 + sent * 4;
            end
            stream_cycles = cycles - begin_cycle;
            if (sent != 64 || commands != before_commands)
                $fatal(1, "resident stream unexpectedly missed or lost a request");
            $display(
                "ICACHE_HIT_STREAM_PASS requests=%0d responses=%0d cycles=%0d continuous_responses=64",
                sent, received, stream_cycles);
            cv = 0;
            cr = 0;
        end
    endtask
    always @(posedge clk) begin
        cycles = cycles + 1;
        if (cycles > 10000) $fatal(1, "timeout state=%0d", cache.state);
        if (rst && mr && mw) $fatal(1, "same memory read/write collision");
    end
    initial begin
        #1;
        for (i = 0; i < 4096; i = i + 1) begin
            uram._ram[i] = initial_word(i);
            urom._rom[i] = 32'h5a000000 + i;
        end
        repeat (4) @(negedge clk);
        rst = 1;
        start_cycle = cycles;
        saved_commands = commands;
        start_active = active;
        for (i = 0; i < 8; i = i + 1) raw_read(32'h10000000 + i * 4, 1, 0);
        single_cycles = cycles - start_cycle;
        single_active = active - start_active;
        if (commands - saved_commands != 8) $fatal(1, "single command count");
        start_cycle = cycles;
        saved_commands = commands;
        start_active = active;
        raw_read(32'h10000000, 8, 0);
        burst_cycles = cycles - start_cycle;
        burst_active = active - start_active;
        if (commands - saved_commands != 1 || burst_cycles >= single_cycles)
            $fatal(1, "burst has no measured benefit");
        raw_read(32'h10000020, 8, 1);
        if (stalls == 0) $fatal(1, "backend backpressure not exercised");
        if (single_cycles != single_active || burst_cycles != burst_active)
            $fatal(1, "driver inserted idle cycles into benchmark");
        $display(
            "DRM_BURST_COMPARE single_cycles=%0d burst_cycles=%0d single_active=%0d burst_active=%0d commands=8_vs_1 beats=8_vs_8",
            single_cycles, burst_cycles, single_active, burst_active);
        @(negedge clk);
        direct = 0;
        saved_lines = lines;
        access_word(0, 32'h10000000, 0, 0, 1, initial_word(0), 0);
        access_word(0, 32'h1000001c, 0, 0, 1, initial_word(7), 0);
        if (CACHE && lines - saved_lines != 1) $fatal(1, "cold fill/hit");
        access_word(0, 32'h10000400, 0, 0, 1, initial_word(256), 0);
        access_word(0, 32'h10000000, 0, 0, 1, initial_word(0), 0);
        if (CACHE && lines - saved_lines != 2) $fatal(1, "two ways not resident");
        access_word(0, 32'h10000800, 0, 0, 1, initial_word(512), 0);
        access_word(0, 32'h10000000, 0, 0, 1, initial_word(0), 0);
        if (CACHE && lines - saved_lines != 3) $fatal(1, "LRU kept wrong victim");
        access_word(0, 32'h10000400, 0, 0, 1, initial_word(256), 0);
        if (CACHE && lines - saved_lines != 4) $fatal(1, "LRU failed to evict B");
        if (!READ_ONLY) begin
            access_word(1, 32'h10000001, 32'h0000ab00, 4'b0010, 1, 0, 0);
            if (uram._ram[0] !== 32'ha500ab00)
                $fatal(1, "write-through ack preceded physical byte write");
            saved_commands = commands;
            access_word(0, 32'h10000000, 0, 0, 1, 32'ha500ab00, 0);
            if (CACHE && commands != saved_commands)
                $fatal(1, "write hit did not update cached byte");
            saved_lines = lines;
            access_word(1, 32'h10000c00, 32'hdeadbeef, 4'b1111, 1, 0, 0);
            if (lines != saved_lines) $fatal(1, "write miss allocated a line");
            access_word(0, 32'h10000c00, 0, 0, 1, 32'hdeadbeef, 0);
            if (CACHE && lines - saved_lines != 1) $fatal(1, "write miss incorrectly cached");
        end else begin
            saved_commands = commands;
            access_word(1, 32'h10000000, 32'hdeadbeef, 4'b1111, 1, 0, 1);
            if (commands != saved_commands || uram._ram[0] !== initial_word(0))
                $fatal(1, "instruction cache accepted a write");
        end
        saved_commands = commands;
        access_word(0, 32'h10001000, 0, 0, 0, initial_word(1024), 0);
        access_word(0, 32'h10001000, 0, 0, 0, initial_word(1024), 0);
        if (commands - saved_commands != 2) $fatal(1, "uncached accesses were cached");
        access_word(0, 32'h60000000, 0, 0, 0, 0, 1);
        if (CACHE) begin
            inject = 1;
            access_word(0, 32'h10000020, 0, 0, 1, 0, 1);
            inject = 0;
            saved_lines = lines;
            access_word(0, 32'h10000020, 0, 0, 1, initial_word(8), 0);
            if (lines - saved_lines != 1) $fatal(1, "failed partial fill installed a valid tag");
            fork
                begin
                    wait (cache.state == 3 && cache.beat == 2);
                    @(negedge clk);
                    invalidate = 1;
                    @(negedge clk);
                    invalidate = 0;
                end
                access_word(0, 32'h10000040, 0, 0, 1, initial_word(16), 0);
            join
            if (cache.valid0 !== 0 || cache.valid1 !== 0)
                $fatal(1, "stale refill reinstalled after invalidate");
            saved_lines = lines;
            access_word(0, 32'h10000040, 0, 0, 1, initial_word(16), 0);
            if (lines - saved_lines != 1) $fatal(1, "invalidate was ineffective");
        end
        // Exercise both ways and both ends of a line in every set. These
        // untouched RAM regions have identical indices and different tags.
        for (i = 0; i < 32; i = i + 1) begin
            saved_lines = lines;
            access_word(0, 32'h10002000 + i * 32, 0, 0, 1, initial_word(2048 + i * 8), 0);
            access_word(0, 32'h10002400 + i * 32 + 28, 0, 0, 1, initial_word(2311 + i * 8), 0);
            access_word(0, 32'h10002000 + i * 32 + 28, 0, 0, 1, initial_word(2055 + i * 8), 0);
            access_word(0, 32'h10002400 + i * 32, 0, 0, 1, initial_word(2304 + i * 8), 0);
            if (CACHE && lines - saved_lines != 2)
                $fatal(1, "set %0d cannot retain two full lines", i);
        end
        if (CACHE && READ_ONLY) begin
            instruction_hit_stream();
            // Warm B last, so the old LRU points at A. Complete a hit on A
            // while accepting a miss on C at the same edge: C must evict B.
            access_word(0, 32'h10002400, 0, 0, 1, initial_word(2304), 0);
            @(negedge clk);
            cv = 1;
            cw = 0;
            cc = 1;
            cr = 1;
            ca = 32'h10002000;
            do @(posedge clk); while (!cq);
            @(negedge clk);
            ca = 32'h10002800;
            @(posedge clk);
            if (!rv || !cq || rd !== initial_word(2048))
                $fatal(1, "same-set turnover was not exercised");
            @(negedge clk);
            cv = 0;
            while (!rv) @(negedge clk);
            if (re || rd !== initial_word(2560)) $fatal(1, "turnover miss result");
            @(posedge clk);
            @(negedge clk);
            cr = 0;
            saved_commands = commands;
            access_word(0, 32'h10002000, 0, 0, 1, initial_word(2048), 0);
            if (commands != saved_commands)
                $fatal(1, "turnover used stale LRU and evicted the just-hit line");
            access_word(0, 32'h10002400, 0, 0, 1, initial_word(2304), 0);
            if (commands - saved_commands != 1) $fatal(1, "turnover failed to evict old LRU");
        end
        // The same low address must not alias program and RAM tags. Final
        // legal lines must not fill from the following, illegal address.
        access_word(0, 32'h00003ffc, 0, 0, 1, 32'h5a000fff, 0);
        access_word(0, 32'h10003ffc, 0, 0, 1, initial_word(4095), 0);
        access_word(0, 32'h00003ffc, 0, 0, 1, 32'h5a000fff, 0);
        access_word(0, 32'h00004000, 0, 0, 1, 0, 1);
        access_word(0, 32'h10004000, 0, 0, 1, 0, 1);
        if (!READ_ONLY) begin
            // A write may have reached physical memory even if its response
            // reports an error. The cached copy must then be invalidated.
            access_word(0, 32'h10002000, 0, 0, 1, initial_word(2048), 0);
            inject_store = 1;
            access_word(1, 32'h10002000, 32'h10203040, 4'b1111, 1, 0, 1);
            inject_store = 0;
            saved_lines  = lines;
            access_word(0, 32'h10002000, 0, 0, 1, 32'h10203040, 0);
            if (CACHE && lines - saved_lines != 1)
                $fatal(1, "write error retained a valid cached line");
        end
        $display(
            "CACHE_SET_BOUNDARY_PASS sets=32 ways=2 line_edges=2 program_ram_last_word=1 write_error=%0d",
            !READ_ONLY);
        passed = 1;
        $display(
            "CACHE_BACKEND_PASS cache=%0d readonly=%0d commands=%0d read_beats=%0d writes=%0d hits=%0d misses=%0d",
            CACHE, READ_ONLY, commands, beats, writes, rh, rm);
        $finish;
    end
endmodule
