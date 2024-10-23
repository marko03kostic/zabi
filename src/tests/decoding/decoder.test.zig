const decoder = @import("zabi-decoding").abi_decoder;
const std = @import("std");
const testing = std.testing;
const utils = @import("zabi-utils").utils;

const DecodeOptions = decoder.DecodeOptions;

const decodeAbiParameter = decoder.decodeAbiParameter;

test "Bool" {
    try testDecodeRuntime(bool, "0000000000000000000000000000000000000000000000000000000000000001", true, .{});
    try testDecodeRuntime(bool, "0000000000000000000000000000000000000000000000000000000000000000", false, .{});
}

test "Uint/Int" {
    try testDecodeRuntime(u8, "0000000000000000000000000000000000000000000000000000000000000005", 5, .{});
    try testDecodeRuntime(u256, "0000000000000000000000000000000000000000000000000000000000010f2c", 69420, .{});
    try testDecodeRuntime(i256, "fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffb", -5, .{});
    try testDecodeRuntime(i64, "fffffffffffffffffffffffffffffffffffffffffffffffffffffffff8a432eb", -123456789, .{});
}

test "Array bytes" {
    try testDecodeRuntime([20]u8, "0000000000000000000000004648451b5f87ff8f0f7d622bd40574bb97e25980", try utils.addressToBytes("0x4648451b5F87FF8F0F7D622bD40574bb97E25980"), .{});
    try testDecodeRuntime([5]u8, "0123456789000000000000000000000000000000000000000000000000000000", [_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 }, .{ .bytes_endian = .little });
    try testDecodeRuntime([10]u8, "0123456789012345678900000000000000000000000000000000000000000000", [_]u8{ 0x01, 0x23, 0x45, 0x67, 0x89 } ** 2, .{ .bytes_endian = .little });
}

test "Strings/Bytes" {
    try testDecodeRuntime([]const u8, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", "foo", .{});
    try testDecodeRuntime([]u8, "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003666f6f0000000000000000000000000000000000000000000000000000000000", @constCast(&[_]u8{ 0x66, 0x6f, 0x6f }), .{});
}

test "Errors" {
    var buffer: [4096]u8 = undefined;
    const bytes = try std.fmt.hexToBytes(&buffer, "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000020");
    try testing.expectError(error.BufferOverrun, decodeAbiParameter([]const []const []const []const []const []const []const []const []const []const u256, testing.allocator, bytes, .{}));
}

test "Arrays" {
    try testDecodeRuntime(
        []const i256,
        "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000",
        &[_]i256{ 4, 2, 0 },
        .{},
    );
    try testDecodeRuntime(
        [2]i256,
        "00000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000002",
        [2]i256{ 4, 2 },
        .{},
    );
    try testDecodeRuntime(
        [2][]const u8,
        "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000",
        [2][]const u8{ "foo", "bar" },
        .{},
    );
    try testDecodeRuntime(
        []const []const u8,
        "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000",
        &[_][]const u8{ "foo", "bar" },
        .{},
    );
    try testDecodeRuntime(
        [3][2][]const u8,
        "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000000000000000000000000000000000000000003666f6f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626172000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000362617a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003626f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000",
        [3][2][]const u8{ .{ "foo", "bar" }, .{ "baz", "boo" }, .{ "fizz", "buzz" } },
        .{},
    );
    try testDecodeRuntime(
        [2][]const []const u8,
        "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001e00000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000000000000000000000000000000000000000c0000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000003666f6f000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000036261720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000666697a7a7a7a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000362757a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000466697a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000662757a7a7a7a0000000000000000000000000000000000000000000000000000",
        [2][]const []const u8{ &.{ "foo", "bar", "fizzzz", "buz" }, &.{ "fizz", "buzz", "buzzzz" } },
        .{},
    );
}

test "Structs" {
    try testDecodeRuntime(
        struct { bar: bool },
        "0000000000000000000000000000000000000000000000000000000000000001",
        .{ .bar = true },
        .{},
    );
    try testDecodeRuntime(
        struct { bar: struct { baz: bool } },
        "0000000000000000000000000000000000000000000000000000000000000001",
        .{ .bar = .{ .baz = true } },
        .{},
    );
    try testDecodeRuntime(
        struct { bar: bool, baz: u256, fizz: []const u8 },
        "0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000",
        .{ .bar = true, .baz = 69, .fizz = "buzz" },
        .{},
    );
    try testDecodeRuntime(
        []const struct { bar: bool, baz: u256, fizz: []const u8 },
        "000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000450000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000462757a7a00000000000000000000000000000000000000000000000000000000",
        &.{.{ .bar = true, .baz = 69, .fizz = "buzz" }},
        .{},
    );
}

test "Tuples" {
    try testDecodeRuntime(
        struct { u256, bool, []const i120 },
        "0000000000000000000000000000000000000000000000000000000000000045000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000004500000000000000000000000000000000000000000000000000000000000001a40000000000000000000000000000000000000000000000000000000000010f2c",
        .{ 69, true, &[_]i120{ 69, 420, 69420 } },
        .{},
    );
    try testDecodeRuntime(
        struct { struct { foo: []const []const u8, bar: u256, baz: []const struct { fizz: []const []const u8, buzz: bool, jazz: []const i256 } } },
        "00000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000a45500000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000001c666f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f6f00000000000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000e0000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000018424f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f4f00000000000000000000000000000000000000000000000000000000000000000000000000000009000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000050000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000700000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000009",
        .{.{ .foo = &[_][]const u8{"fooooooooooooooooooooooooooo"}, .bar = 42069, .baz = &.{.{ .fizz = &.{"BOOOOOOOOOOOOOOOOOOOOOOO"}, .buzz = true, .jazz = &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9 } }} }},
        .{},
    );
}

// Testing functions.
fn testDecodeRuntime(comptime T: type, hex: []const u8, expected: T, options: DecodeOptions) !void {
    var buffer: [2048]u8 = undefined;

    const bytes = try std.fmt.hexToBytes(&buffer, hex);
    const decoded = try decodeAbiParameter(T, testing.allocator, bytes, options);
    defer decoded.deinit();

    try testInnerValues(expected, decoded.result);
}

fn testInnerValues(expected: anytype, actual: anytype) !void {
    if (@TypeOf(actual) == []const u8) {
        return try testing.expectEqualStrings(expected, actual);
    }

    const info = @typeInfo(@TypeOf(expected));
    if (info == .pointer) {
        if (@typeInfo(info.pointer.child) == .@"struct") return try testInnerValues(expected[0], actual[0]);

        for (expected, actual) |e, a| {
            try testInnerValues(e, a);
        }
        return;
    }
    if (info == .array) {
        for (expected, actual) |e, a| {
            try testInnerValues(e, a);
        }
        return;
    }

    if (info == .@"struct") {
        inline for (info.@"struct".fields) |field| {
            try testInnerValues(@field(expected, field.name), @field(actual, field.name));
        }
        return;
    }
    return try testing.expectEqual(@as(@TypeOf(actual), expected), actual);
}
