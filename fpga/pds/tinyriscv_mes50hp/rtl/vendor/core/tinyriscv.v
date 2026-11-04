/*
 * 模块说明：三级 RV32IM 处理器核心。
 * 来源说明：基于 TinyRISC-V 对应模块修改扩展，原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：连接 IF ID EX、寄存器堆、CSR、除法与异常控制，增加有效提交、预测及等待接口。
 * 关键约束：保持流水与清空流水含义不同。只有真实完成且未被异常取消的指令退休一次；未完成访存和除法保留唯一归属，中断在安全提交边界受理。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "defines.v"
`include "../../mes50hp_config.vh"
`ifndef MES50HP_BP_ENABLE
`define MES50HP_BP_ENABLE 1
`endif

// tinyriscv处理器核顶层模块
module tinyriscv #(
    parameter WAIT_MEMORY = 0,
    EARLY_D_LOOKUP = 0
) (

    input wire clk,
    input wire rst,

    output wire [`MemAddrBus] rib_ex_addr_o,             // 读、写外设的地址
    input  wire [    `MemBus] rib_ex_data_i,             // 从外设读取的数据
    output wire [    `MemBus] rib_ex_data_o,             // 写入外设的数据
    output wire               rib_ex_req_o,              // 访问外设请求
    output wire               rib_ex_we_o,               // 写外设标志
    output wire [        3:0] rib_ex_wstrb_o,
    input  wire               data_req_ready_i,
    data_rsp_valid_i,
    data_rsp_error_i,
    output wire               data_rsp_ready_o,
    output wire               data_lookup_valid_o,
    data_lookup_cancel_o,
    data_lookup_use_o,
    output wire [       31:0] data_lookup_addr_o,
    input  wire               data_lookup_ready_i,
    data_lookup_result_valid_i,
    data_lookup_hit_i,
    input  wire [       31:0] data_lookup_result_addr_i,
    data_lookup_data_i,

    output wire [`MemAddrBus] rib_pc_addr_o,      // 取指地址
    input  wire [    `MemBus] rib_pc_data_i,      // 取到的指令内容
    output wire               fetch_req_valid_o,
    fetch_rsp_ready_o,
    input  wire               fetch_req_ready_i,
    fetch_rsp_valid_i,
    fetch_rsp_error_i,
    output wire               fence_i_o,
    output wire               quiescent_o,
    input  wire               prediction_clear_i,

    input  wire [`RegAddrBus] jtag_reg_addr_i,  // jtag模块读、写寄存器的地址
    input  wire [    `RegBus] jtag_reg_data_i,  // jtag模块写寄存器数据
    input  wire               jtag_reg_we_i,    // jtag模块写寄存器标志
    output wire [    `RegBus] jtag_reg_data_o,  // jtag模块读取到的寄存器数据

    input wire rib_hold_flag_i,   // 总线暂停标志
    input wire jtag_halt_flag_i,  // jtag暂停标志
    input wire jtag_reset_flag_i, // jtag复位PC标志

    input wire [`INT_BUS] int_i,  // 中断信号

    // MES50HP port: explicit software test-status outputs.
    output wire [`RegBus] test_x26_o,
    output wire [`RegBus] test_x27_o

);

    // pc_reg模块输出信号
    wire [`InstAddrBus] pc_pc_o;

    // if_id模块输出信号
    wire [`InstBus] if_inst_o;
    wire [`InstAddrBus] if_inst_addr_o;
    wire [`INT_BUS] if_int_flag_o;
    wire if_valid_o;
    wire ie_valid_o;
    wire if_fetch_error, ex_fetch_error;
    wire fetch_valid, fetch_error, fetch_busy, fetch_consume;
    wire [31:0] fetch_pc, fetch_data, fetch_prediction, fetch_request_addr;
    wire [31:0] fetch_lookup_pc;
    wire [31:0] if_predicted_next, id_predicted_next, ex_predicted_next;

    // The inherited divider drains the pipeline on launch. Preserve its owner
    // independently of EX bubbles until the single completion writeback.
    reg div_pending;
    reg [31:0] div_owner_pc;
    reg [31:0] div_owner_inst;

    // id模块输出信号
    wire [`RegAddrBus] id_reg1_raddr_o;
    wire [`RegAddrBus] id_reg2_raddr_o;
    wire [`InstBus] id_inst_o;
    wire [`InstAddrBus] id_inst_addr_o;
    wire [`RegBus] id_reg1_rdata_o;
    wire [`RegBus] id_reg2_rdata_o;
    wire id_reg_we_o;
    wire [`RegAddrBus] id_reg_waddr_o;
    wire [`MemAddrBus] id_csr_raddr_o;
    wire id_csr_we_o;
    wire [`RegBus] id_csr_rdata_o;
    wire [`MemAddrBus] id_csr_waddr_o;
    wire [`MemAddrBus] id_op1_o;
    wire [`MemAddrBus] id_op2_o;
    wire [`MemAddrBus] id_op1_jump_o;
    wire [`MemAddrBus] id_op2_jump_o;

    // id_ex模块输出信号
    wire [`InstBus] ie_inst_o;
    wire [`InstAddrBus] ie_inst_addr_o;
    wire ie_reg_we_o;
    wire [`RegAddrBus] ie_reg_waddr_o;
    wire [`RegBus] ie_reg1_rdata_o;
    wire [`RegBus] ie_reg2_rdata_o;
    wire ie_csr_we_o;
    wire [`MemAddrBus] ie_csr_waddr_o;
    wire [`RegBus] ie_csr_rdata_o;
    wire [`MemAddrBus] ie_op1_o;
    wire [`MemAddrBus] ie_op2_o;
    wire [`MemAddrBus] ie_op1_jump_o;
    wire [`MemAddrBus] ie_op2_jump_o;

    // ex模块输出信号
    wire [`MemBus] ex_mem_wdata_o;
    wire [`MemAddrBus] ex_mem_raddr_o;
    wire [`MemAddrBus] ex_mem_waddr_o;
    wire ex_mem_we_o;
    wire ex_mem_req_o;
    wire [`RegBus] ex_reg_wdata_o;
    wire ex_reg_we_o;
    wire [`RegAddrBus] ex_reg_waddr_o;
    wire ex_hold_flag_o;
    wire ex_jump_flag_o;
    wire [`InstAddrBus] ex_jump_addr_o;
    wire ex_div_start_o;
    wire [`RegBus] ex_div_dividend_o;
    wire [`RegBus] ex_div_divisor_o;
    wire [2:0] ex_div_op_o;
    wire [`RegAddrBus] ex_div_reg_waddr_o;
    wire [`RegBus] ex_csr_wdata_o;
    wire ex_csr_we_o;
    wire [`MemAddrBus] ex_csr_waddr_o;

    // regs模块输出信号
    wire [`RegBus] regs_rdata1_o;
    wire [`RegBus] regs_rdata2_o;

    // csr_reg模块输出信号
    wire [`RegBus] csr_data_o;
    wire [`RegBus] csr_clint_data_o;
    wire csr_global_int_en_o;
    wire [`RegBus] csr_clint_csr_mtvec;
    wire [`RegBus] csr_clint_csr_mepc;
    wire [`RegBus] csr_clint_csr_mstatus;

    // ctrl模块输出信号
    wire [`Hold_Flag_Bus] ctrl_hold_flag_o;
    wire ctrl_jump_flag_o;
    wire [`InstAddrBus] ctrl_jump_addr_o;

    // div模块输出信号
    wire [`RegBus] div_result_o;
    wire div_ready_o;
    wire div_busy_o;
    wire [`RegAddrBus] div_reg_waddr_o;

    // clint模块输出信号
    wire clint_we_o;
    wire [`MemAddrBus] clint_waddr_o;
    wire [`MemAddrBus] clint_raddr_o;
    wire [`RegBus] clint_data_o;
    wire [`InstAddrBus] clint_int_addr_o;
    wire clint_int_assert_o;
    wire clint_hold_flag_o;


    // V0.4: side effects and redirects are selected at a valid EX boundary.
    wire raw_reg_we, raw_csr_we, raw_mem_req, raw_mem_we, raw_jump, raw_div_start;
    wire [31:0] raw_jump_addr;
    wire csr_legal;
    wire [31:0] csr_mie, csr_mip;
    wire sync_exception;
    wire [31:0] sync_cause, sync_tval;
    wire decoded_exception;
    wire [31:0] decoded_cause, decoded_tval;
    reg data_started, data_accepted;
    reg early_owner_valid;
    reg [31:0] early_owner_address;
    wire early_data_match = EARLY_D_LOOKUP && WAIT_MEMORY && early_owner_valid && ie_valid_o &&
        raw_mem_req && !raw_mem_we && !data_started && !data_accepted && !sync_exception &&
        data_lookup_result_valid_i && data_lookup_hit_i && early_owner_address == ex_mem_raddr_o &&
        data_lookup_result_addr_i == ex_mem_raddr_o;
    wire slow_data_complete = WAIT_MEMORY && data_accepted && data_rsp_valid_i;
    wire data_complete = slow_data_complete || early_data_match;
    wire data_error = slow_data_complete && data_rsp_error_i;
    wire
        memory_wait = WAIT_MEMORY && ie_valid_o && raw_mem_req && !sync_exception && !data_complete;
    wire debug_pause = WAIT_MEMORY && jtag_halt_flag_i;
    wire [2:0] pipe_control = memory_wait && !clint_int_assert_o ? `Hold_None :
        debug_pause && !ex_jump_flag_o && !ex_hold_flag_o ? `Hold_None : ctrl_hold_flag_o;
    wire boundary_valid = ie_valid_o && !div_pending && !div_busy_o &&
        (!jtag_halt_flag_i || (WAIT_MEMORY && data_started)) &&
        (!jtag_reset_flag_i || (WAIT_MEMORY && data_started));
    wire [31:0] eligible_irqs = csr_mie & csr_mip;
    wire irq_pending = csr_clint_csr_mstatus[3] && |eligible_irqs;
    wire [31:0] irq_cause = eligible_irqs[11] ? 32'h8000000b :
        eligible_irqs[3] ? 32'h80000003 : 32'h80000007;
    wire take_irq = irq_pending && !(WAIT_MEMORY && data_started);
    wire trap_valid = boundary_valid && (sync_exception || data_error || take_irq);
    wire [31:0] trap_cause = sync_exception ? sync_cause :
        data_error ? (raw_mem_we ? 32'd7 : 32'd5) : irq_cause;
    wire [31:0] trap_tval = sync_exception ? sync_tval : data_error ? rib_ex_addr_o : 32'b0;
    wire mret_valid = boundary_valid && !trap_valid && ie_inst_o == 32'h30200073;
    wire is_div = ie_inst_o[6:0] == 7'h33 && ie_inst_o[31:25] == 1 && ie_inst_o[14:12] >= 4;
    wire divider_commit = div_pending && div_ready_o && (!jtag_halt_flag_i || WAIT_MEMORY) &&
        !jtag_reset_flag_i;
    wire retire_valid = rst &&
        ((boundary_valid && !trap_valid && !is_div && !memory_wait) || divider_commit);
    wire [31:0] retire_pc = divider_commit ? div_owner_pc : ie_inst_addr_o;
    wire [31:0] retire_inst = divider_commit ? div_owner_inst : ie_inst_o;
    wire effects_allowed = !trap_valid &&
        (!jtag_halt_flag_i || (WAIT_MEMORY && (data_started || div_pending))) &&
        (!jtag_reset_flag_i || (WAIT_MEMORY && data_started));
    wire is_branch = ie_inst_o[6:0] == 7'h63;
    wire is_jal = ie_inst_o[6:0] == 7'h6f;
    wire is_jalr = ie_inst_o[6:0] == 7'h67;
    wire is_fence = ie_inst_o[6:0] == 7'h0f;
    wire fence_i_commit = retire_valid && !divider_commit && is_fence && ie_inst_o[14:12] == 1;
    wire [31:0] actual_next_pc = raw_jump ? raw_jump_addr : ie_inst_addr_o + 32'd4;
    wire mispredict = boundary_valid && !trap_valid && !mret_valid && !is_div && !memory_wait &&
        (actual_next_pc != ex_predicted_next);
    wire control_redirect = boundary_valid && effects_allowed && (mispredict || is_div || is_fence);
    wire branch_resolve = retire_valid && !divider_commit && (is_branch || is_jal);
    wire branch_mispredict = branch_resolve && mispredict;
    wire predictor_hit, predictor_taken;
    assign fence_i_o = fence_i_commit;
    assign quiescent_o = !data_started && !data_accepted && !div_pending && !div_busy_o;
    // Instruction access errors precede decoding, including injected backend errors.
    assign sync_exception = decoded_exception || (WAIT_MEMORY && ex_fetch_error);
    assign sync_cause = WAIT_MEMORY && ex_fetch_error && !(|ie_inst_addr_o[1:0]) ? 32'd1 :
        decoded_cause;
    assign sync_tval = WAIT_MEMORY && ex_fetch_error ? ie_inst_addr_o : decoded_tval;

    fetch_transaction u_fetch_transaction (
        .clk(clk),
        .rst(rst),
        .enable_i(WAIT_MEMORY && !jtag_halt_flag_i && !jtag_reset_flag_i),
        .flush_i(ex_jump_flag_o || jtag_reset_flag_i || jtag_halt_flag_i),
        // FENCE.I starts only after the cache/predictor clear edge. Other
        // known redirects may replace a discarded fetch at this same edge.
        .redirect_i(ex_jump_flag_o && !fence_i_commit),
        .redirect_pc_i(ex_jump_addr_o),
        .consume_i(fetch_consume),
        .pc_i(pc_pc_o),
        .predicted_next_i(if_predicted_next),
        .req_valid_o(fetch_req_valid_o),
        .req_ready_i(fetch_req_ready_i),
        .req_addr_o(fetch_request_addr),
        .rsp_valid_i(fetch_rsp_valid_i),
        .rsp_error_i(fetch_rsp_error_i),
        .rsp_data_i(rib_pc_data_i),
        .rsp_ready_o(fetch_rsp_ready_o),
        .valid_o(fetch_valid),
        .error_o(fetch_error),
        .data_o(fetch_data),
        .pc_o(fetch_pc),
        .predicted_next_o(fetch_prediction),
        .lookup_pc_o(fetch_lookup_pc),
        .busy_o(fetch_busy)
    );
    assign fetch_consume = WAIT_MEMORY && !memory_wait && pipe_control < `Hold_If &&
        !jtag_halt_flag_i && !jtag_reset_flag_i;
    assign data_rsp_ready_o = WAIT_MEMORY && rst && data_accepted;
    wire id_load = id_inst_o[6:0] == 7'h03 &&
        (id_inst_o[14:12] == 0 || id_inst_o[14:12] == 1 || id_inst_o[14:12] == 2 ||
         id_inst_o[14:12] == 4 || id_inst_o[14:12] == 5);
    wire [31:0] id_load_address = id_op1_o + id_op2_o;
    wire id_load_aligned = !(id_inst_o[13:12] == 1 && id_load_address[0]) &&
        !(id_inst_o[13:12] == 2 && |id_load_address[1:0]);
    wire id_load_cached = id_load_address < 32'h4000 ||
        (id_load_address >= 32'h10000000 && id_load_address < 32'h10004000);
    assign data_lookup_addr_o = id_load_address;
    assign data_lookup_cancel_o = ex_jump_flag_o || debug_pause || jtag_reset_flag_i ||
        prediction_clear_i;
    assign data_lookup_valid_o = EARLY_D_LOOKUP && WAIT_MEMORY && rst && if_valid_o &&
        !if_fetch_error && id_load && id_load_aligned && id_load_cached && !memory_wait &&
        pipe_control < `Hold_Id && !data_lookup_cancel_o;
    assign
        data_lookup_use_o = EARLY_D_LOOKUP && early_data_match && retire_valid && !divider_commit;
    always @(posedge clk) begin
        if (!rst || !EARLY_D_LOOKUP || data_lookup_cancel_o || pipe_control >= `Hold_Id) begin
            early_owner_valid   <= 0;
            early_owner_address <= 0;
        end else if (!memory_wait) begin
            early_owner_valid   <= data_lookup_valid_o && data_lookup_ready_i;
            early_owner_address <= id_load_address;
        end
    end
    always @(posedge clk) begin
        if (!rst) begin
            data_started  <= 0;
            data_accepted <= 0;
        end else if (WAIT_MEMORY) begin
            if (ex_mem_req_o) data_started <= 1;
            if (ex_mem_req_o && data_req_ready_i) data_accepted <= 1;
            if (data_complete) begin
                data_started  <= 0;
                data_accepted <= 0;
            end
        end
    end

    branch_predictor #(
        .ENABLE(`MES50HP_BP_ENABLE)
    ) u_branch_predictor (
        .clk(clk),
        .rst(rst),
        .clear_i(jtag_reset_flag_i || fence_i_commit || (WAIT_MEMORY && prediction_clear_i)),
        .fetch_pc_i(WAIT_MEMORY ? fetch_lookup_pc : pc_pc_o),
        .predicted_next_o(if_predicted_next),
        .hit_o(predictor_hit),
        .taken_o(predictor_taken),
        .resolve_i(retire_valid && !divider_commit),
        .resolve_pc_i(ie_inst_addr_o),
        .resolve_inst_i(ie_inst_o),
        .target_i(is_jalr ? raw_jump_addr : ie_op1_jump_o + ie_op2_jump_o),
        .conditional_i(is_branch),
        .jal_i(is_jal || is_jalr),
        .taken_i(raw_jump)
    );

    assign ex_reg_we_o = raw_reg_we && effects_allowed && !memory_wait;
    assign ex_csr_we_o = raw_csr_we && effects_allowed;
    assign ex_mem_req_o = raw_mem_req && effects_allowed && !(WAIT_MEMORY && data_accepted) &&
        !early_data_match;
    assign ex_mem_we_o = raw_mem_we && effects_allowed && !(WAIT_MEMORY && data_accepted) &&
        !early_data_match;
    assign ex_div_start_o = raw_div_start && effects_allowed;
    assign ex_jump_flag_o = control_redirect || clint_int_assert_o;
    assign ex_jump_addr_o = clint_int_assert_o ? clint_int_addr_o : actual_next_pc;
    assign clint_hold_flag_o = 1'b0;
    assign clint_int_assert_o = trap_valid || mret_valid;
    assign clint_int_addr_o = mret_valid ? csr_clint_csr_mepc :
        ({csr_clint_csr_mtvec[31:2], 2'b00} + ((trap_cause[31] && csr_clint_csr_mtvec[1:0] == 1) ?
                                               {25'b0, trap_cause[4:0], 2'b00} : 32'b0));

    trap_control #(
        .MEMORY_STATS(WAIT_MEMORY)
    ) u_trap_control (
        .valid_i(boundary_valid),
        .pc_i(ie_inst_addr_o),
        .inst_i(ie_inst_o),
        .rs1_i(ie_reg1_rdata_o),
        .jump_i(raw_jump),
        .jump_target_i(raw_jump_addr),
        .csr_legal_i(csr_legal),
        .exception_o(decoded_exception),
        .cause_o(decoded_cause),
        .tval_o(decoded_tval)
    );

    always @(posedge clk) begin
        if (!rst || jtag_reset_flag_i) begin
            div_pending <= 1'b0;
            div_owner_pc <= 32'b0;
            div_owner_inst <= 32'b0;
        end else if (clint_int_assert_o) begin
            div_pending <= 1'b0;
        end else if (ie_valid_o && ex_div_start_o && !div_pending) begin
            div_pending <= 1'b1;
            div_owner_pc <= ie_inst_addr_o;
            div_owner_inst <= ie_inst_o;
        end else if (div_ready_o) begin
            div_pending <= 1'b0;
        end
    end


    assign rib_ex_addr_o = (ex_mem_we_o == `WriteEnable) ? ex_mem_waddr_o : ex_mem_raddr_o;
    wire [1:0] store_offset = ex_mem_waddr_o[1:0];
    wire [2:0] store_size = ie_inst_o[14:12];
    assign rib_ex_wstrb_o = !WAIT_MEMORY ? 4'b1111 : store_size == 0 ? (4'b0001 << store_offset) :
        store_size == 1 ? (4'b0011 << store_offset) : 4'b1111;
    assign rib_ex_data_o = WAIT_MEMORY && raw_mem_we ? (ie_reg2_rdata_o << {store_offset, 3'b000}) :
        ex_mem_wdata_o;
    assign rib_ex_req_o = ex_mem_req_o;
    assign rib_ex_we_o = ex_mem_we_o;

    // Invalid instruction addresses never select a peripheral on RIB.
    assign rib_pc_addr_o = WAIT_MEMORY ? fetch_request_addr : pc_pc_o < 32'h4000 ? pc_pc_o : 32'b0;


    // pc_reg模块例化
    pc_reg u_pc_reg (
        .predicted_next_i(WAIT_MEMORY ? fetch_prediction : if_predicted_next),
        .clk(clk),
        .rst(rst),
        .jtag_reset_flag_i(jtag_reset_flag_i),
        .pc_o(pc_pc_o),
        .hold_flag_i(WAIT_MEMORY && !(fetch_valid && fetch_consume) ? `Hold_Pc : ctrl_hold_flag_o),
        .jump_flag_i(ctrl_jump_flag_o),
        .jump_addr_i(ctrl_jump_addr_o)
    );

    // ctrl模块例化
    ctrl u_ctrl (
        .rst(rst),
        .jump_flag_i(ex_jump_flag_o),
        .jump_addr_i(ex_jump_addr_o),
        .hold_flag_ex_i(ex_hold_flag_o),
        .hold_flag_rib_i(rib_hold_flag_i),
        .hold_flag_o(ctrl_hold_flag_o),
        .hold_flag_clint_i(clint_hold_flag_o),
        .jump_flag_o(ctrl_jump_flag_o),
        .jump_addr_o(ctrl_jump_addr_o),
        .jtag_halt_flag_i(jtag_halt_flag_i)
    );

    // regs模块例化
    regs u_regs (
        .clk(clk),
        .rst(rst),
        .we_i(ex_reg_we_o),
        .waddr_i(ex_reg_waddr_o),
        .wdata_i(ex_reg_wdata_o),
        .raddr1_i(id_reg1_raddr_o),
        .rdata1_o(regs_rdata1_o),
        .raddr2_i(id_reg2_raddr_o),
        .rdata2_o(regs_rdata2_o),
        .jtag_we_i(jtag_reg_we_i),
        .jtag_addr_i(jtag_reg_addr_i),
        .jtag_data_i(jtag_reg_data_i),
        .jtag_data_o(jtag_reg_data_o),
        .test_x26_o(test_x26_o),
        .test_x27_o(test_x27_o)
    );

    // csr_reg模块例化
    csr_reg u_csr_reg (
        .clk(clk),
        .rst(rst),
        .we_i(ex_csr_we_o),
        .raddr_i(ie_inst_o[31:20]),
        .waddr_i(ex_csr_waddr_o[11:0]),
        .data_i(ex_csr_wdata_o),
        .data_o(csr_data_o),
        .access_write_i(ie_csr_we_o),
        .access_legal_o(csr_legal),
        .int_i(int_i),
        .trap_i(trap_valid),
        .mret_i(mret_valid),
        .retire_i(retire_valid),
        .trap_pc_i(ie_inst_addr_o),
        .trap_cause_i(trap_cause),
        .trap_tval_i(trap_tval),
        .mtvec_o(csr_clint_csr_mtvec),
        .mepc_o(csr_clint_csr_mepc),
        .mstatus_o(csr_clint_csr_mstatus),
        .mie_o(csr_mie),
        .mip_o(csr_mip)
    );

    // if_id模块例化
    if_id u_if_id (
        .stall_i(WAIT_MEMORY && (memory_wait || debug_pause)),
        .fetch_error_i(WAIT_MEMORY && fetch_error),
        .fetch_error_o(if_fetch_error),
        .predicted_next_i(WAIT_MEMORY ? fetch_prediction : if_predicted_next),
        .predicted_next_o(id_predicted_next),
        .clk(clk),
        .rst(rst),
        .valid_i(WAIT_MEMORY ? (fetch_valid && fetch_consume) :
                 (!rib_hold_flag_i && !jtag_halt_flag_i && !jtag_reset_flag_i)),
        .valid_o(if_valid_o),
        .inst_i(WAIT_MEMORY ? fetch_data : rib_pc_data_i),
        .inst_addr_i(WAIT_MEMORY ? fetch_pc : pc_pc_o),
        .int_flag_i(int_i),
        .int_flag_o(if_int_flag_o),
        .hold_flag_i(pipe_control),
        .inst_o(if_inst_o),
        .inst_addr_o(if_inst_addr_o)
    );

    // id模块例化
    id u_id (
        .rst(rst),
        .inst_i(if_inst_o),
        .inst_addr_i(if_inst_addr_o),
        .reg1_rdata_i(regs_rdata1_o),
        .reg2_rdata_i(regs_rdata2_o),
        .ex_jump_flag_i(ex_jump_flag_o),
        .reg1_raddr_o(id_reg1_raddr_o),
        .reg2_raddr_o(id_reg2_raddr_o),
        .inst_o(id_inst_o),
        .inst_addr_o(id_inst_addr_o),
        .reg1_rdata_o(id_reg1_rdata_o),
        .reg2_rdata_o(id_reg2_rdata_o),
        .reg_we_o(id_reg_we_o),
        .reg_waddr_o(id_reg_waddr_o),
        .op1_o(id_op1_o),
        .op2_o(id_op2_o),
        .op1_jump_o(id_op1_jump_o),
        .op2_jump_o(id_op2_jump_o),
        .csr_rdata_i(csr_data_o),
        .csr_raddr_o(id_csr_raddr_o),
        .csr_we_o(id_csr_we_o),
        .csr_rdata_o(id_csr_rdata_o),
        .csr_waddr_o(id_csr_waddr_o)
    );

    // id_ex模块例化
    id_ex u_id_ex (
        .stall_i(WAIT_MEMORY &&
                 (memory_wait || (debug_pause && !data_complete && !divider_commit))),
        .fetch_error_i(if_fetch_error),
        .fetch_error_o(ex_fetch_error),
        .predicted_next_i(id_predicted_next),
        .predicted_next_o(ex_predicted_next),
        .clk(clk),
        .rst(rst),
        .valid_i(if_valid_o && !jtag_reset_flag_i &&
                 !(debug_pause && (data_complete || divider_commit))),
        .valid_o(ie_valid_o),
        .inst_i(id_inst_o),
        .inst_addr_i(id_inst_addr_o),
        .reg_we_i(id_reg_we_o),
        .reg_waddr_i(id_reg_waddr_o),
        .reg1_rdata_i(id_reg1_rdata_o),
        .reg2_rdata_i(id_reg2_rdata_o),
        .hold_flag_i(pipe_control),
        .inst_o(ie_inst_o),
        .inst_addr_o(ie_inst_addr_o),
        .reg_we_o(ie_reg_we_o),
        .reg_waddr_o(ie_reg_waddr_o),
        .reg1_rdata_o(ie_reg1_rdata_o),
        .reg2_rdata_o(ie_reg2_rdata_o),
        .op1_i(id_op1_o),
        .op2_i(id_op2_o),
        .op1_jump_i(id_op1_jump_o),
        .op2_jump_i(id_op2_jump_o),
        .op1_o(ie_op1_o),
        .op2_o(ie_op2_o),
        .op1_jump_o(ie_op1_jump_o),
        .op2_jump_o(ie_op2_jump_o),
        .csr_we_i(id_csr_we_o),
        .csr_waddr_i(id_csr_waddr_o),
        .csr_rdata_i(id_csr_rdata_o),
        .csr_we_o(ie_csr_we_o),
        .csr_waddr_o(ie_csr_waddr_o),
        .csr_rdata_o(ie_csr_rdata_o)
    );

    // ex模块例化
    ex u_ex (
        .rst(rst),
        .valid_i(ie_valid_o),
        .div_pending_i(div_pending),
        .inst_i(ie_inst_o),
        .inst_addr_i(ie_inst_addr_o),
        .reg_we_i(ie_reg_we_o),
        .reg_waddr_i(ie_reg_waddr_o),
        .reg1_rdata_i(ie_reg1_rdata_o),
        .reg2_rdata_i(ie_reg2_rdata_o),
        .op1_i(ie_op1_o),
        .op2_i(ie_op2_o),
        .op1_jump_i(ie_op1_jump_o),
        .op2_jump_i(ie_op2_jump_o),
        .mem_rdata_i(early_data_match ? data_lookup_data_i : rib_ex_data_i),
        .mem_wdata_o(ex_mem_wdata_o),
        .mem_raddr_o(ex_mem_raddr_o),
        .mem_waddr_o(ex_mem_waddr_o),
        .mem_we_o(raw_mem_we),
        .mem_req_o(raw_mem_req),
        .reg_wdata_o(ex_reg_wdata_o),
        .reg_we_o(raw_reg_we),
        .reg_waddr_o(ex_reg_waddr_o),
        .hold_flag_o(ex_hold_flag_o),
        .jump_flag_o(raw_jump),
        .jump_addr_o(raw_jump_addr),
        .int_assert_i(1'b0),
        .int_addr_i(32'b0),
        .div_ready_i(div_ready_o),
        .div_result_i(div_result_o),
        .div_busy_i(div_busy_o),
        .div_reg_waddr_i(div_reg_waddr_o),
        .div_start_o(raw_div_start),
        .div_dividend_o(ex_div_dividend_o),
        .div_divisor_o(ex_div_divisor_o),
        .div_op_o(ex_div_op_o),
        .div_reg_waddr_o(ex_div_reg_waddr_o),
        .csr_we_i(ie_csr_we_o),
        .csr_waddr_i(ie_csr_waddr_o),
        .csr_rdata_i(csr_data_o),
        .csr_wdata_o(ex_csr_wdata_o),
        .csr_we_o(raw_csr_we),
        .csr_waddr_o(ex_csr_waddr_o)
    );

    // div模块例化
    div u_div (
        .clk(clk),
        .rst(rst && !jtag_reset_flag_i),
        .dividend_i(ex_div_dividend_o),
        .divisor_i(ex_div_divisor_o),
        .start_i(ex_div_start_o),
        .op_i(ex_div_op_o),
        .reg_waddr_i(ex_div_reg_waddr_o),
        .result_o(div_result_o),
        .ready_o(div_ready_o),
        .busy_o(div_busy_o),
        .reg_waddr_o(div_reg_waddr_o)
    );

    // Legacy clint.v is retained for source history, not instantiated in V0.4.
endmodule
