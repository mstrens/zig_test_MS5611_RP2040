cmake_minimum_required(VERSION 3.25)
#modified by mstrens because it do not work with the PATH

# Initialize the Pico SDK
#include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)
include(pico_sdk_import.cmake)

project(my_project LANGUAGES C CXX)

# initialize the Raspberry Pi Pico SDK
pico_sdk_init()


# rest of your project
add_executable(zig_test)

file(GLOB C_SRC CONFIGURE_DEPENDS "src/*.h" "src/*.cpp" "src/*.c")

target_sources(zig_test PRIVATE ${C_SRC})

add_library(zig_library STATIC IMPORTED)
set_property(TARGET zig_library PROPERTY IMPORTED_LOCATION ../zig-out/lib/libzig-pico.a)


# Add the standard library to the build (the c file, the lib from zig and the stdlib)
target_link_libraries(zig_test 
    zig_library
    pico_stdlib
    hardware_pio
    hardware_watchdog
        pico_multicore
        hardware_pio
        hardware_i2c
        hardware_timer
        hardware_dma
        hardware_irq
        hardware_adc
        hardware_pwm
    
)

# enable usb output, disable uart output
    pico_enable_stdio_usb(zig_test 1)
    pico_enable_stdio_uart(zig_test 0)

# create map/bin/hex/uf2 file in addition to ELF.
pico_add_extra_outputs(zig_test)














#project(mlem)
#pico_sdk_init()
#add_executable(mlem)

#if (STDIO_USB)
#    pico_enable_stdio_uart(mlem 0)
#    pico_enable_stdio_usb(mlem 1)
#endif()

#if (STDIO_UART)
#    pico_enable_stdio_uart(mlem 1)
#    pico_enable_stdio_usb(mlem 0)   
#endif()

#target_link_libraries(mlem pico_stdlib  ${CMAKE_SOURCE_DIR}/zig-out/mlem.o)

#pico_add_extra_outputs(mlem)