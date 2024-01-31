
#include <stdio.h>
#include <stdlib.h>

#include "pico/stdlib.h"
#include "hardware/pio.h"
#include "hardware/clocks.h"
#include "ws2812.pio.h"
#include "hardware/watchdog.h"

#include "ws2812.h"

// this funcion is a wrapper for an sdk function just because I do not know how to call pio_add_program() directly from zig
// due to the &ws2812_program parameter.
//uint32_t get_offset(uint32_t pio){      
//        pio_hw_t * c_pio = (void*) pio;
//        return pio_add_program(c_pio, &ws2812_program);
//}

uint32_t getPio1(){
    return (uint32_t) pio1;
}

uint32_t get_ws2812_program() {
    return (uint32_t) &ws2812_program;
}

