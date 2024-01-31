const std = @import("std");
pub const p = @cImport({
    //    @cInclude("stdio.h");
    @cInclude("pico/stdlib.h");
    @cInclude("stdio.h");

    @cInclude("hardware/gpio.h");
    @cInclude("hardware/i2c.h");
});

const CMD_READ_ADC        = @as(u8,0x00);
const CMD_READ_PROM       = @as(u8,0xA0);
const CMD_RESET           = @as(u8,0x1E);
const CMD_CONVERT_D1      = @as(u8,0x40);
const CMD_CONVERT_D2      = @as(u8,0x50);

pub const Ms5611 = struct {
    i2c : u32, // base register of the pio being used
    adr : u8,  // i2c address of sensor 
    //sda : u8,   // gpio for sda
    //scl : u8,   // gpio for scl
    d1 : u32 = 0, 
    d2 : u32 = 0,
    d2_prev : u32 = 0, 
    isInstalled: bool, // true when sensor is installed/detected
    lastRead: u32, // last time sensor has been read
    lastConversionRequest : u32 = 0,
    lastTempRequest : u32 = 0,
    prevAltMicros : u32 = 0,
    state: Ms5611State ,     // keep state process
    calibrationData : [8]u16, // calibration data
    err: i32,        // just for testing the error on i2c
    altitude_cm : i32,   //Altitude in cm    
    pub fn begin(self: *Ms5611 , i2c1_zig : u32) void{
        self.i2c=i2c1_zig;
        self.adr = 0x77;
        self.isInstalled = false;
        self.lastRead=0;
        self.state=Ms5611State.noState;
        self.err=0;
        // reset the ms5611
        self.command(CMD_RESET);
        if (self.err > 0) {
        //var i2cError : i32 = p.i2c_write_timeout_us (self.i2c , self.adr , &CMD_RESET , 1 , false, 1000) ;
        //if (i2cError < 0 ) {// ask for a reset
            _ = p.printf("error on I2C reset command\n");
            self.err = 1;
            return;      
        }
    
        p.sleep_ms(10);

        // read factory calibrations from EEPROM.
        var buffer : [2]u8 = undefined;
        for (0..8) |i| {
            self.calibrationData[i] = 0;
            const ic : u8 = @truncate(i);
            const cmdw = CMD_READ_PROM + ic * 2 ; // this is the address to be read
            self.command(cmdw); 
            //buffer[0] = CMD_READ_PROM + ic * 2 ; // this is the address to be read
            //i2cError = p.i2c_write_timeout_us (self.i2c , self.adr, &buffer[0] , 1 , false , 1000);
            //if (  i2cError < 0 ) {
            if (self.err > 0) {
                _ = p.printf("error write calibration MS5611 \n");
                self.err = 2;
                return ; // command to get access to one register '0xA0 + 2* offset
            }

            var i2cError : i32= p.i2c_read_timeout_us (self.i2c , self.adr , &buffer[0] , 2 , false, 1500);
            if ( i2cError < 0)  {
                _ = p.printf("error read calibration MS5611: %i\n",i2cError);
                self.err = 3;
                return ;
            }  
            self.calibrationData[i] = (@as(u16,buffer[0])<<8 ) | @as(u16,buffer[1] );
            _ = p.printf("cal=%x\n",self.calibrationData[i]) ;    
        }
        if (ms5611_crc(&self.calibrationData) != 0) {
            _ = p.printf("error in CRC of calibration for MS5611\n");
            self.err = 9;
            return;  // Check the crc
        }
        _ = p.printf("MS5611 sensor is successfully detected\n");
  
        self.isInstalled = true; // if we reach this point, baro is installed (and calibration is loaded)
    }
    
    // to do check for error
    pub fn command ( self: *Ms5611 , cmd : u8) void {
        const buf  = [1]u8{ cmd };
        self.err = 0;
        const i2cError : i32= p.i2c_write_timeout_us (self.i2c , self.adr, &buf[0] , 1 , false, 1000);
        if ( i2cError < 0 ) { // i2c_write return the number of byte written or an error code
            _ = p.printf("error write MS5611 cmd: %i\n",i2cError);
            self.err = 4;
        }        
    }

    pub fn read_adc(self: *Ms5611) u32{
        var buf : [3]u8 = undefined;
        var adc_value :u32 = 0;
        var i2cError : i32 = 0;
        self.err = 0;
        self.command(CMD_READ_ADC);
        if (self.err == 0) {
            i2cError = p.i2c_read_timeout_us (self.i2c , self.adr, &buf[0] , 3 , false, 1500);
            if (i2cError >= 0) {
                adc_value = ((@as(u32, buf[0])) << 16) | ((@as(u32, buf[1])) << 8) | ((@as(u32, buf[2])) ); 
                _ = p.printf("adc = %x\n", adc_value);
            } else {
                _ = p.printf("error reading MS5611 %i\n",i2cError);
                self.err = 5;
            }
        }    
        return adc_value;
    }

// -- END OF FILE --
// Try to get a new pressure 
// MS5611 requires some delay between asking for a conversion and getting the result
// in order not to block the process, we use a state
// If state = 1, it means we asked for a pressure conversion; we can read it if delay is long enough; we ask for a temp conversion
// If state = 2, it means we asked for a temperature conversion; we can read it if delay is long enough
// if state = 0, we have to
// return 0 if a new value is calculated; -1 if no calculation was performed; other in case of I2C error
// when a value is calculated, then altitude, rawPressure and temperature are calculated.
    pub fn get_altitude(self : *Ms5611) i32 {
        if (self.isInstalled == false) return -1;
        if ( p.to_us_since_boot(p.get_absolute_time ()) -% self.lastConversionRequest < 9500 ) return -1; // -% is to have wrapping like C
        if (self.state == Ms5611State.noState) {
            self.command(0x48);
            if (self.err == 0) {
                self.lastConversionRequest = @truncate(p.to_us_since_boot(p.get_absolute_time ()));
                self.state = Ms5611State.waitForPressure;
            }
        } else if (self.state == Ms5611State.waitForPressure ) {
            self.d1 = self.read_adc();
            if (self.err > 0) return -1;
            self.command(0x58);
            if (self.err > 0) return -1;
            self.lastConversionRequest = @truncate(p.to_us_since_boot(p.get_absolute_time ()));
            self.lastTempRequest = self.lastConversionRequest;    
            self.state = Ms5611State.waitForTemperature;
        } else if (self.state == Ms5611State.waitForTemperature ) {
            self.d2 = self.read_adc();
            if (self.err > 0) return -1;
            self.command(0x48);
            if (self.err > 0) return -1;
            self.lastConversionRequest = @truncate(p.to_us_since_boot(p.get_absolute_time ()));
            self.state = Ms5611State.waitForPressure;
            self.calculateAltitude();        
            return 0;
        }
        return -1;
    }

    pub fn calculateAltitude(self : *Ms5611) void {
        if (self.d2_prev == 0) {
            self.d2_prev = self.d2;
            self.prevAltMicros = self.lastTempRequest;
        }
        const dt : i64 =  ((@as(i64, self.d2) +  @as(i64, self.d2_prev)) >> 1 ) -
                            (@as(i64, self.calibrationData[5]) << 8 );
        const temp : i32 = @truncate(2000 + (( dt * @as(i64,self.calibrationData[6]) ) >> 23  )) ; 
        self.d2_prev = self.d2; 
        const off : i64 =  (@as(i64,self.calibrationData[2]) << 16) + 
                           ((@as(i64,self.calibrationData[4]) * dt ) >> 7  );
        const sens : i64 =  (@as(i64,self.calibrationData[1]) << 15) + 
                           ((@as(i64,self.calibrationData[3]) * dt ) >> 8  );
        const raw_pressure : i64 =  ((((@as(i64, self.d1) * sens) >> 21 ) - off ) * 10000 ) >> 15 ;
        const actual_pressure_pa : f64 = @as(f64,@floatFromInt(raw_pressure)) * 0.0001;
        // altitude (m) = 44330 * (1.0 - pow(pressure in pa /sealevelPressure , 0.1903));
        const altitudeCm : f64 = 4433000.0 * (1.0 - std.math.pow(f64, actual_pressure_pa / 101325.0, 0.1903)); // 101325 is pressure at see level in Pa; altitude is in cm
        _ = p.printf("pressure = %f   temp= %i    alt= %f\n",actual_pressure_pa, temp, altitudeCm);
        
        //const altIntervalMicros :u32 = self.lastTempRequest -% self.prevAltMicros;
        self.prevAltMicros = self.lastTempRequest;                                 
    }
    
}; // end struct

const Ms5611State = enum {
    noState,
    waitForPressure,
    waitForTemperature,
};

const Ms5611Error = error {
    I2cWriteError,
    I2cReadError,
};


fn ms5611_crc(prom : *[8]u16) i8 {
    _ = p.printf("prom7 before %x\n",prom[7]);
    var res : u32 = 0;
    var crc : u8 = @truncate(prom[7]);
    crc = crc & 0xF;
    prom[7] = prom[7] & 0xFF00 ;
    _ = p.printf("prom7 after %x\n",prom[7]);
    var blankEeprom : bool = true;

    for (0..16) |i| {
        const id2 : u32 = i >> 1;
        if (prom[id2] > 0) {blankEeprom = false;}
        if ((i & 1) == 1) {
            res = res ^ (prom[id2] & 0x00FF);
        } else {
            res = res ^ (prom[id2] >> 8);
        }
        for (0..8) |_| {
            if ((res & 0x8000) > 0) {
                res = res ^ 0x1800;
            }
            res = res << 1; 
        } // end first for
    }// end for
    prom[7] |= crc;
    _ = p.printf("prom7 restored %x\n",prom[7]);
    
    if (!blankEeprom and (crc == ((res >> 12) & 0xF))) return 0;
    return -1;   // -1 = error
}
