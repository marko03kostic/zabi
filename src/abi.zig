const std = @import("std");
const testing = std.testing;
const AbiParameter = @import("abi_parameter.zig").AbiParameter;
const AbiEventParameter = @import("abi_parameter.zig").AbiEventParameter;
const Extract = @import("types.zig").Extract;
const StateMutability = @import("state_mutability.zig").StateMutability;
const UnionParser = @import("types.zig").UnionParser;

pub const Abitype = enum { function, @"error", event, constructor, fallback, receive };

/// Solidity Abi function representation.
/// Reference: ["function"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Function = struct {
    type: Extract(Abitype, "function"),
    /// Deprecated. Use either 'pure' or 'view'.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    constant: ?bool = null,
    /// Deprecated. Older vyper compiler versions used to provide gas estimates.
    ///
    /// https://github.com/vyperlang/vyper/issues/2151
    gas: ?i64 = null,
    inputs: []const AbiParameter,
    name: []const u8,
    outputs: []const AbiParameter,
    /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    payable: ?bool = null,
    stateMutability: StateMutability,
};

/// Solidity Abi function representation.
/// Reference: ["event"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Event = struct {
    type: Extract(Abitype, "event"),
    name: []const u8,
    inputs: []const AbiEventParameter,
    anonymous: ?bool = null,
};

/// Solidity Abi function representation.
/// Reference: ["error"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Error = struct {
    type: Extract(Abitype, "error"),
    name: []const u8,
    inputs: []const AbiParameter,
};

/// Solidity Abi function representation.
/// Reference: ["constructor"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Constructor = struct {
    type: Extract(Abitype, "constructor"),
    inputs: []const AbiParameter,
    /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    payable: ?bool = null,
    stateMutability: Extract(StateMutability, "payable,nonpayable"),
};

/// Solidity Abi function representation.
/// Reference: ["fallback"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Fallback = struct {
    type: Extract(Abitype, "fallback"),
    /// Deprecated. Use 'nonpayable' or 'payable'. Consider using `StateMutability`.
    ///
    /// https://github.com/ethereum/solidity/issues/992
    payable: ?bool = null,
    stateMutability: Extract(StateMutability, "payable,nonpayable"),
};

/// Solidity Abi function representation.
/// Reference: ["receive"](https://docs.soliditylang.org/en/latest/abi-spec.html#json)
pub const Receive = struct { type: Extract(Abitype, "receive"), stateMutability: Extract(StateMutability, "payable") };

/// Union representing all of the possible Abi members.
pub const AbiItem = union(enum) {
    abiFunction: Function,
    abiEvent: Event,
    abiError: Error,
    abiConstructor: Constructor,
    abiFallback: Fallback,
    abiReceive: Receive,

    pub usingnamespace UnionParser(@This());
};

pub const Abi = []const AbiItem;
test "Json parse simple" {
    const slice =
        \\ [{
        \\  "type": "receive",
        \\  "stateMutability": "payable"
        \\ }]
    ;

    const parsed = try std.json.parseFromSlice(Abi, testing.allocator, slice, .{});
    defer parsed.deinit();
}