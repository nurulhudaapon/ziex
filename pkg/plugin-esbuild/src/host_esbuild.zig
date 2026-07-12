const std = @import("std");
const builtin = @import("builtin");

/// Zig dependency name in build.zig.zon for the host platform's @esbuild/* binary.
pub fn depName() []const u8 {
    return switch (builtin.os.tag) {
        .macos => switch (builtin.cpu.arch) {
            .aarch64 => "esbuild_darwin_arm64",
            .x86_64 => "esbuild_darwin_x64",
            else => unsupported(),
        },
        .linux => switch (builtin.cpu.arch) {
            .aarch64 => "esbuild_linux_arm64",
            .x86_64 => "esbuild_linux_x64",
            .x86 => "esbuild_linux_ia32",
            .arm => "esbuild_linux_arm",
            .loongarch64 => "esbuild_linux_loong64",
            .mips64el => "esbuild_linux_mips64el",
            .powerpc64 => "esbuild_linux_ppc64",
            .riscv64 => "esbuild_linux_riscv64",
            .s390x => "esbuild_linux_s390x",
            else => unsupported(),
        },
        .windows => switch (builtin.cpu.arch) {
            .aarch64 => "esbuild_win32_arm64",
            .x86_64 => "esbuild_win32_x64",
            .x86 => "esbuild_win32_ia32",
            else => unsupported(),
        },
        .freebsd => switch (builtin.cpu.arch) {
            .aarch64 => "esbuild_freebsd_arm64",
            .x86_64 => "esbuild_freebsd_x64",
            else => unsupported(),
        },
        .netbsd => switch (builtin.cpu.arch) {
            .aarch64 => "esbuild_netbsd_arm64",
            .x86_64 => "esbuild_netbsd_x64",
            else => unsupported(),
        },
        .openbsd => switch (builtin.cpu.arch) {
            .aarch64 => "esbuild_openbsd_arm64",
            .x86_64 => "esbuild_openbsd_x64",
            else => unsupported(),
        },
        .illumos => switch (builtin.cpu.arch) {
            .x86_64 => "esbuild_sunos_x64",
            else => unsupported(),
        },
        else => unsupported(),
    };
}

/// Filename of the esbuild executable inside the npm package tarball.
pub fn exeName() []const u8 {
    return if (builtin.os.tag == .windows) "esbuild.exe" else "bin/esbuild";
}

fn unsupported() noreturn {
    @compileError(std.fmt.comptimePrint(
        "esbuild binary not available for host {s}-{s}",
        .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) },
    ));
}
