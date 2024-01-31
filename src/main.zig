const std = @import("std");
const l = @import("ws2812.zig");
const b = @import("ms5611.zig");
pub const p = @cImport({
    //    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    @cInclude("stdio.h");
    @cInclude("hardware/gpio.h");
    @cInclude("pico/binary_info.h");
    @cInclude("ws2812.h");
    @cInclude("ws2812.pio.h"); // this file contains the pio program to handle the ws2812; it has been created outside this zig program.
    @cInclude("hardware/pio.h");
    @cInclude("hardware/i2c.h");
    @cInclude("i2c.h");
    
});

//setup of pio to handle ws2812 led
//const pio1 = @as(u32,  0x50300000); // rp2040 base register adress of pio1, change the address to 0x50200000 if you want to use pio0
const sm : u8 = 3; // state machine being used 
const led_gpio = 16; // gpio of the led on a rp2040-zero
var rgbLed : l.RgbLed = undefined;

// setup of I2C for baro sensor
const sda : u8 = 6; // gpio used for sda
const scl : u8 = 7; // gpio used for scl

var i2c1_zig : u32 = undefined;

var baro : b.Ms5611 = undefined;  // structure that keep baro sensor data and methods

pub fn setupI2c() void {
    // get from sdk the value used by sdk to identify i2c1 (it is stored in ram at power on)
    // initialize I2C     
    _ = p.i2c_init( i2c1_zig, 400 * 1000);
    p.gpio_set_function(sda, GPIO_FUNC_I2C);
    p.gpio_set_function(scl, GPIO_FUNC_I2C);
    p.gpio_pull_up(sda);
    p.gpio_pull_up(scl); 
}


const  GPIO_FUNC_I2C = @as(c_uint, 3); // 3 is the code used by RP2040 to assign gpio for I2C
var pio1Val : u32 = undefined;

export fn zig_main() c_int {
    _ = p.stdio_init_all();    // let sdk initialize the rp2040
//    pio1Val = p.getPio1() ;
    
    rgbLed.setupLed(sm , led_gpio);         // init a pio/sm to manage the led
    rgbLed.setRgbColor(0,0,10);   // select a color
    //rgbLed.setRgbOn();                   // turn led on (optional because it will be toggle in the loop)
    p.sleep_ms(3000);
    i2c1_zig = p.getI2c1();  // find the value used for i2c1 in pico sdk
    setupI2c();              // setup the i2c (here hardcoded on i2c1) with zig code

    rgbLed.setRgbOn();                   // turn led on (optional because it will be toggle in the loop)
    
    baro.begin(i2c1_zig);                   // perform a reset of ms5611 and get calibration
    while (true) {
        p.sleep_ms(1000);
        if (baro.isInstalled) {
            _ = p.printf("ms installed \n");
            _ = baro.get_altitude();
        } else {
            _ = p.printf("ms not installed %d\n", baro.err);
        }    
        rgbLed.toggleRgb(); // switch led ON/OFF
        _ = p.printf("program = %x", p.get_ws2812_program());
    }
}


//const gpio_function = enum(c_uint) {
//    GPIO_FUNC_XIP = 0,
//    GPIO_FUNC_SPI = 1,
//    GPIO_FUNC_UART = 2,
//    GPIO_FUNC_I2C = 3,
//    GPIO_FUNC_PWM = 4,
//    GPIO_FUNC_SIO = 5,
//    GPIO_FUNC_PIO0 = 6,
//    GPIO_FUNC_PIO1 = 7,
//    GPIO_FUNC_GPCK = 8,
//    GPIO_FUNC_USB = 9,
//    GPIO_FUNC_NULL = 0x1f,
//};
    


