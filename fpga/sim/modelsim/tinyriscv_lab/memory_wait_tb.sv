/*
 * 模块说明：memory_wait_tb。
 * 来源说明：本工程板级适配、测试或构建辅助文件；来源快照见逐文件映射。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// 测试平台：memory_wait_tb；用于仿真检查，不能替代实体板运行或真实 ILA。
`timescale 1ns / 1ps
module memory_wait_tb #(
    parameter integer SEED = 1,
    FAULTS = 0,
    HALT = 0,
    FETCH_FAULTS = 0,
    IRQ_BACKPRESSURE = 0
);
    reg clk = 0, rst = 0;
    always #5 clk = ~clk;
    wire [31:0] ia, da, wd, x26, x27;
    wire iq, ir, dq, dw, dr;
    wire [3:0] be;
    reg iv = 0, dv = 0, de = 0, ie = 0;
    reg [31:0] idata = 0, ddata = 0;
    reg [7:0] irq = 0;
    reg debug_halt = 0;
    integer pause_checks = 0;
    reg [31:0] rom[0:4095], ram[0:4095];
    reg [31:0] rng = SEED;
    reg ibusy = 0, dbusy = 0;
    reg [31:0] iowner, downer, daddress, dwrite;
    reg [3:0] dmask;
    reg dstore;
    integer iw = 0, delay_d = 0, cycles = 0, accepted = 0, responses = 0, stores = 0;
    integer retires = 0, faults_seen = 0, redirects_waiting = 0, terminal_retires = 0;
    integer i, lane, fetch_faults_seen = 0, blocked_valid_cycles = 0;
    reg bp_irq_sent = 0;
    reg passed = 0;
    string image;
    wire iready = rst && !ibusy && rng[0];
    wire force_data_stall = IRQ_BACKPRESSURE && dq && dw && da == 32'h10000040 &&
        blocked_valid_cycles < 4;
    wire dready = rst && !dbusy && rng[2] && !force_data_stall;
    tinyriscv #(
        .WAIT_MEMORY(1)
    ) dut (
        .clk(clk),
        .rst(rst),
        .rib_ex_addr_o(da),
        .rib_ex_data_o(wd),
        .rib_ex_data_i(ddata),
        .rib_ex_req_o(dq),
        .rib_ex_we_o(dw),
        .rib_ex_wstrb_o(be),
        .data_req_ready_i(dready),
        .data_rsp_valid_i(dv),
        .data_rsp_error_i(de),
        .data_rsp_ready_o(dr),
        .rib_pc_addr_o(ia),
        .rib_pc_data_i(idata),
        .fetch_req_valid_o(iq),
        .fetch_req_ready_i(iready),
        .fetch_rsp_valid_i(iv),
        .fetch_rsp_error_i(ie),
        .fetch_rsp_ready_o(ir),
        .fence_i_o(),
        .prediction_clear_i(1'b0),
        .jtag_reg_addr_i(5'b0),
        .jtag_reg_data_i(32'b0),
        .jtag_reg_we_i(1'b0),
        .jtag_reg_data_o(),
        .rib_hold_flag_i(1'b0),
        .jtag_halt_flag_i(debug_halt),
        .jtag_reset_flag_i(1'b0),
        .int_i(irq),
        .test_x26_o(x26),
        .test_x27_o(x27)
    );
    initial begin
        for (i = 0; i < 4096; i = i + 1) begin
            rom[i] = 32'h13;
            ram[i] = 0;
        end
        if (!$value$plusargs("IMAGE=%s", image)) $fatal(1, "IMAGE missing");
        $readmemh(image, rom);
        repeat (4) @(negedge clk);
        rst = 1;
    end
    initial
        if (HALT) begin : pause_scenarios
            reg [31:0] held_pc, held_inst;
            integer saved_responses;
            wait (rst);
            wait (dut.ie_valid_o && !dut.raw_mem_req && !dut.is_div);
            @(negedge clk);
            debug_halt = 1;
            held_pc = dut.ie_inst_addr_o;
            held_inst = dut.ie_inst_o;
            repeat (8) begin
                @(posedge clk);
                #1;
                if (!dut.ie_valid_o || dut.ie_inst_addr_o !== held_pc ||
                    dut.ie_inst_o !== held_inst || dut.retire_valid)
                    $fatal(1, "halt lost an uncommitted instruction");
            end
            @(negedge clk);
            debug_halt   = 0;
            pause_checks = pause_checks + 1;
            wait (dbusy && dut.data_accepted);
            @(negedge clk);
            debug_halt = 1;
            saved_responses = responses;
            wait (responses == saved_responses + 1);
            repeat (6) @(negedge clk);
            if (dut.data_started || dut.data_accepted || dut.retire_valid || dut.ex_reg_we_o)
                $fatal(1, "halt did not drain data exactly once");
            debug_halt   = 0;
            pause_checks = pause_checks + 1;
            wait (dut.div_pending && dut.div_busy_o);
            @(negedge clk);
            debug_halt = 1;
            wait (!dut.div_pending);
            repeat (6) @(negedge clk);
            if (dut.retire_valid || dut.ex_reg_we_o) $fatal(1, "halt repeated divider completion");
            debug_halt   = 0;
            pause_checks = pause_checks + 1;
        end
    always @(posedge clk)
        if (rst) begin
            cycles = cycles + 1;
            rng <= {rng[30:0], rng[31] ^ rng[21] ^ rng[1] ^ rng[0]};
            if (iq && iready) begin
                if (ibusy) $fatal(1, "fetch duplicated");
                ibusy <= 1;
                iowner <= ia;
                iw <= 1 + int'(rng[7:4]);
            end
            if (ibusy && !iv) begin
                if (iw != 0) iw <= iw - 1;
                else begin
                    iv <= 1;
                    idata <= rom[iowner[13:2]];
                    ie <= FETCH_FAULTS && iowner == 32'h200;
                end
            end
            if (iv && ir) begin
                iv <= 0;
                ibusy <= 0;
                ie <= 0;
            end
            if (dq && dready) begin
                if (dbusy) $fatal(1, "data request duplicated");
                dbusy <= 1;
                downer <= dut.ie_inst_addr_o;
                daddress <= da;
                dwrite <= wd;
                dmask <= be;
                dstore <= dw;
                delay_d <= 3 + int'(rng[12:8]);
                accepted = accepted + 1;
                if (FAULTS && !IRQ_BACKPRESSURE && da == 32'h10000040 && dw) irq <= 8'b10;
            end
            if (force_data_stall) begin
                blocked_valid_cycles = blocked_valid_cycles + 1;
                if (blocked_valid_cycles == 2) begin
                    irq <= 8'b10;
                    bp_irq_sent <= 1;
                end
            end
            if (dbusy && !dv) begin
                if (delay_d != 0) delay_d <= delay_d - 1;
                else begin
                    dv <= 1;
                    de <= FAULTS && (daddress == 32'h10000080 || daddress == 32'h10000084);
                    if (daddress[31:28] == 1) ddata <= ram[daddress[13:2]];
                    else if (daddress[31:28] == 0) ddata <= rom[daddress[13:2]];
                    else ddata <= 0;
                    if (dstore && !(FAULTS && daddress == 32'h10000084)) begin
                        stores = stores + 1;
                        for (lane = 0; lane < 4; lane = lane + 1)
                        if (dmask[lane]) begin
                            if (daddress[31:28] == 1)
                                ram[daddress[13:2]][lane*8+:8] <= dwrite[lane*8+:8];
                            else if (daddress[31:28] == 0)
                                rom[daddress[13:2]][lane*8+:8] <= dwrite[lane*8+:8];
                        end
                    end
                end
            end
            if (dv && dr) begin
                dv <= 0;
                dbusy <= 0;
                de <= 0;
                responses = responses + 1;
            end
            if (dbusy && (!dut.ie_valid_o || dut.ie_inst_addr_o !== downer))
                $fatal(1, "data owner was lost");
            if (dbusy && !dv &&
                (dut.retire_valid || dut.ex_reg_we_o || dut.ex_csr_we_o || dut.trap_valid))
                $fatal(1, "commit/trap before accepted data response");
            if (dut.retire_valid) begin
                if (FETCH_FAULTS && dut.retire_pc == 32'h200) $fatal(1, "failed fetch retired");
                retires = retires + 1;
                if (dut.retire_inst[6:0] == 7'h03 || dut.retire_inst[6:0] == 7'h23)
                    if (!(dv && dr && !de)) $fatal(1, "memory retired without successful response");
            end
            if (dut.trap_valid && (dut.trap_cause == 5 || dut.trap_cause == 7))
                faults_seen = faults_seen + 1;
            if (dut.trap_valid && dut.trap_cause == 1) fetch_faults_seen = fetch_faults_seen + 1;
            if (dut.ex_jump_flag_o && ibusy) redirects_waiting = redirects_waiting + 1;
            // ISA binaries write x26 before x27. Wait for two actual retirements,
            // rather than a fixed number of cycles in a variable-latency core.
            if (x26 == 1 && dut.retire_valid) terminal_retires = terminal_retires + 1;
            if (x26 == 1 && terminal_retires >= 2) begin
                if (x27 !== 1) $fatal(1, "software failed pc=%h", dut.pc_pc_o);
                if (accepted != responses || dbusy) $fatal(1, "unmatched data requests");
                if (FAULTS && (faults_seen != 2 || ram[16] !== 32'h55aa || ram[33] !== 0))
                    $fatal(1, "fault/IRQ side effects incorrect");
                if (HALT && pause_checks != 3) $fatal(1, "halt scenarios incomplete");
                if (FETCH_FAULTS && fetch_faults_seen != 1)
                    $fatal(1, "fetch fault missing or repeated");
                if (IRQ_BACKPRESSURE && (!bp_irq_sent || blocked_valid_cycles < 4))
                    $fatal(1, "IRQ while valid was stalled not exercised");
                passed = 1;
                $display(
                    "MEMORY_WAIT_PASS seed=%0d cycles=%0d accepted=%0d responses=%0d stores=%0d retired=%0d faults=%0d redirects_waiting=%0d",
                    SEED, cycles, accepted, responses, stores, retires, faults_seen,
                    redirects_waiting);
                $finish;
            end
            if (cycles > 200000) $fatal(1, "timeout pc=%h", dut.pc_pc_o);
        end
    reg previous_i_stall = 0, previous_d_stall = 0, previous_ir_stall = 0, previous_dr_stall = 0;
    reg [31:0] held_ia, held_da, held_wd, held_id, held_dd;
    reg [3:0] held_be;
    reg held_dw, held_ie, held_de;
    always @(posedge clk)
        if (rst) begin
            if (previous_i_stall && (!iq || ia !== held_ia))
                $fatal(1, "fetch request changed under backpressure");
            if (previous_d_stall &&
                (!dq || da !== held_da || wd !== held_wd || dw !== held_dw || be !== held_be))
                $fatal(1, "data request changed under backpressure");
            if (previous_ir_stall && (!iv || idata !== held_id || ie !== held_ie))
                $fatal(1, "fetch response changed under backpressure");
            if (previous_dr_stall && (!dv || ddata !== held_dd || de !== held_de))
                $fatal(1, "data response changed under backpressure");
            previous_i_stall = iq && !iready;
            previous_d_stall = dq && !dready;
            previous_ir_stall = iv && !ir;
            previous_dr_stall = dv && !dr;
            held_ia = ia;
            held_da = da;
            held_wd = wd;
            held_dw = dw;
            held_be = be;
            held_id = idata;
            held_ie = ie;
            held_dd = ddata;
            held_de = de;
        end
endmodule
