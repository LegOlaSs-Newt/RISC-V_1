/*
 * 模块说明：机器态异常及中断入口。
 * 来源说明：本项目新增。
 * 主要改动：在精确指令边界选择同步异常或可受理中断，生成 trap CSR 更新及入口重定向。
 * 关键约束：数据错误属于发起该请求的指令；已提出的访存排空，不能以新中断撤销已完成写。仅实现 M 模式，不声明用户态或分页。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// V0.4 synchronous exception decoder. Original ALU/LSU stays in ex.v.
// No outputs depend on gated bus requests, so a fault cannot form a gate loop.
module trap_control #(parameter MEMORY_STATS=0)(
    input wire valid_i,
    input wire [31:0] pc_i, inst_i, rs1_i,
    input wire jump_i,
    input wire [31:0] jump_target_i,
    input wire csr_legal_i,
    output reg exception_o,
    output reg [31:0] cause_o, tval_o
);
    wire [6:0] op = inst_i[6:0];
    wire [2:0] f3 = inst_i[14:12];
    wire [6:0] f7 = inst_i[31:25];
    wire load = op == 7'h03;
    wire store = op == 7'h23;
    wire control = op == 7'h63 || op == 7'h6f || op == 7'h67;
    wire [31:0] address = rs1_i + (store ?
        {{20{inst_i[31]}},inst_i[31:25],inst_i[11:7]} :
        {{20{inst_i[31]}},inst_i[31:20]});
    wire misaligned = (f3[1:0] == 2'd1 && address[0]) ||
                      (f3[1:0] == 2'd2 && |address[1:0]);
    wire memory_ok = address < 32'h00004000 ||
                     (address >= 32'h10000000 && address < 32'h10004000);
    wire stats_ok = MEMORY_STATS && load && f3==2 &&
                    address>=32'h60000000 && address<32'h60000078;
    wire mmio_ok = f3 == 3'd2 && (
        address == 32'h20000000 || address == 32'h20000004 ||
        address == 32'h20000008 || address == 32'h2000000c ||
        address == 32'h30000000 || address == 32'h30000004 ||
        address == 32'h30000008 || address == 32'h3000000c ||
        address == 32'h30000010 ||
        address == 32'h40000000 || address == 32'h40000004 ||
        address == 32'h50000000 || address == 32'h50000004 ||
        address == 32'h50000008);
    reg legal;
    always @* begin
        legal = 1'b0;
        case (op)
            7'h37,7'h17,7'h6f: legal = 1'b1;
            7'h67: legal = f3 == 0;
            7'h63: legal = f3 == 0 || f3 == 1 || f3 >= 4;
            7'h03: legal = f3 == 0 || f3 == 1 || f3 == 2 || f3 == 4 || f3 == 5;
            7'h23: legal = f3 <= 2;
            7'h13: begin
                if (f3 == 1) legal = f7 == 0;
                else if (f3 == 5) legal = f7 == 0 || f7 == 7'h20;
                else legal = 1'b1;
            end
            7'h33: legal = f7 == 0 || f7 == 1 ||
                              (f7 == 7'h20 && (f3 == 0 || f3 == 5));
            // Reserved register/immediate fields are ignored for FENCE/FENCE.I.
            7'h0f: legal = f3 == 0 || f3 == 1;
            7'h73: begin
                if (f3 == 0)
                    legal = inst_i == 32'h00000073 || inst_i == 32'h00100073 ||
                            inst_i == 32'h30200073 || inst_i == 32'h10500073;
                else if (f3 != 4) legal = csr_legal_i;
            end
        endcase
        exception_o = 1'b0;
        cause_o = 0;
        tval_o = 0;
        if (valid_i) begin
            if (|pc_i[1:0]) begin
                exception_o = 1; cause_o = 0; tval_o = pc_i;
            end else if (pc_i >= 32'h4000) begin
                exception_o = 1; cause_o = 1; tval_o = pc_i;
            end else if (!legal) begin
                exception_o = 1; cause_o = 2; tval_o = inst_i;
            end else if (control && jump_i && |jump_target_i[1:0]) begin
                exception_o = 1; cause_o = 0; tval_o = jump_target_i;
            end else if ((load || store) && misaligned) begin
                exception_o = 1; cause_o = store ? 6 : 4; tval_o = address;
            end else if ((load || store) && !(memory_ok || mmio_ok || stats_ok)) begin
                exception_o = 1; cause_o = store ? 7 : 5; tval_o = address;
            end else if (inst_i == 32'h00000073) begin
                exception_o = 1; cause_o = 11;
            end else if (inst_i == 32'h00100073) begin
                exception_o = 1; cause_o = 3;
            end
        end
    end
endmodule

