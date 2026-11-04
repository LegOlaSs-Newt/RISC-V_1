OUTPUT_ARCH(riscv)
ENTRY(_start)
MEMORY {
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 16K
    RAM (rw) : ORIGIN = 0x10000000, LENGTH = 16K
}
SECTIONS {
    .text : { KEEP(*(.init)) *(.text*) *(.rodata*) . = ALIGN(4); } > ROM
    .data : {
        __data_start = .;
        *(.data*) *(.sdata*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM AT> ROM
    __data_load = LOADADDR(.data);
    __global_pointer$ = ORIGIN(RAM) + 0x800;
    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss*) *(.sbss*) *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
    ASSERT(__bss_end <= __stack_top - 1024, "RAM data leaves less than 1 KiB of stack")
}
