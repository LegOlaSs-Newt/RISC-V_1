/*
 * 模块说明：predictor_lifecycle_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：predictor_lifecycle_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module predictor_lifecycle_tb #(
    parameter integer ENABLE = 1
);
    tinyriscv_lab_tb base ();
    integer fences = 0;
    reg checks_complete = 0;
    always @(posedge base.clk)
        if (base.rst && base.dut.u_tinyriscv.fence_i_commit) begin
            if (ENABLE && base.dut.u_tinyriscv.u_branch_predictor.valid === 0)
                base.fail("FENCE.I lifecycle test never trained predictor");
            #1;
            if (base.dut.u_tinyriscv.u_branch_predictor.valid !== 0)
                base.fail("FENCE.I did not clear predictor table");
            fences = fences + 1;
            $display("LIFECYCLE_FENCE_CLEARED enable=%0d count=%0d", ENABLE, fences);
        end
    initial begin
        wait (base.rst);
        wait (base.dut.u_tinyriscv.u_regs.regs[25] === 2);
        repeat (12) @(negedge base.clk);
        if (fences != 1) base.fail("missing first FENCE.I");
        if (ENABLE && base.dut.u_tinyriscv.u_branch_predictor.valid === 0)
            base.fail("JTAG reset lifecycle test never trained predictor");
        force base.dut.u_tinyriscv.jtag_reset_flag_i = 1'b1;
        @(posedge base.clk);
        #1;
        if (base.dut.u_tinyriscv.u_branch_predictor.valid !== 0)
            base.fail("JTAG reset did not clear predictor");
        @(negedge base.clk);
        force base.dut.u_tinyriscv.jtag_reset_flag_i = 1'b0;
        @(negedge base.clk);
        release base.dut.u_tinyriscv.jtag_reset_flag_i;
        wait (base.dut.u_tinyriscv.u_regs.regs[25] === 0);
        wait (base.dut.u_tinyriscv.u_regs.regs[25] === 2);
        repeat (12) @(negedge base.clk);
        if (fences != 2) base.fail("missing second FENCE.I");
        force base.rst = 1'b0;
        repeat (2) @(posedge base.clk);
        #1;
        if (base.dut.u_tinyriscv.u_branch_predictor.valid !== 0)
            base.fail("SoC reset did not clear predictor");
        // Replace program while reset, as the board download/restart sequence does.
        base.dut.u_rom._rom[0] = 32'h00100d93;  // addi x27,x0,1
        base.dut.u_rom._rom[1] = 32'h00100d13;  // addi x26,x0,1
        base.dut.u_rom._rom[2] = 32'h0000006f;  // jal x0,0
        @(negedge base.clk);
        force base.rst = 1'b1;
        @(negedge base.clk);
        release base.rst;
        wait (base.x27 === 1);
        checks_complete = 1;
        $display("PREDICTOR_LIFECYCLE_CHECKS enable=%0d fences=%0d", ENABLE, fences);
    end
endmodule

