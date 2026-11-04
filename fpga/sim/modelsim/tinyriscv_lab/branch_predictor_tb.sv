/*
 * 模块说明：branch_predictor_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：branch_predictor_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
// Standalone state-transition tests, independent of CPU instruction tests.
module branch_predictor_tb #(
    parameter integer ENABLE = 1
);
    reg clk = 0, rst = 0, clear = 0;
    always #5 clk = ~clk;
    reg [31:0] pc = 0, rpc = 0, target = 0;
    reg resolve = 0, cond = 0, jal = 0, taken = 0;
    wire [31:0] predicted;
    wire hit, predict_taken;
    reg passed = 0;
    integer i;
    branch_predictor #(
        .ENABLE(ENABLE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .clear_i(clear),
        .fetch_pc_i(pc),
        .predicted_next_o(predicted),
        .hit_o(hit),
        .taken_o(predict_taken),
        .resolve_i(resolve),
        .resolve_pc_i(rpc),
        .target_i(target),
        .conditional_i(cond),
        .jal_i(jal),
        .taken_i(taken)
    );
    task check(input bit expected_hit, input [31:0] expected_next);
        #1;
        if (hit !== expected_hit || predicted !== expected_next)
            $fatal(
                1,
                "BTB mismatch pc=%h hit=%b next=%h expected_hit=%b expected_next=%h",
                pc,
                hit,
                predicted,
                expected_hit,
                expected_next
            );
    endtask
    task train(input [31:0] a, input [31:0] t, input bit c, input bit j, input bit tk);
        @(negedge clk);
        rpc = a;
        target = t;
        cond = c;
        jal = j;
        taken = tk;
        resolve = 1;
        @(negedge clk);
        resolve = 0;
    endtask
    initial begin
        repeat (2) @(negedge clk);
        rst = 1;
        for (i = 0; i < 32; i = i + 1) begin
            pc = i * 4;
            check(0, i * 4 + 4);
        end
        pc = 4;
        train(4, 32'h200, 1, 0, 0);  // allocate weak not taken (01)
        if (ENABLE) begin
            check(1, 8);
            train(4, 32'h200, 1, 0, 1);
            check(1, 32'h200);  // 10
            train(4, 32'h200, 1, 0, 1);
            check(1, 32'h200);  // 11
            train(4, 32'h200, 1, 0, 1);
            check(1, 32'h200);  // saturate
            train(4, 32'h200, 1, 0, 0);
            check(1, 32'h200);  // 10
            train(4, 32'h200, 1, 0, 0);
            check(1, 8);  // 01
            train(4, 32'h200, 1, 0, 0);
            check(1, 8);  // 00
            train(4, 32'h200, 1, 0, 0);
            check(1, 8);  // saturate
            train(32'h84, 32'h300, 0, 1, 1);  // same index, new tag/JAL
            check(0, 8);
            pc = 32'h84;
            check(1, 32'h300);
            // Non-branch at same PC invalidates a stale instruction.
            train(32'h84, 0, 0, 0, 0);
            check(0, 32'h88);
            train(32'h84, 32'h304, 0, 1, 1);
            check(1, 32'h304);
            // resolve=0 never trains, even with a matching address.
            @(negedge clk);
            rpc = 32'h84;
            target = 32'h400;
            cond = 0;
            jal = 1;
            taken = 1;
            @(negedge clk);
            check(1, 32'h304);
            train(32'h84, 32'h308, 0, 1, 1);
            check(1, 32'h308);
            clear   = 1;
            resolve = 1;  // clear has priority over update
            @(negedge clk);
            clear   = 0;
            resolve = 0;
            check(0, 32'h88);
            train(4, 32'h200, 1, 0, 1);
            pc = 4;
            check(1, 32'h200);
            rst = 0;
            @(negedge clk);
            rst = 1;
            check(0, 8);
        end else begin
            check(0, 8);
            train(4, 32'h300, 0, 1, 1);
            check(0, 8);
        end
        passed = 1;
        $display("BTB_PASS enable=%0d", ENABLE);
        $finish;
    end
    initial begin
        #20000;
        $fatal(1, "BTB timeout");
    end
endmodule

