const std = @import("std");

const version = "1.37.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const autoconf = b.addRunArtifact(helper(b, "autoconf"));
    autoconf.addFileArg(b.path("config/zibudi.config"));
    autoconf.addArg(version);
    const generated = autoconf.addOutputDirectoryArg("include");

    const applets = b.addRunArtifact(helper(b, "applets"));
    applets.addDirectoryArg(b.path("."));
    const headers = applets.addOutputDirectoryArg("include");

    const tables = b.addExecutable(.{
        .name = "applet_tables",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
    });
    tables.root_module.addIncludePath(generated);
    tables.root_module.addIncludePath(headers);
    tables.root_module.addIncludePath(b.path("include"));
    tables.root_module.addCSourceFile(.{
        .file = b.path("applets/applet_tables.c"),
        .flags = &.{"--include=autoconf.h"},
    });

    const run_tables = b.addRunArtifact(tables);
    const applet_tables = run_tables.addOutputFileArg("applet_tables.h");
    const num_applets = run_tables.addOutputFileArg("NUM_APPLETS.h");

    const tables_dir = b.addWriteFiles();
    _ = tables_dir.addCopyFile(applet_tables, "applet_tables.h");
    _ = tables_dir.addCopyFile(num_applets, "NUM_APPLETS.h");

    const messages = b.addExecutable(.{
        .name = "usage",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
    });
    messages.root_module.addIncludePath(generated);
    messages.root_module.addIncludePath(headers);
    messages.root_module.addIncludePath(b.path("include"));
    messages.root_module.addCSourceFile(.{
        .file = b.path("applets/usage.c"),
        .flags = &.{"--include=autoconf.h"},
    });

    const pack = b.addRunArtifact(helper(b, "usage"));
    pack.addFileArg(b.addRunArtifact(messages).captureStdOut(.{}));
    _ = tables_dir.addCopyFile(pack.addOutputFileArg("usage_compressed.h"), "usage_compressed.h");

    const busybox = b.addExecutable(.{
        .name = "busybox",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(busybox);

    busybox.root_module.addIncludePath(generated);
    busybox.root_module.addIncludePath(tables_dir.getDirectory());
    busybox.root_module.addIncludePath(headers);
    busybox.root_module.addIncludePath(b.path("include"));
    busybox.root_module.addIncludePath(b.path("libbb"));
    busybox.root_module.addCSourceFiles(.{
        .root = b.path("."),
        .files = @import("tools/sources.zig").sources,
        .flags = &.{
            "-std=gnu99",
            "--include=autoconf.h",
            "-D_GNU_SOURCE",
            "-DNDEBUG",
            "-D_LARGEFILE_SOURCE",
            "-D_LARGEFILE64_SOURCE",
            "-D_FILE_OFFSET_BITS=64",
            "-D_TIME_BITS=64",
            "-DBB_VER=\"" ++ version ++ "\"",
            "-funsigned-char",
            "-fno-builtin-strlen",
            "-fno-builtin-printf",
            "-Wno-deprecated-declarations",
        },
    });
}

fn helper(b: *std.Build, name: []const u8) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(b.fmt("tools/{s}.zig", .{name})),
            .target = b.graph.host,
            .optimize = .ReleaseFast,
        }),
    });
}
