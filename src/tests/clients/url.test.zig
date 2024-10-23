const std = @import("std");
const testing = std.testing;
const url = @import("zabi-clients").url;

const searchUrlParamsAlloc = url.searchUrlParamsAlloc;

test "Query Parameters" {
    {
        const params = try searchUrlParamsAlloc(testing.allocator, .{ .foo = 69, .bar = "LOOOL" }, .{});
        defer testing.allocator.free(params);

        try testing.expectEqualStrings("?foo=69&bar=LOOOL", params);
    }
    {
        const foo: []const []const u8 = &.{ "LOOOL", "FOOOO" };
        const params = try searchUrlParamsAlloc(testing.allocator, .{ .foo = 69, .bar = foo }, .{});
        defer testing.allocator.free(params);

        try testing.expectEqualStrings("?foo=69&bar=LOOOL,FOOOO", params);
    }
    {
        const params = try searchUrlParamsAlloc(testing.allocator, .{ .foo = 69, .bar = null }, .{});
        defer testing.allocator.free(params);

        try testing.expectEqualStrings("?foo=69&bar=null", params);
    }
    {
        const params = try searchUrlParamsAlloc(testing.allocator, .{ .foo = 69, .bar = .baz }, .{});
        defer testing.allocator.free(params);

        try testing.expectEqualStrings("?foo=69&bar=baz", params);
    }
    {
        const params = try searchUrlParamsAlloc(testing.allocator, .{ .foo = 69, .bar = true }, .{});
        defer testing.allocator.free(params);

        try testing.expectEqualStrings("?foo=69&bar=true", params);
    }
    {
        const params = try searchUrlParamsAlloc(testing.allocator, .{ .foo = 69, .bar = 1.1 }, .{});
        defer testing.allocator.free(params);

        try testing.expectEqualStrings("?foo=69&bar=1.1e0", params);
    }
    {
        const params = try searchUrlParamsAlloc(testing.allocator, .{ .foo = 69, .bar = [_]u8{0} ** 20 }, .{});
        defer testing.allocator.free(params);

        try testing.expectEqualStrings("?foo=69&bar=0x0000000000000000000000000000000000000000", params);
    }
    {
        const params = try searchUrlParamsAlloc(testing.allocator, .{ .foo = 69, .bar = [_]u8{0} ** 1 }, .{});
        defer testing.allocator.free(params);

        try testing.expectEqualStrings("?foo=69&bar=00", params);
    }
}
