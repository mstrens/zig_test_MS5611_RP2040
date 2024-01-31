
#include <stdio.h>
#include <stdlib.h>

#include "pico/stdlib.h"

#include "ws2812.h"

//link_with_pico_sdk.c
//extern "C" void zig_main();
extern void zig_main();

int main()
{
    zig_main();
    return 0;
}

/* for information here are the base address of main rp2040 registers; usefull when using some sdk commands (e.g. for i2c, pio, ...)
#define UART0_BASE _u(0x40034000)
#define UART1_BASE _u(0x40038000)
#define SPI0_BASE _u(0x4003c000)
#define SPI1_BASE _u(0x40040000)
#define I2C0_BASE _u(0x40044000)
#define I2C1_BASE _u(0x40048000)
#define ADC_BASE _u(0x4004c000)
#define PWM_BASE _u(0x40050000)
#define TIMER_BASE _u(0x40054000)
#define WATCHDOG_BASE _u(0x40058000)
#define RTC_BASE _u(0x4005c000)
#define ROSC_BASE _u(0x40060000)
#define VREG_AND_CHIP_RESET_BASE _u(0x40064000)
#define TBMAN_BASE _u(0x4006c000)
#define DMA_BASE _u(0x50000000)
#define USBCTRL_DPRAM_BASE _u(0x50100000)
#define USBCTRL_BASE _u(0x50100000)
#define USBCTRL_REGS_BASE _u(0x50110000)
#define PIO0_BASE _u(0x50200000)
#define PIO1_BASE _u(0x50300000)
#define XIP_AUX_BASE _u(0x50400000)
#define SIO_BASE _u(0xd0000000)
#define PPB_BASE _u(0xe0000000) 
*/