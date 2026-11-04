add wave -group Clock /tinyriscv_lab_tb/clk /tinyriscv_lab_tb/rst
add wave -group Pipeline -radix hexadecimal /tinyriscv_lab_tb/pc /tinyriscv_lab_tb/fetch_inst /tinyriscv_lab_tb/id_pc /tinyriscv_lab_tb/id_inst /tinyriscv_lab_tb/ex_pc /tinyriscv_lab_tb/ex_inst
add wave -group Writeback /tinyriscv_lab_tb/wb_we
add wave -group Writeback -radix unsigned /tinyriscv_lab_tb/wb_rd
add wave -group Writeback -radix hexadecimal /tinyriscv_lab_tb/wb_data /tinyriscv_lab_tb/x1 /tinyriscv_lab_tb/x2 /tinyriscv_lab_tb/x3 /tinyriscv_lab_tb/x4 /tinyriscv_lab_tb/x5 /tinyriscv_lab_tb/x6 /tinyriscv_lab_tb/x26 /tinyriscv_lab_tb/x27
add wave -group Control /tinyriscv_lab_tb/hold_flag /tinyriscv_lab_tb/jump_flag
add wave -group Control -radix hexadecimal /tinyriscv_lab_tb/jump_addr
add wave -group Memory /tinyriscv_lab_tb/mem_req /tinyriscv_lab_tb/mem_we
add wave -group Memory -radix hexadecimal /tinyriscv_lab_tb/mem_addr /tinyriscv_lab_tb/mem_wdata /tinyriscv_lab_tb/mem_rdata
