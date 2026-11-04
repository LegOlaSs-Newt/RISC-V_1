/*
 * 模块说明：可下载程序存储器。
 * 来源说明：基于 TinyRISC-V 对应模块修改扩展，原声明按文件保存在 licenses/SOURCE_NOTICES.md。
 * 主要改动：保存启动镜像并支持 UART 主机写入，Wait 模式使用同步读 DRM。
 * 关键约束：程序区可写，CPU 自修改代码后须 FENCE.I；数据阵列不逐字复位，启动内容由构建镜像决定。
 * 许可位置：提交根 licenses，第三方固定原件保留自身声明。
 */
`include "../core/defines.v"
`include "../../boot_image_path.vh"


module rom #(
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

    reg [`MemBus] _rom[0:`RomNum - 1];

    // MES50HP port: include the demo firmware in the FPGA configuration.
    // UART writes can subsequently replace this volatile program image.
    initial $readmemh(`MES50HP_BOOT_MEM, _rom);


    always @(posedge clk) begin
        if (we_i == `WriteEnable) begin
            if (!SYNC_READ) _rom[addr_i[31:2]] <= data_i;
            else begin
                if (wstrb_i[0]) _rom[addr_i[13:2]][7:0] <= data_i[7:0];
                if (wstrb_i[1]) _rom[addr_i[13:2]][15:8] <= data_i[15:8];
                if (wstrb_i[2]) _rom[addr_i[13:2]][23:16] <= data_i[23:16];
                if (wstrb_i[3]) _rom[addr_i[13:2]][31:24] <= data_i[31:24];
            end
        end
    end

    generate
        if (SYNC_READ) begin : synchronous_read
            always @(posedge clk) if (read_en_i) data_o <= _rom[addr_i[13:2]];
        end else begin : legacy_read
            always @(*) begin
                if (rst == `RstEnable) begin
                    data_o = `ZeroWord;
                end else begin
                    data_o = _rom[addr_i[31:2]];
                end
            end
        end
    endgenerate

endmodule
