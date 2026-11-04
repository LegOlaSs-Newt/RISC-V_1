# Watch the current Port/simple build produced with GCC -O0 and link.lds.
# main uses s0=0x10004000, sum at s0-24, and i at s0-20.
# These locations are specific to this build; recheck program.dis after edits.
# Add these objects before restarting so their complete history is recorded.
view wave
add wave -group Simple_C_Variables -radix unsigned -label mul {/tinyriscv_lab_tb/dut/u_ram/_ram[0]}
add wave -group Simple_C_Variables -radix unsigned -label divisor {/tinyriscv_lab_tb/dut/u_ram/_ram[1]}
add wave -group Simple_C_Variables -radix unsigned -label sum {/tinyriscv_lab_tb/dut/u_ram/_ram[4090]}
add wave -group Simple_C_Variables -radix unsigned -label i {/tinyriscv_lab_tb/dut/u_ram/_ram[4091]}
add wave -group Simple_C_Runtime -radix hexadecimal -label sp_x2 /tinyriscv_lab_tb/x2
add wave -group Simple_C_Runtime -radix hexadecimal -label gp_x3 /tinyriscv_lab_tb/x3
add wave -group Simple_C_Runtime -radix hexadecimal -label s0_x8 {/tinyriscv_lab_tb/dut/u_tinyriscv/u_regs/regs[8]}
add wave -group Simple_Division -label div_busy /tinyriscv_lab_tb/dut/u_tinyriscv/div_busy_o
add wave -group Simple_Division -label div_ready /tinyriscv_lab_tb/dut/u_tinyriscv/div_ready_o
add wave -group Simple_Division -radix unsigned -label div_result /tinyriscv_lab_tb/dut/u_tinyriscv/div_result_o
configure wave -timelineunits ns
radix signal /tinyriscv_lab_tb/ex_pc hexadecimal
radix signal /tinyriscv_lab_tb/ex_inst hexadecimal
