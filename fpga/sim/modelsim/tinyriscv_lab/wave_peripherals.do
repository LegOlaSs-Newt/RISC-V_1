add wave -group GPIO /tinyriscv_lab_tb/gpio_pins /tinyriscv_lab_tb/gpio_drive
add wave -group GPIO -radix hexadecimal /tinyriscv_lab_tb/gpio_ctrl /tinyriscv_lab_tb/gpio_data
add wave -group UART /tinyriscv_lab_tb/uart_tx /tinyriscv_lab_tb/uart_rx
add wave -group UART -radix hexadecimal /tinyriscv_lab_tb/uart_status /tinyriscv_lab_tb/uart_baud /tinyriscv_lab_tb/uart_state /tinyriscv_lab_tb/uart_bit
add wave -group Timer -radix unsigned /tinyriscv_lab_tb/timer_count /tinyriscv_lab_tb/timer_value /tinyriscv_lab_tb/interrupt_edges
add wave -group Timer -radix hexadecimal /tinyriscv_lab_tb/timer_ctrl /tinyriscv_lab_tb/mtvec /tinyriscv_lab_tb/mepc
add wave -group Timer /tinyriscv_lab_tb/timer_int
add wave -group SPI /tinyriscv_lab_tb/spi_ss /tinyriscv_lab_tb/spi_clk /tinyriscv_lab_tb/spi_mosi /tinyriscv_lab_tb/spi_miso
add wave -group SPI -radix hexadecimal /tinyriscv_lab_tb/spi_status
