//! Runs upstream's scripts/kconfig/conf, which writes include/autoconf.h into
//! the directory it is run from.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    if (argv.len != 7) return error.Usage;

    const cwd = std.Io.Dir.cwd();
    const conf = try cwd.realPathFileAlloc(io, argv[1], arena);
    const srctree = try cwd.realPathFileAlloc(io, argv[2], arena);
    const top = try cwd.realPathFileAlloc(io, argv[3], arena);
    const config = try cwd.realPathFileAlloc(io, argv[4], arena);
    const version, const out = .{ argv[5], argv[6] };

    try cwd.createDirPath(io, try std.fmt.allocPrint(arena, "{s}/include", .{out}));

    const env = init.environ_map;
    // conf reaches for the per-directory Config.in files under this name, and
    // those are the ones upstream's gen_build_files.sh wrote.
    try env.put("srctree", srctree);
    try env.put("KERNELVERSION", version);
    // Otherwise it stamps the hour into autoconf.h and no two builds agree.
    try env.put("KCONFIG_NOTIMESTAMP", "1");

    var child = try std.process.spawn(io, .{
        .argv = &.{ conf, "-D", config, top },
        .cwd = .{ .path = out },
        .environ_map = env,
    });
    switch (try child.wait(io)) {
        .exited => |code| if (code != 0) return error.KconfigFailed,
        else => return error.KconfigFailed,
    }
}
