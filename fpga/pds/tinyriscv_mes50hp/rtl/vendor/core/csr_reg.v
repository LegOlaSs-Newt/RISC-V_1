/*
 * 模块说明：机器态 CSR 寄存器。
 * 来源说明：基于 TinyRISC-V 对应文件；原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：本轮整理排版及中文说明，既有实现和成功判据保持；功能修改记录见板级 MODIFICATIONS.md。
 * 关键约束：以当前接口、配置和实际执行记录为准；测试、实现和实板结果分别登记，不使用旧结果代替新执行。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
// MES50HP V0.4: EX CSR access, atomic trap state, M-only WARL fields.
// Architecture reference: privileged 20260120 sections 3.1.6-3.1.16, 3.3.2.
module csr_reg (
    input wire clk,
    rst,
    input wire we_i,
    input wire [11:0] raddr_i,
    waddr_i,
    input wire [31:0] data_i,
    output reg [31:0] data_o,
    input wire access_write_i,
    output reg access_legal_o,
    input wire [7:0] int_i,
    input wire trap_i,
    mret_i,
    retire_i,
    input wire [31:0] trap_pc_i,
    trap_cause_i,
    trap_tval_i,
    output wire [31:0] mtvec_o,
    mepc_o,
    mstatus_o,
    mie_o,
    mip_o
);
    reg [63:0] cycle, instret;
    reg [31:0] mtvec, mepc, mcause, mtval, mie, mstatus, mscratch;
    reg  [31:0] mcountinhibit;
    wire [31:0] mip = {20'b0, int_i[2], 3'b0, int_i[0], 3'b0, int_i[1], 3'b0};
    assign mtvec_o = mtvec;
    assign mepc_o = mepc;
    assign mstatus_o = mstatus;
    assign mie_o = mie;
    assign mip_o = mip;
    always @* begin
        access_legal_o = 1'b1;
        data_o = 0;
        case (raddr_i)
            12'h300: data_o = mstatus;
            12'h301: data_o = 32'h40001100;
            12'h304: data_o = mie;
            12'h305: data_o = mtvec;
            12'h310: data_o = 0;
            12'h320: data_o = mcountinhibit;
            12'h340: data_o = mscratch;
            12'h341: data_o = mepc;
            12'h342: data_o = mcause;
            12'h343: data_o = mtval;
            12'h344: data_o = mip;
            12'hb00, 12'hc00: data_o = cycle[31:0];
            12'hb80, 12'hc80: data_o = cycle[63:32];
            12'hb02, 12'hc02: data_o = instret[31:0];
            12'hb82, 12'hc82: data_o = instret[63:32];
            12'hf11, 12'hf12, 12'hf13, 12'hf14, 12'hf15: data_o = 0;
            default: access_legal_o = 1'b0;
        endcase
        if (access_write_i && raddr_i[11:10] == 2'b11) access_legal_o = 1'b0;
    end
    always @(posedge clk) begin
        if (!rst) begin
            cycle <= 0;
            instret <= 0;
            mtvec <= 0;
            mepc <= 0;
            mcause <= 0;
            mtval <= 0;
            mie <= 0;
            mstatus <= 32'h1800;
            mscratch <= 0;
            mcountinhibit <= 0;
        end else begin
            if (!mcountinhibit[0]) cycle <= cycle + 1'b1;
            if (retire_i && !mcountinhibit[2]) instret <= instret + 1'b1;
            if (trap_i) begin
                mepc <= {trap_pc_i[31:2], 2'b00};
                mcause <= trap_cause_i;
                mtval <= trap_tval_i;
                mstatus <= 32'h1800 | (mstatus[3] ? 32'h80 : 32'h0);
            end else if (mret_i) begin
                mstatus <= 32'h1880 | (mstatus[7] ? 32'h8 : 32'h0);
            end else if (we_i) begin
                case (waddr_i)
                    12'h300: mstatus <= (data_i & 32'h88) | 32'h1800;
                    12'h304: mie <= data_i & 32'h888;
                    12'h305: mtvec <= {data_i[31:2], 2'b00} | (data_i[1:0] == 1 ? 32'h1 : 32'h0);
                    12'h320: mcountinhibit <= data_i & 32'h5;
                    12'h340: mscratch <= data_i;
                    12'h341: mepc <= {data_i[31:2], 2'b00};
                    12'h342: mcause <= data_i;
                    12'h343: mtval <= data_i;
                    12'hb00: cycle <= {cycle[63:32], data_i};
                    12'hb80: cycle <= {data_i, cycle[31:0]};
                    12'hb02: instret <= {instret[63:32], data_i};
                    12'hb82: instret <= {data_i, instret[31:0]};
                endcase
            end
        end
    end
endmodule
