const std = @import("std");
const builtin = @import("builtin");

/// Zig dependency name in build.zig.zon for the host platform's @typescript/typescript-* binary.
pub fn depName() []const u8 {
    return switch (builtin.os.tag) {
        .macos => switch (builtin.cpu.arch) {
            .aarch64 => "typescript_darwin_arm64",
            .x86_64 => "typescript_darwin_x64",
            else => unsupported(),
        },
        .linux => switch (builtin.cpu.arch) {
            .aarch64 => "typescript_linux_arm64",
            .x86_64 => "typescript_linux_x64",
            .arm => "typescript_linux_arm",
            .loongarch64 => "typescript_linux_loong64",
            .mips64el => "typescript_linux_mips64el",
            .powerpc64 => "typescript_linux_ppc64",
            .riscv64 => "typescript_linux_riscv64",
            .s390x => "typescript_linux_s390x",
            else => unsupported(),
        },
        .windows => switch (builtin.cpu.arch) {
            .aarch64 => "typescript_win32_arm64",
            .x86_64 => "typescript_win32_x64",
            else => unsupported(),
        },
        .freebsd => switch (builtin.cpu.arch) {
            .aarch64 => "typescript_freebsd_arm64",
            .x86_64 => "typescript_freebsd_x64",
            else => unsupported(),
        },
        .netbsd => switch (builtin.cpu.arch) {
            .aarch64 => "typescript_netbsd_arm64",
            .x86_64 => "typescript_netbsd_x64",
            else => unsupported(),
        },
        .openbsd => switch (builtin.cpu.arch) {
            .aarch64 => "typescript_openbsd_arm64",
            .x86_64 => "typescript_openbsd_x64",
            else => unsupported(),
        },
        .illumos => switch (builtin.cpu.arch) {
            .x86_64 => "typescript_sunos_x64",
            else => unsupported(),
        },
        else => unsupported(),
    };
}

/// Filename of the tsc executable inside the npm package tarball.
pub fn exeName() []const u8 {
    return if (builtin.os.tag == .windows) "tsc.exe" else "tsc";
}

fn unsupported() noreturn {
    @compileError(std.fmt.comptimePrint(
        "typescript binary not available for host {s}-{s}",
        .{ @tagName(builtin.os.tag), @tagName(builtin.cpu.arch) },
    ));
}
