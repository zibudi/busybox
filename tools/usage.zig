//! Packs the usage tool's output into usage_compressed.h the way
//! applets/usage_compressed does, minus the bzip2 half that
//! CONFIG_FEATURE_COMPRESS_USAGE would need and we do not enable.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    if (argv.len != 3) return error.Usage;

    const cwd = std.Io.Dir.cwd();
    const messages = try cwd.readFileAlloc(io, argv[1], arena, .limited(1 << 24));

    var h: std.Io.Writer.Allocating = .init(arena);
    const w = &h.writer;

    try w.writeAll("#define UNPACKED_USAGE \"\" \\\n");
    var i: usize = 0;
    while (i < messages.len) : (i += 16) {
        try w.writeByte('"');
        for (messages[i..@min(i + 16, messages.len)]) |byte| try w.print("\\{o:0>3}", .{byte});
        try w.writeAll("\" \\\n");
    }
    try w.print("\n#define UNPACKED_USAGE_LENGTH {d}\n\n", .{messages.len});

    try cwd.writeFile(io, .{ .sub_path = argv[2], .data = h.written() });
}
