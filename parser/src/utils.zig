const std = @import("std");

extern fn print(ptr: [*]const u8, len: usize) void;

pub fn debug_print(comptime fmt: []const u8, args: anytype) void {
    var buffer: [1024]u8 = undefined;
    var slice = std.fmt.bufPrint(&buffer, fmt, args) catch unreachable;
    print(slice.ptr, slice.len);
}
