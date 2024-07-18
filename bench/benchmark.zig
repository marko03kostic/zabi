const benchmark = @import("BenchmarkType.zig");
const constants = @import("constants.zig");
const std = @import("std");
const zabi_root = @import("zabi");
const generator = zabi_root.generator;

// Types
const Allocator = std.mem.Allocator;
const Event = zabi_root.abi.abitypes.Event;
const HttpRpcClient = zabi_root.clients.PubClient;
const TransactionEnvelope = zabi_root.types.transactions.TransactionEnvelope;

// Functions
const decodeAbiParameters = zabi_root.decoding.abi_decoder.decodeAbiParameters;
const decodeLogs = zabi_root.decoding.logs_decoder.decodeLogs;
const decodeRlp = zabi_root.decoding.rlp.decodeRlp;
const encodeAbiParameters = zabi_root.encoding.abi_encoding.encodeAbiParameters;
const encodeLogTopics = zabi_root.encoding.logs_encoding.encodeLogTopics;
const encodeRlp = zabi_root.encoding.rlp.encodeRlp;
const parseTransaction = zabi_root.decoding.parse_transacition.parseTransaction;
const parseHumanReadable = zabi_root.human_readable.parsing.parseHumanReadable;
const serializeTransaction = zabi_root.encoding.serialize.serializeTransaction;

const BORDER = "=" ** 80;
const PADDING = " " ** 35;

pub const std_options: std.Options = .{
    .log_level = .info,
};

const BenchmarkPrinter = struct {
    writer: std.fs.File.Writer,

    fn init(writer: std.fs.File.Writer) BenchmarkPrinter {
        return .{ .writer = writer };
    }

    fn fmt(self: BenchmarkPrinter, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.writer, format, args) catch unreachable;
    }

    fn print(self: BenchmarkPrinter, comptime format: []const u8, args: anytype) void {
        std.fmt.format(self.writer, format, args) catch @panic("Format failed!");
        self.fmt("\x1b[0m", .{});
    }
};

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const printer = BenchmarkPrinter.init(std.io.getStdErr().writer());

    var client: HttpRpcClient = undefined;
    defer client.deinit();

    const uri = try std.Uri.parse("https://ethereum-rpc.publicnode.com");
    try client.init(.{
        .allocator = allocator,
        .uri = uri,
    });

    printer.print("{s}Benchmark running in {s} mode\n", .{ " " ** 20, @tagName(@import("builtin").mode) });
    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "Human-Readable ABI", BORDER });

    {
        const result = try benchmark.benchmark(
            allocator,
            zabi_root.human_readable.parsing.parseHumanReadable,
            .{ zabi_root.abi.abitypes.Abi, allocator, constants.slice },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "Http Client", BORDER });
    {
        printer.print("Get ChainId...", .{});
        const result = try benchmark.benchmark(
            allocator,
            HttpRpcClient.getChainId,
            .{&client},
            .{ .runs = 5, .warmup_runs = 1 },
        );
        result.printSummary();
    }

    try encodingFunctions(allocator, printer);
    try decodingFunctions(allocator, printer);
}

pub fn decodingFunctions(allocator: Allocator, printer: BenchmarkPrinter) !void {
    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "DECODING", BORDER });
    printer.print("Parse serialized transaction... ", .{});

    {
        const random_data = try generator.generateRandomData(TransactionEnvelope, allocator, 1, .{ .slice_size = 2 });
        defer random_data.deinit();

        const encoded = try serializeTransaction(allocator, random_data.generated, null);
        defer allocator.free(encoded);

        const result = try benchmark.benchmark(
            allocator,
            parseTransaction,
            .{ allocator, encoded },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    printer.print("RLP Decoding...", .{});
    {
        const multi: struct { u8, bool, []const u8 } = .{ 127, false, "foobar" };
        const encoded = try encodeRlp(allocator, .{multi});
        defer allocator.free(encoded);

        const result = try benchmark.benchmark(allocator, zabi_root.decoding.rlp.decodeRlp, .{
            allocator,
            struct { u8, bool, []const u8 },
            encoded,
        }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }

    printer.print("Abi Decoding... ", .{});
    {
        const encoded = try encodeAbiParameters(allocator, constants.params, constants.items);
        defer encoded.deinit();

        const result = try benchmark.benchmark(
            allocator,
            decodeAbiParameters,
            .{ allocator, constants.params, encoded.data, .{} },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    printer.print("Abi Logs Decoding... ", .{});
    {
        const event = try parseHumanReadable(
            Event,
            allocator,
            "event Foo(uint indexed a, int indexed b, bool indexed c, bytes5 indexed d)",
        );
        defer event.deinit();

        const encoded = try encodeLogTopics(
            allocator,
            event.value,
            .{ 69, -420, true, "01234" },
        );
        defer allocator.free(encoded);

        const result = try benchmark.benchmark(
            allocator,
            decodeLogs,
            .{ allocator, struct { [32]u8, u256, i256, bool, [5]u8 }, event.value.inputs, encoded },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }
}
/// Runs the encoding function of zabi.
pub fn encodingFunctions(allocator: Allocator, printer: BenchmarkPrinter) !void {
    printer.print("\x1b[1;32m\n{s}\n{s}{s}\n{s}\n", .{ BORDER, PADDING, "ENCODING", BORDER });
    printer.print("Serialize Transaction... ", .{});
    {
        const random_data = try generator.generateRandomData(TransactionEnvelope, allocator, 69, .{ .slice_size = 2 });
        defer random_data.deinit();

        const result = try benchmark.benchmark(
            allocator,
            serializeTransaction,
            .{ allocator, random_data.generated, null },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    printer.print("RLP Encoding... ", .{});

    {
        const random_data = try generator.generateRandomData(struct { u256, []const u8, bool }, allocator, 0, .{});
        defer random_data.deinit();

        const result = try benchmark.benchmark(
            allocator,
            encodeRlp,
            .{ allocator, random_data.generated },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    printer.print("ABI Encoding... ", .{});
    {
        const result = try benchmark.benchmark(
            allocator,
            encodeAbiParameters,
            .{ allocator, constants.params, constants.items },
            .{ .warmup_runs = 5, .runs = 100 },
        );
        result.printSummary();
    }

    printer.print("ABI Logs Encoding... ", .{});
    {
        const event = try parseHumanReadable(
            Event,
            allocator,
            "event Foo(uint indexed a, int indexed b, bool indexed c, bytes5 indexed d)",
        );
        defer event.deinit();

        const result = try benchmark.benchmark(allocator, zabi_root.encoding.logs_encoding.encodeLogTopics, .{
            allocator,
            event.value,
            .{ 69, -420, true, "01234" },
        }, .{ .warmup_runs = 5, .runs = 100 });
        result.printSummary();
    }
}
