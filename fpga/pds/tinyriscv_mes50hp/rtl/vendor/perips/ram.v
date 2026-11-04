/*
 * 模块说明：字节写数据存储器。
 * 来源说明：基于 TinyRISC-V 对应模块修改扩展，原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：提供 16 KiB RAM 和四字节写使能，Wait 模式采用同步读。
 * 关键约束：字节掩码逐项保留，不依赖同地址双端口碰撞返回；全局复位不承诺擦除存储内容。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "../core/defines.v"

// ram module
module ram #(
    parameter SYNC_READ = 0
) (

    input wire clk,
    input wire rst,

    input wire               we_i,       // write enable
    input wire [`MemAddrBus] addr_i,     // addr
    input wire [    `MemBus] data_i,
    input wire               read_en_i,
    input wire [        3:0] wstrb_i,

    output reg [`MemBus] data_o  // read data

);

    reg [`MemBus] _ram[0:`MemNum - 1];


    always @(posedge clk) begin
        if (we_i == `WriteEnable) begin
            if (!SYNC_READ) _ram[addr_i[31:2]] <= data_i;
            else begin
                if (wstrb_i[0]) _ram[addr_i[13:2]][7:0] <= data_i[7:0];
                if (wstrb_i[1]) _ram[addr_i[13:2]][15:8] <= data_i[15:8];
                if (wstrb_i[2]) _ram[addr_i[13:2]][23:16] <= data_i[23:16];
                if (wstrb_i[3]) _ram[addr_i[13:2]][31:24] <= data_i[31:24];
            end
        end
    end

    generate
        if (SYNC_READ) begin : synchronous_read
            always @(posedge clk) if (read_en_i) data_o <= _ram[addr_i[13:2]];
        end else begin : legacy_read
            always @(*) begin
                if (rst == `RstEnable) begin
                    data_o = `ZeroWord;
                end else begin
                    data_o = _ram[addr_i[31:2]];
                end
            end
        end
    endgenerate

endmodule
