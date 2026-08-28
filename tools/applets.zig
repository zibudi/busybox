//! Writes include/applets.h and include/usage.h the way scripts/gen_build_files.sh
//! does: lift the //applet: and //usage: comments out of the sources, in the order
//! the shell would glob them, and splice them into the .src.h templates.

const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const argv = try init.minimal.args.toSlice(arena);
    if (argv.len != 3) return error.Usage;

    const source, const out = .{ argv[1], argv[2] };
    const cwd = std.Io.Dir.cwd();

    const sources = try glob(io, arena, source);

    var applets: std.Io.Writer.Allocating = .init(arena);
    var usage: std.Io.Writer.Allocating = .init(arena);

    for (sources) |path| {
        const text = try cwd.readFileAlloc(io, path, arena, .limited(1 << 24));
        var lines = std.mem.splitScalar(u8, text, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "//applet:")) {
                try applets.writer.print("{s}\n", .{line["//applet:".len..]});
            } else if (std.mem.startsWith(u8, line, "//usage:")) {
                const rest = line["//usage:".len..];
                if (rest.len == 0) continue;
                if (rest[0] != ' ' and rest[0] != '\t') try usage.writer.writeByte('\n');
                try usage.writer.print("{s} \\\n", .{rest});
            }
        }
    }

    try splice(io, arena, source, out, "applets", applets.written());
    try splice(io, arena, source, out, "usage", usage.written());
}

fn splice(
    io: std.Io,
    arena: std.mem.Allocator,
    source: []const u8,
    out: []const u8,
    name: []const u8,
    body: []const u8,
) !void {
    const cwd = std.Io.Dir.cwd();
    const template = try cwd.readFileAlloc(
        io,
        try std.fmt.allocPrint(arena, "{s}/include/{s}.src.h", .{ source, name }),
        arena,
        .limited(1 << 22),
    );

    var h: std.Io.Writer.Allocating = .init(arena);
    try h.writer.print("/* DO NOT EDIT. This file is generated from {s}.src.h */\n", .{name});

    var seen = false;
    var lines = std.mem.splitScalar(u8, template, '\n');
    while (lines.next()) |line| {
        if (!seen and std.mem.eql(u8, line, "INSERT")) {
            seen = true;
            try h.writer.writeAll(body);
            continue;
        }
        if (lines.peek() == null and line.len == 0) break;
        try h.writer.print("{s}\n", .{line});
    }
    if (!seen) return error.NoInsertLine;

    try cwd.writeFile(io, .{
        .sub_path = try std.fmt.allocPrint(arena, "{s}/{s}.h", .{ out, name }),
        .data = h.written(),
    });
}

fn glob(io: std.Io, arena: std.mem.Allocator, source: []const u8) ![]const []const u8 {
    const top = try names(io, arena, source, .directory);
    var found: std.ArrayList([]const u8) = .empty;

    for (top) |dir| {
        const path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ source, dir });
        for (try names(io, arena, path, .file)) |file|
            try found.append(arena, try std.fmt.allocPrint(arena, "{s}/{s}", .{ path, file }));
    }
    for (top) |dir| {
        const path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ source, dir });
        for (try names(io, arena, path, .directory)) |sub| {
            const nested = try std.fmt.allocPrint(arena, "{s}/{s}", .{ path, sub });
            for (try names(io, arena, nested, .file)) |file|
                try found.append(arena, try std.fmt.allocPrint(arena, "{s}/{s}", .{ nested, file }));
        }
    }
    return found.items;
}

fn names(io: std.Io, arena: std.mem.Allocator, path: []const u8, want: std.Io.File.Kind) ![]const []const u8 {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);

    var found: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.name[0] == '.') continue;
        if (entry.kind != want) continue;
        if (want == .file and !std.mem.endsWith(u8, entry.name, ".c")) continue;
        try found.append(arena, try arena.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, found.items, {}, lessThan);
    return found.items;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}
