/*
 * 模块说明：early_cache_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：early_cache_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module early_cache_tb;
    reg clk = 0, rst = 0, invalidate = 0;
    always #5 clk = ~clk;
    reg rv = 0, lv = 0, lc = 0, block_query = 0, lu = 0, mv = 0, me = 0, ml = 0;
    reg [31:0] ra = 0, la = 0, md = 0;
    wire rr, sv, se, cv, cw, mr, lr, lrv, lh;
    wire [31:0] sd, ca, cd, lra, ld;
    wire [3:0] cs, cb;
    wire [63:0] dh, dm, wh, wm, wc, uc;
    integer commands = 0, n;
    reg passed = 0;
    two_way_cache #(
        .ENABLE(1),
        .EARLY_LOOKUP(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .invalidate_i(invalidate),
        .req_valid_i(rv),
        .req_write_i(1'b0),
        .req_cacheable_i(1'b1),
        .req_addr_i(ra),
        .req_wdata_i(32'b0),
        .req_wstrb_i(4'b0),
        .req_ready_o(rr),
        .rsp_valid_o(sv),
        .rsp_error_o(se),
        .rsp_data_o(sd),
        .rsp_ready_i(1'b1),
        .lookup_valid_i(lv),
        .lookup_cancel_i(lc),
        .lookup_block_i(block_query),
        .lookup_use_i(lu),
        .lookup_addr_i(la),
        .lookup_ready_o(lr),
        .lookup_result_valid_o(lrv),
        .lookup_hit_o(lh),
        .lookup_result_addr_o(lra),
        .lookup_data_o(ld),
        .cmd_valid_o(cv),
        .cmd_write_o(cw),
        .cmd_addr_o(ca),
        .cmd_wdata_o(cd),
        .cmd_wstrb_o(cs),
        .cmd_beats_o(cb),
        .cmd_ready_i(1'b1),
        .mem_valid_i(mv),
        .mem_error_i(me),
        .mem_last_i(ml),
        .mem_data_i(md),
        .mem_ready_o(mr),
        .read_hits_o(dh),
        .read_misses_o(dm),
        .write_hits_o(wh),
        .write_misses_o(wm),
        .wait_cycles_o(wc),
        .uncached_o(uc)
    );
    always @(posedge clk) if (rst && cv) commands = commands + 1;
    task automatic query(input [31:0] address);
        @(negedge clk);
        la = address;
        lv = 1;
        #1;
        if (!lr) $fatal(1, "lookup unexpectedly blocked");
        @(posedge clk);
        @(negedge clk);
        lv = 0;
    endtask
    task automatic fill(input [31:0] address, input [31:0] base, input bit fault);
        @(negedge clk);
        ra = address;
        rv = 1;
        #1;
        if (!rr || !cv || cb != 8) $fatal(1, "normal miss command missing");
        @(posedge clk);
        @(negedge clk);
        rv = 0;
        for (integer k = 0; k < 8; k = k + 1) begin
            mv = 1;
            ml = (k == 7);
            me = fault && (k == 7);
            md = base + k;
            #1;
            if (!mr) $fatal(1, "refill backpressure unexpected");
            if (k == 7 && (!sv || se != fault)) $fatal(1, "final error/completion mismatch");
            @(posedge clk);
            @(negedge clk);
        end
        mv = 0;
        ml = 0;
        me = 0;
    endtask
    initial begin
        repeat (3) @(negedge clk);
        rst = 1;
        query(8);
        if (!lrv || lh || cv || dh || dm || commands || dut.valid0 || dut.valid1)
            $fatal(1, "query miss had side effects");
        fill(8, 32'h10000000, 0);
        fill(32'h408, 32'h20000000, 0);
        if (dut.lru[0] !== 0) $fatal(1, "warm LRU unexpected");
        query(8);
        if (!lh || ld !== 32'h10000002 || dh || dut.lru[0] !== 0)
            $fatal(1, "query changed stats/LRU or data wrong");
        lu = 1;
        @(posedge clk);
        @(negedge clk);
        lu = 0;
        if (dh != 1 || dut.lru[0] !== 1) $fatal(1, "committed hit not counted exactly once");
        query(32'h408);
        if (!lh || ld !== 32'h20000002) $fatal(1, "second way query wrong");
        @(posedge clk);
        @(negedge clk);
        if (lrv || lh || dh != 1) $fatal(1, "query validity exceeded one cycle");
        // An architectural request owns the same read port before a query.
        @(negedge clk);
        ra = 32'h408;
        rv = 1;
        la = 8;
        lv = 1;
        #1;
        if (lr || !rr) $fatal(1, "normal request lost read-port priority");
        @(posedge clk);
        @(negedge clk);
        rv = 0;
        lv = 0;
        if (lrv || !sv || sd !== 32'h20000002) $fatal(1, "normal hit response wrong");
        @(posedge clk);
        @(negedge clk);
        query(8);
        lc = 1;
        @(posedge clk);
        @(negedge clk);
        lc = 0;
        if (lrv || lh || dh != 2) $fatal(1, "cancel retained query or changed hit count");
        query(8);
        block_query = 1;
        #1;
        if (lrv || lh) $fatal(1, "host block did not mask result");
        @(posedge clk);
        @(negedge clk);
        block_query = 0;
        query(8);
        invalidate  = 1;
        block_query = 1;
        @(posedge clk);
        @(negedge clk);
        invalidate  = 0;
        block_query = 0;
        if (lrv || lh || dut.valid0 || dut.valid1)
            $fatal(1, "invalidate retained query/cache line");
        query(8);
        if (lh || cv || commands != 2) $fatal(1, "invalid query allocated/refilled a line");
        fill(8, 32'h30000000, 1);
        if (dut.valid0 || dut.valid1) $fatal(1, "late refill error installed valid data");
        fill(8, 32'h30000000, 0);
        query(8);
        if (!lh || ld !== 32'h30000002) $fatal(1, "post-error refill failed");
        rst = 0;
        @(posedge clk);
        @(negedge clk);
        rst = 1;
        if (lrv || lh || dh || dm || dut.valid0 || dut.valid1)
            $fatal(1, "reset retained query identity");
        passed = 1;
        $display(
            "EARLY_CACHE_PASS speculative_miss,no_side_effects,ways,TTL,port_priority,cancel,host,invalidate,late_error,reset"
                );
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "unit timeout");
    end
endmodule
