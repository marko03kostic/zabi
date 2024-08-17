const std = @import("std");
const testing = std.testing;
const utils = @import("../../utils/utils.zig");

const ENSClient = @import("ens.zig").ENSClient;

test "ENS Text" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var ens: ENSClient(.http) = undefined;
    defer ens.deinit();

    try ens.init(
        .{ .uri = uri, .allocator = testing.allocator },
        .{ .ensUniversalResolver = try utils.addressToBytes("0x8cab227b1162f03b8338331adaad7aadc83b895e") },
    );

    try testing.expectError(error.EvmFailedToExecute, ens.getEnsText("zzabi.eth", "com.twitter", .{}));
}

test "ENS Name" {
    {
        const uri = try std.Uri.parse("http://localhost:6969/");

        var ens: ENSClient(.http) = undefined;
        defer ens.deinit();

        try ens.init(
            .{ .uri = uri, .allocator = testing.allocator },
            .{ .ensUniversalResolver = try utils.addressToBytes("0x8cab227b1162f03b8338331adaad7aadc83b895e") },
        );

        const value = try ens.getEnsName("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", .{});
        defer value.deinit();

        try testing.expectEqualStrings(value.response, "vitalik.eth");
        try testing.expectError(error.EvmFailedToExecute, ens.getEnsName("0xD9DA6Bf26964af9d7Eed9e03e53415D37aa96045", .{}));
    }
    {
        const uri = try std.Uri.parse("http://localhost:6969/");

        var ens: ENSClient(.http) = undefined;
        defer ens.deinit();

        try ens.init(
            .{ .uri = uri, .allocator = testing.allocator },
            .{ .ensUniversalResolver = try utils.addressToBytes("0x9cab227b1162f03b8338331adaad7aadc83b895e") },
        );

        try testing.expectError(error.EvmFailedToExecute, ens.getEnsName("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045", .{}));
    }
}

test "ENS Address" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var ens: ENSClient(.http) = undefined;
    defer ens.deinit();

    try ens.init(
        .{ .uri = uri, .allocator = testing.allocator },
        .{ .ensUniversalResolver = try utils.addressToBytes("0x8cab227b1162f03b8338331adaad7aadc83b895e") },
    );

    const value = try ens.getEnsAddress("vitalik.eth", .{});
    defer value.deinit();

    try testing.expectEqualSlices(u8, &value.result, &try utils.addressToBytes("0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045"));
    try testing.expectError(error.EvmFailedToExecute, ens.getEnsAddress("zzabi.eth", .{}));
}

test "ENS Resolver" {
    const uri = try std.Uri.parse("http://localhost:6969/");

    var ens: ENSClient(.http) = undefined;
    defer ens.deinit();

    try ens.init(
        .{ .uri = uri, .allocator = testing.allocator },
        .{ .ensUniversalResolver = try utils.addressToBytes("0x8cab227b1162f03b8338331adaad7aadc83b895e") },
    );

    const value = try ens.getEnsResolver("vitalik.eth", .{});

    try testing.expectEqualSlices(u8, &try utils.addressToBytes("0x4976fb03C32e5B8cfe2b6cCB31c09Ba78EBaBa41"), &value);
}