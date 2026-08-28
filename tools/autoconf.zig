//! Turns a .config into autoconf.h, the way scripts/kconfig/confdata.c does,
//! minus the timestamp upstream also omits for reproducible builds, and into
//! common_bufsiz.h, which scripts/generate_BUFSIZ.sh writes.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    if (argv.len != 4) return error.Usage;

    const config, const version, const out = .{ argv[1], argv[2], argv[3] };

    const cwd = std.Io.Dir.cwd();
    const source = try cwd.readFileAlloc(io, config, arena, .limited(1 << 24));

    var h: std.Io.Writer.Allocating = .init(arena);
    const w = &h.writer;

    try w.print(
        \\/*
        \\ * Automatically generated C config: don't edit
        \\ * Busybox version: {s}
        \\ */
        \\#define AUTOCONF_TIMESTAMP ""
        \\
        \\
    , .{version});

    var header = true;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, line, "#")) {
            const title = lines.next() orelse break;
            while (lines.next()) |rest| if (std.mem.eql(u8, rest, "#")) break;
            if (header) {
                header = false;
            } else if (std.mem.startsWith(u8, title, "# ")) {
                try w.print("\n/*\n * {s}\n */\n", .{title[2..]});
            }
            continue;
        }
        if (std.mem.startsWith(u8, line, "# CONFIG_") and std.mem.endsWith(u8, line, " is not set")) {
            const name = line["# CONFIG_".len .. line.len - " is not set".len];
            try w.print(
                \\#undef CONFIG_{0s}
                \\#define ENABLE_{0s} 0
                \\#define IF_{0s}(...)
                \\#define IF_NOT_{0s}(...) __VA_ARGS__
                \\
            , .{name});
            continue;
        }
        if (!std.mem.startsWith(u8, line, "CONFIG_")) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const name = line["CONFIG_".len..eq];
        const value = line[eq + 1 ..];
        try w.print("#define CONFIG_{s} {s}\n", .{ name, if (std.mem.eql(u8, value, "y")) "1" else value });
        try w.print(
            \\#define ENABLE_{0s} 1
            \\#ifdef MAKE_SUID
            \\# define IF_{0s}(...) __VA_ARGS__ "CONFIG_{0s}"
            \\#else
            \\# define IF_{0s}(...) __VA_ARGS__
            \\#endif
            \\#define IF_NOT_{0s}(...)
            \\
        , .{name});
    }

    try cwd.writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(arena, "{s}/autoconf.h", .{out}),
        .data = h.written(),
    });

    // scripts/embedded_scripts bundles applets_sh/ only when asked to, and we
    // do not implement the bundling, so refuse the config that would need it.
    if (std.mem.indexOf(u8, source, "\nCONFIG_FEATURE_SH_EMBEDDED_SCRIPTS=y") != null) return error.EmbeddedScriptsUnsupported;
    try cwd.writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(arena, "{s}/embedded_scripts.h", .{out}),
        .data = "\n#define NUM_SCRIPTS 0\n",
    });

    // The other branches of generate_BUFSIZ.sh measure the linked binary's bss
    // tail, which we do not do, so refuse the config that would need it.
    if (std.mem.indexOf(u8, source, "\nCONFIG_FEATURE_USE_BSS_TAIL=y") != null) return error.BssTailUnsupported;
    try cwd.writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(arena, "{s}/common_bufsiz.h", .{out}),
        .data =
        \\enum { COMMON_BUFSIZE = 1024 };
        \\extern char bb_common_bufsiz1[];
        \\#define setup_common_bufsiz() ((void)0)
        \\
        ,
    });
}
