const std = @import("std");
const Allocator = std.mem.Allocator;
const WasmAllocator = std.heap.WasmAllocator;
const Utf8Iterator = std.unicode.Utf8Iterator;
const Utf8View = std.unicode.Utf8View;

const Scanner = @import("./scanner.zig");

const allocator = Allocator{
    .ptr = undefined,
    .vtable = &WasmAllocator.vtable,
};

const TokenResult = struct {
    tokens: [*]Scanner.Token,
    len: u32,
};

export fn alloc(len: usize) [*]const u8 {
    const slice = allocator.alloc(u8, len) catch @panic("Failed to allocate memory");
    return slice.ptr;
}

export fn destroy(ptr: *const Scanner.Token) void {
    allocator.destroy(ptr);
}

export fn parse(source: [*]const u8, len: usize) *const TokenResult {
    var scanner = Scanner.init(source[0..len]);
    var list = std.ArrayList(Scanner.Token).init(allocator);
    defer list.deinit();
    while (scanner.scanToken()) |token| {
        list.append(token) catch @panic("Failed to append token");
    }
    const ptr = allocator.create(TokenResult) catch @panic("Failed to allocate memory");
    const slice = list.toOwnedSlice() catch @panic("Failed to allocate memory");
    ptr.* = .{
        .tokens = slice.ptr,
        .len = slice.len,
    };
    return ptr;
}
