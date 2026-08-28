const std = @import("std");

const version = "1.37.0";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // upstream's own scripts, run the way upstream runs them: gen_build_files.sh
    // lifts applets.h and usage.h out of the //applet: and //usage: comments and
    // splices a Config.in together for every directory.
    const gen = b.addSystemCommand(&.{"sh"});
    gen.addFileArg(b.path("scripts/gen_build_files.sh"));
    gen.addDirectoryArg(b.path("."));
    const kconfig_tree = gen.addOutputDirectoryArg("generated");

    const include = b.addWriteFiles();
    for ([_][]const u8{ "applets.h", "usage.h" }) |name| {
        _ = include.addCopyFile(kconfig_tree.path(b, b.fmt("include/{s}", .{name})), b.fmt("include/{s}", .{name}));
    }

    // These two read ./.config and write the one header they are handed.
    const dot_config = b.addWriteFiles();
    _ = dot_config.addCopyFile(b.path("config/zibudi.config"), ".config");
    for ([_][2][]const u8{
        .{ "scripts/embedded_scripts", "embedded_scripts.h" },
        .{ "scripts/generate_BUFSIZ.sh", "common_bufsiz.h" },
    }) |script| {
        const run = b.addSystemCommand(&.{"sh"});
        run.addFileArg(b.path(script[0]));
        const header = run.addOutputFileArg(script[1]);
        run.setCwd(dot_config.getDirectory());
        _ = include.addCopyFile(header, b.fmt("include/{s}", .{script[1]}));
    }

    const autoconf = b.addRunArtifact(helper(b, "kconfig"));
    autoconf.addArtifactArg(kconfig(b));
    autoconf.addDirectoryArg(kconfig_tree);
    autoconf.addFileArg(b.path("Config.in"));
    autoconf.addFileArg(b.path("config/zibudi.config"));
    autoconf.addArg(version);
    const config = autoconf.addOutputDirectoryArg("kconfig").path(b, "include");

    const includes = include.getDirectory().path(b, "include");

    const tables = host(b, "applet_tables");
    addHeaders(b, tables, config, includes);
    tables.root_module.addCSourceFile(.{
        .file = b.path("applets/applet_tables.c"),
        .flags = &.{"--include=autoconf.h"},
    });

    const run_tables = b.addRunArtifact(tables);
    const tables_dir = b.addWriteFiles();
    _ = tables_dir.addCopyFile(run_tables.addOutputFileArg("applet_tables.h"), "applet_tables.h");
    _ = tables_dir.addCopyFile(run_tables.addOutputFileArg("NUM_APPLETS.h"), "NUM_APPLETS.h");

    const messages = host(b, "usage");
    addHeaders(b, messages, config, includes);
    messages.root_module.addCSourceFile(.{
        .file = b.path("applets/usage.c"),
        .flags = &.{"--include=autoconf.h"},
    });

    // usage_compressed wants the program in a directory it can name.
    const usage_dir = b.addWriteFiles();
    _ = usage_dir.addCopyFile(messages.getEmittedBin(), "usage");

    const pack = b.addSystemCommand(&.{"sh"});
    pack.addFileArg(b.path("applets/usage_compressed"));
    const usage_h = pack.addOutputFileArg("usage_compressed.h");
    pack.addDirectoryArg(usage_dir.getDirectory());
    _ = tables_dir.addCopyFile(usage_h, "usage_compressed.h");

    const busybox = b.addExecutable(.{
        .name = "busybox",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    b.installArtifact(busybox);

    addHeaders(b, busybox, config, includes);
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

fn addHeaders(b: *std.Build, compile: *std.Build.Step.Compile, config: std.Build.LazyPath, include: std.Build.LazyPath) void {
    compile.root_module.addIncludePath(config);
    compile.root_module.addIncludePath(include);
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
