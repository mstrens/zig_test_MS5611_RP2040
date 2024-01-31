#include <stdio.h>
#include <stdlib.h>

#include "pico/stdlib.h"
#include "hardware/i2c.h"
#include "hardware/clocks.h"
#include "i2c.h"



uint32_t getI2c1(){
    //printf("i2c=%x , *i2c=%x\n",i2c1, *i2c1);
    return (uint32_t) i2c1;
}

uint32_t getI2c0(){ 
    return (uint32_t) i2c0;
}

