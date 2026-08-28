const std = @import("std");

const version = "1.37.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const autoconf = b.addRunArtifact(helper(b, "kconfig"));
    autoconf.addArtifactArg(kconfig(b));
    autoconf.addDirectoryArg(b.path("generated"));
    autoconf.addFileArg(b.path("Config.in"));
    autoconf.addFileArg(b.path("config/zibudi.config"));
    autoconf.addArg(version);
    const config = autoconf.addOutputDirectoryArg("kconfig").path(b, "include");

    const tables = host(b, "applet_tables");
    addHeaders(b, tables, config);
    tables.root_module.addCSourceFile(.{
        .file = b.path("applets/applet_tables.c"),
        .flags = &.{"--include=autoconf.h"},
    });

    const run_tables = b.addRunArtifact(tables);
    const tables_dir = b.addWriteFiles();
    _ = tables_dir.addCopyFile(run_tables.addOutputFileArg("applet_tables.h"), "applet_tables.h");
    _ = tables_dir.addCopyFile(run_tables.addOutputFileArg("NUM_APPLETS.h"), "NUM_APPLETS.h");

    const messages = host(b, "usage");
    addHeaders(b, messages, config);
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

    addHeaders(b, busybox, config);
    busybox.root_module.addIncludePath(tables_dir.getDirectory());
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

// generated/ is the object tree upstream's own scripts write: gen_build_files.sh
// puts applets.h and usage.h in include/ and a Config.in in each directory,
// generate_BUFSIZ.sh and embedded_scripts write the other two headers. It is
// carried because running those scripts needs a shell, and the shell is what
// this builds.
fn addHeaders(b: *std.Build, compile: *std.Build.Step.Compile, config: std.Build.LazyPath) void {
    compile.root_module.addIncludePath(config);
    compile.root_module.addIncludePath(b.path("generated/include"));
    compile.root_module.addIncludePath(b.path("include"));
}

// zconf.tab.c includes the rest of kconfig, so the three files upstream ships
// pre-generated have to be reachable under the names it includes them by.
fn kconfig(b: *std.Build) *std.Build.Step.Compile {
    const shipped = b.addWriteFiles();
    const parser = shipped.addCopyFile(b.path("scripts/kconfig/zconf.tab.c_shipped"), "zconf.tab.c");
    _ = shipped.addCopyFile(b.path("scripts/kconfig/zconf.hash.c_shipped"), "zconf.hash.c");
    _ = shipped.addCopyFile(b.path("scripts/kconfig/lex.zconf.c_shipped"), "lex.zconf.c");

    const conf = host(b, "conf");
    conf.root_module.addIncludePath(shipped.getDirectory());
    conf.root_module.addIncludePath(b.path("scripts/kconfig"));
    for ([_]std.Build.LazyPath{ b.path("scripts/kconfig/conf.c"), parser }) |file| {
        conf.root_module.addCSourceFile(.{ .file = file, .flags = &.{"-DKBUILD_NO_NLS"} });
    }
    return conf;
}

fn host(b: *std.Build, name: []const u8) *std.Build.Step.Compile {
    return b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .ReleaseFast,
            .link_libc = true,
        }),
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
