const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const db = b.addModule("db", .{
        .root_source_file = b.path("src/db.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Database - SQLite
    {
        const zqlite = b.createModule(.{
            .root_source_file = b.path("vendor/zqlite/src/zqlite.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        zqlite.addIncludePath(b.path("vendor/sqlite"));

        const sqlite = b.addModule("db_sqlite", .{
            .root_source_file = b.path("src/db/sqlite.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        sqlite.addImport("db", db);
        sqlite.addImport("zqlite", zqlite);
        sqlite.addIncludePath(b.path("vendor/sqlite"));
        sqlite.addCSourceFile(.{
            .file = b.path("vendor/sqlite/sqlite3.c"),
            .flags = &[_][]const u8{
                "-std=c99",
                "-DSQLITE_DQS=0",
                "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1",
                "-DSQLITE_USE_ALLOCA=1",
                "-DSQLITE_THREADSAFE=1",
                "-DSQLITE_TEMP_STORE=3",
                "-DSQLITE_ENABLE_API_ARMOR=1",
                "-DSQLITE_ENABLE_UNLOCK_NOTIFY",
                "-DSQLITE_DEFAULT_FILE_PERMISSIONS=0600",
                "-DSQLITE_OMIT_DEPRECATED=1",
                "-DSQLITE_OMIT_LOAD_EXTENSION=1",
                "-DSQLITE_OMIT_PROGRESS_CALLBACK=1",
                "-DSQLITE_OMIT_SHARED_CACHE",
                "-DSQLITE_OMIT_TRACE=1",
                "-DSQLITE_OMIT_UTF16=1",
                "-DHAVE_USLEEP=0",
            },
        });
    }
}
