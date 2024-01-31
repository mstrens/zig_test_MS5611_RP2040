// this is the version from github nemuibanila with some changes in order to remove pico-w by pico board 
// it uses addStaticLib instead of addObject to create an object and then call Cmake and make
// it is supposed to create libzig-pico.a in zig-out/lib
// generated uf2 is in build
// this version is supposed to work on windows and linux.

const std = @import("std");
const builtin = @import("builtin");

const Board = "pico";

// RP2040 -- This includes a specific header file.
const IsRP2040 = true;

// Choose whether Stdio goes to USB or UART
const StdioUsb = true;
const PicoStdlibDefine = if (StdioUsb) "LIB_PICO_STDIO_USB" else "LIB_PICO_STDIO_UART";

// Pico SDK path can be specified here for your convenience
const PicoSDKPath: ?[]const u8 = null;
//const PicoSDKPath: ?[]const u8 = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk";

// arm-none-eabi includes patch must be specified here
const arm_none_eabi_include_path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/gcc-arm-none-eabi/arm-none-eabi/include";

pub fn build(b: *std.Build) anyerror!void {

    // ------------------
    const target = std.zig.CrossTarget{
        .abi = .eabi,
        .cpu_arch = .thumb,
        .cpu_model = .{ .explicit = &std.Target.arm.cpu.cortex_m0plus },
        .os_tag = .freestanding,
    };

    const optimize = b.standardOptimizeOption(.{});

    //const lib = b.addObject(.{
    const lib = b.addStaticLibrary(.{ // tested by mstrens

        .name = "zig-pico",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    // get and perform basic verification on the pico sdk path
    // if the sdk path contains the pico_sdk_init.cmake file then we know its correct
    
    // get the PICO_SDK_PATH from the os (works for all types of os)
    const pico_sdk_path = blk :{
        if (PicoSDKPath) |sdk_path| break: blk sdk_path
        else {
            //if (std.process.getEnvVarOwned(allocator,"PICO_SDK_PATH") ) |value| break : blk value else |_| { 
            if (std.process.getEnvVarOwned(b.allocator,"PICO_SDK_PATH") ) |value| break : blk value else |_| { 
            
                std.log.err("The Pico SDK path must be set either through the PICO_SDK_PATH environment variable or at the top of build.zig.", .{});
                return;          
            }
        }
    };      

    const pico_init_cmake_path = b.pathJoin(&.{ pico_sdk_path, "pico_sdk_init.cmake" });
    std.fs.cwd().access(pico_init_cmake_path, .{}) catch {
        std.log.err(
            \\Provided Pico SDK path does not contain the file pico_sdk_init.cmake
            \\Tried: {s}
            \\Are you sure you entered the path correctly?"
        , .{pico_init_cmake_path});
        return;
    };

    // default arm-none-eabi includes
    
    lib.linkLibC();
    //lib.addSystemIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/gcc-arm-none-eabi/arm-none-eabi/include" });
    lib.addSystemIncludePath(.{ .path = arm_none_eabi_include_path });


    //const find = try b.findProgram(&.{"find"}, &.{});

    // find the board header
    const board_header = blk: {
        const boards_directory_path = b.pathJoin(&.{ pico_sdk_path, "src/boards/include/boards/" });
        var boards_dir = try std.fs.cwd().openIterableDir(boards_directory_path, .{});
        defer boards_dir.close();

        var it = boards_dir.iterate();
        while (try it.next()) |file| {
            if (std.mem.containsAtLeast(u8, file.name, 1, Board)) {
                // found the board header
                break :blk file.name;
            }
        }
        std.log.err("Could not find the header file for board '{s}'\n", .{Board});
        return;
    };

    // Autogenerate the header file like the pico sdk would
    const cmsys_exception_prefix = if (IsRP2040) "" else "//";
    const header_str = try std.fmt.allocPrint(b.allocator,
        \\#include "{s}/src/boards/include/boards/{s}"
        \\{s}#include "{s}/src/rp2_common/cmsis/include/cmsis/rename_exceptions.h"
    , .{ pico_sdk_path, board_header, cmsys_exception_prefix, pico_sdk_path });

    // Write and include the generated header
    const config_autogen_step = b.addWriteFile("pico/config_autogen.h", header_str);
    lib.step.dependOn(&config_autogen_step.step);  // so we create the file before running the lib step.

    lib.addIncludePath(config_autogen_step.getDirectory());

    // requires running cmake at least once
    lib.addSystemIncludePath(.{ .path = "build/generated/pico_base" });

    // Search for all directories "include" in `src` and add them
    {
        const pico_sdk_src = try std.fmt.allocPrint(b.allocator, "{s}/src", .{pico_sdk_path});
        var dir = try std.fs.cwd().openIterableDir(pico_sdk_src, .{
            .no_follow = true, // `true` means it won't dereference the symlinks.
        });
        var walker = try dir.walk(b.allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            // |entry| has 4 fileds : dir, basename,path,kind; basename seems to be the last part in the path, path is the full path
            if (std.mem.eql(u8,entry.basename,"include")) {
                if (! std.mem.containsAtLeast(u8, entry.path, 1, "host")) {
                    const pico_sdk_include = try std.fmt.allocPrint(b.allocator, "{s}\\src\\{s}", .{pico_sdk_path,entry.path});
                    lib.addIncludePath(std.build.LazyPath{.path = pico_sdk_include}); 
                    //std.debug.print("{s}\n", .{pico_sdk_include});
                }
            }
        }
    }


    // Define UART or USB constant for headers
    lib.defineCMacroRaw(PicoStdlibDefine);  // set up for usb or uart

    // those are the path given by original program when it runs on linux.
    // the new code is supposed to generate the same path also for windows.
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/pico_time/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/pico_util/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/pico_binary_info/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/pico_usb_reset_interface/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/pico_sync/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/pico_divider/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/pico_bit_ops/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/pico_base/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/pico_stdlib/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/boot_picoboot/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/common/boot_uf2/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_pio/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_spi/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_resets/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_stdio/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_lwip/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_claim/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_adc/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_sync/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_double/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_rand/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_stdio_usb/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_int64_ops/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_cyw43_driver/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_pll/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_vreg/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_cyw43_arch/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_rtc/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_i2c/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_xosc/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_stdio_semihosting/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_multicore/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_base/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_unique_id/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/boot_stage2/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_platform/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_timer/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_printf/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_flash/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_divider/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_malloc/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_watchdog/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_bootrom/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_fix/rp2040_usb_device_enumeration/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_mem_ops/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_float/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_btstack/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_uart/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_runtime/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_pwm/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/cmsis/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_i2c_slave/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_exception/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_dma/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_async_context/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_flash/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_interp/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/pico_stdio_uart/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_gpio/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_irq/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2_common/hardware_clocks/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/boards/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2040/hardware_regs/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/src/rp2040/hardware_structs/include" });
    //lib.addIncludePath(.{ .path = "C:/Program Files/Raspberry Pi/Pico SDK v1.5.1/pico-sdk/lib/lwip/src/include" });

    // required for pico_w wifi
//    lib.defineCMacroRaw("PICO_CYW43_ARCH_THREADSAFE_BACKGROUND");
//    const cyw43_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/cyw43-driver/src", .{pico_sdk_path});
//    lib.addIncludePath(.{ .path = cyw43_include });

    // required by cyw43
//   const lwip_include = try std.fmt.allocPrint(b.allocator, "{s}/lib/lwip/src/include", .{pico_sdk_path});
//    lib.addIncludePath(.{ .path = lwip_include });

    // options headers
    lib.addIncludePath(.{ .path = "config/" });

    lib.addIncludePath(.{ .path = "src/" });

//    const compiled = lib.getEmittedBin();   // compiled is the bin generated by the lib step
//    const install_step = b.addInstallFile(compiled, "mlem.o"); // here we copy it with this name
//    install_step.step.dependOn(&lib.step);

    // 3 lines above replaced by mstrens ; file will probably be in another dir and name (zig-out/lib)
    // so cmakelists.txt must be changed
    const install_step = b.addInstallArtifact(lib, .{});
    install_step.step.dependOn(&lib.step);

    // create build directory
    if (std.fs.cwd().makeDir("build")) |_| {} else |err| {
        if (err != error.PathAlreadyExists) return err;
    }

    const uart_or_usb = if (StdioUsb) "-DSTDIO_USB=1" else "-DSTDIO_UART=1";
    const cmake_pico_sdk_path = b.fmt("-DPICO_SDK_PATH={s}", .{pico_sdk_path});
    const cmake_argv = [_][]const u8{ "cmake", "-B", "./build", "-S .", "-DPICO_BOARD=" ++ Board, cmake_pico_sdk_path, uart_or_usb };
    const cmake_step = b.addSystemCommand(&cmake_argv);
    cmake_step.step.dependOn(&install_step.step);

//    const threads = try std.Thread.getCpuCount();
//    const make_thread_arg = try std.fmt.allocPrint(b.allocator, "-j{d}", .{threads});

//    const make_argv = [_][]const u8{ "make", "-C", "./build", make_thread_arg };

//    const make_step = b.addSystemCommand(&make_argv);
//    make_step.step.dependOn(&cmake_step.step);

    const make_step = b.addSystemCommand(&.{ "cmake", "--build", "./build" });
    make_step.setName("cmake : build project");
    make_step.step.dependOn(&cmake_step.step);

    b.getInstallStep().dependOn(&make_step.step);

    //const uf2_create_step = b.addInstallFile(.{ .path = "build/hello_world.uf2" }, "firmware.uf2");
    //uf2_create_step.step.dependOn(&make_step.step);

    //const uf2_step = b.step("uf2", "Create firmware.uf2");
    //uf2_step.dependOn(&uf2_create_step.step);
    //b.default_step = uf2_step;
}
