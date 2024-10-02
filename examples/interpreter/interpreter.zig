const args_parser = zabi.args;
const std = @import("std");
const zabi = @import("zabi");

const Contract = zabi.evm.contract.Contract;
const Interpreter = zabi.evm.Interpreter;
const PlainHost = zabi.evm.host.PlainHost;

pub const CliOptions = struct {
    bytecode: []const u8,
    calldata: []const u8,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var iter = try std.process.argsWithAllocator(gpa.allocator());
    defer iter.deinit();

    const parsed = args_parser.parseArgs(CliOptions, gpa.allocator(), &iter);

    const buffer = try gpa.allocator().alloc(u8, @divExact(parsed.bytecode.len, 2));
    defer gpa.allocator().free(buffer);

    const calldata = try gpa.allocator().alloc(u8, @divExact(parsed.calldata.len, 2));
    defer gpa.allocator().free(calldata);

    _ = try std.fmt.hexToBytes(buffer, parsed.bytecode);
    _ = try std.fmt.hexToBytes(calldata, parsed.calldata);

    const contract_instance = try Contract.init(
        gpa.allocator(),
        calldata,
        .{ .raw = buffer },
        null,
        0,
        [_]u8{1} ** 20,
        [_]u8{0} ** 20,
    );
    defer contract_instance.deinit(gpa.allocator());

    var plain: PlainHost = undefined;
    defer plain.deinit();

    plain.init(gpa.allocator());

    var interpreter: Interpreter = undefined;
    defer interpreter.deinit();

    try interpreter.init(gpa.allocator(), contract_instance, plain.host(), .{ .gas_limit = 300_000_000 });

    const result = try interpreter.run();
    defer result.deinit(gpa.allocator());

    std.debug.print("Interpreter result: {any}", .{result});
}
