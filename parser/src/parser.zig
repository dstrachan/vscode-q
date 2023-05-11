const std = @import("std");
const Allocator = std.mem.Allocator;
const WasmAllocator = std.heap.WasmAllocator;

const TestType = struct {
    x: i32,
    y: i32,
    z: i32,
};

const allocator = Allocator{
    .ptr = undefined,
    .vtable = &WasmAllocator.vtable,
};

export fn alloc(len: usize) [*]const u8 {
    const slice = allocator.alloc(u8, len) catch @panic("Failed to allocate memory");
    return slice.ptr;
}

export fn destroy(ptr: *const TestType) void {
    allocator.destroy(ptr);
}

export fn parse(source: [*]const u8, len: usize) *const TestType {
    _ = len;
    _ = source;
    const ptr = allocator.create(TestType) catch @panic("Failed to allocate memory");
    ptr.* = .{
        .x = 100,
        .y = 200,
        .z = 300,
    };
    return ptr;
}
