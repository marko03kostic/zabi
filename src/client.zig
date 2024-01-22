const block = @import("meta/block.zig");
const http = std.http;
const log = @import("meta/log.zig");
const meta = @import("meta/meta.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");
const types = @import("meta/ethereum.zig");
const utils = @import("utils.zig");
const Anvil = @import("tests/anvil.zig").Anvil;
const Chains = types.PublicChains;
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Uri = std.Uri;

/// This allocator will get set by the arena.
alloc: Allocator,
/// The arena where all allocations will leave.
arena: *ArenaAllocator,
/// The client chainId.
chain_id: usize,
/// The underlaying http client used to manage all the calls.
client: *http.Client,
/// The set of predifined headers use for the rpc calls.
headers: *http.Headers,
/// The uri of the provided init string.
uri: Uri,
/// Tracked errors picked up by the requests
errors: std.ArrayListUnmanaged(types.ErrorResponse) = .{},

const PubClient = @This();

pub fn init(alloc: Allocator, url: []const u8, chain_id: ?Chains) !*PubClient {
    var pub_client = try alloc.create(PubClient);
    errdefer alloc.destroy(pub_client);

    pub_client.arena = try alloc.create(ArenaAllocator);
    errdefer alloc.destroy(pub_client.arena);

    pub_client.client = try alloc.create(http.Client);
    errdefer alloc.destroy(pub_client.client);

    pub_client.headers = try alloc.create(http.Headers);
    errdefer alloc.destroy(pub_client.arena);

    pub_client.arena.* = ArenaAllocator.init(alloc);
    pub_client.alloc = pub_client.arena.allocator();
    errdefer pub_client.arena.deinit();

    pub_client.headers.* = try http.Headers.initList(pub_client.alloc, &.{.{ .name = "Content-Type", .value = "application/json" }});
    pub_client.client.* = http.Client{ .allocator = pub_client.alloc };

    pub_client.uri = try Uri.parse(url);

    const chain: Chains = chain_id orelse .ethereum;
    const id = switch (chain) {
        inline else => |id| @intFromEnum(id),
    };

    pub_client.chain_id = id;
    pub_client.errors = .{};

    return pub_client;
}

pub fn deinit(self: *PubClient) void {
    const allocator = self.arena.child_allocator;
    self.arena.deinit();
    allocator.destroy(self.arena);
    allocator.destroy(self.headers);
    allocator.destroy(self.client);
    allocator.destroy(self);
}

pub fn estimateFeesPerGas(self: *PubClient, call_object: transaction.EthCall, know_block: ?block.Block) !transaction.EstimateFeeReturn {
    const current_block = know_block orelse try self.getBlockByNumber(.{});

    switch (current_block) {
        inline else => |block_info| {
            switch (call_object) {
                .eip1559 => |tx| {
                    const base_fee = block_info.baseFeePerGas orelse return error.UnableToFetchFeeInfoFromBlock;
                    const max_priority = if (tx.maxPriorityFeePerGas) |max| max else try self.estimateMaxFeePerGasManual(current_block);
                    const max_fee = if (tx.maxFeePerGas) |max| max else base_fee + max_priority;

                    return .{ .eip1559 = .{ .max_fee = max_fee, .max_priority = max_priority } };
                },
                .legacy => |tx| {
                    const gas_price = if (tx.gasPrice) |price| price else try self.getGasPrice() * std.math.pow(u64, 10, 9);
                    const price = @divExact(gas_price * std.math.ceil(1.2 * std.math.pow(u64, 10, 1)), std.math.pow(u64, 10, 1));

                    return .{ .legacy = .{ .gas_price = price } };
                },
            }
        },
    }
}

pub fn estimateGas(self: *PubClient, call_object: transaction.EthCall, opts: block.BlockNumberRequest) !types.Gwei {
    return self.fetchCall(types.Gwei, call_object, opts, .eth_estimateGas);
}

pub fn estimateMaxFeePerGasManual(self: *PubClient, know_block: ?block.Block) !types.Gwei {
    const current_block = know_block orelse try self.getBlockByNumber(.{});
    const gas_price = try self.getGasPrice();

    switch (current_block) {
        inline else => |block_info| {
            const base_fee = block_info.baseFeePerGas orelse return error.UnableToFetchFeeInfoFromBlock;

            const estimated = fee: {
                if (base_fee > gas_price) break :fee 0;

                break :fee gas_price - base_fee;
            };

            return estimated;
        },
    }
}

pub fn estimateMaxFeePerGas(self: *PubClient) !types.Gwei {
    return self.fetchWithEmptyArgs(types.Gwei, .eth_maxPriorityFeePerGas);
}

pub fn getAccounts(self: *PubClient) ![]const types.Hex {
    return self.fetchWithEmptyArgs([]const types.Hex, .eth_accounts);
}

pub fn getAddressBalance(self: *PubClient, opts: block.BalanceRequest) !types.Wei {
    return self.fetchByAddress(types.Wei, opts, .eth_getBalance);
}

pub fn getAddressTransactionCount(self: *PubClient, opts: block.BalanceRequest) !usize {
    return self.fetchByAddress(usize, opts, .eth_getTransactionCount);
}

pub fn getBlockByHash(self: *PubClient, opts: block.BlockHashRequest) !block.Block {
    if (!utils.isHash(opts.block_hash)) return error.InvalidHash;
    const include = opts.include_transaction_objects orelse false;

    const Params = std.meta.Tuple(&[_]type{ types.Hex, bool });
    const params: Params = .{ opts.block_hash, include };

    const request: types.EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByHash, .id = self.chain_id };

    return self.fetchBlock(request);
}

pub fn getBlockByNumber(self: *PubClient, opts: block.BlockRequest) !block.Block {
    const tag: block.BlockTag = opts.tag orelse .latest;
    const include = opts.include_transaction_objects orelse false;

    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ types.Hex, bool });
    const params: Params = .{ block_number, include };
    const request: types.EthereumRequest(Params) = .{ .params = params, .method = .eth_getBlockByNumber, .id = self.chain_id };

    return self.fetchBlock(request);
}

pub fn getBlockNumber(self: *PubClient) !u64 {
    return self.fetchWithEmptyArgs(u64, .eth_blockNumber);
}

pub fn getBlockTransactionCountByHash(self: *PubClient, block_hash: types.Hex) !usize {
    return self.fetchByBlockHash(block_hash, .eth_getBlockTransactionCountByHash);
}

pub fn getBlockTransactionCountByNumber(self: *PubClient, opts: block.BlockNumberRequest) !usize {
    return self.fetchByBlockNumber(opts, .eth_getBlockTransactionCountByNumber);
}

pub fn getChainId(self: *PubClient) !usize {
    return self.fetchWithEmptyArgs(usize, .eth_chainId);
}

pub fn getContractCode(self: *PubClient, opts: block.BalanceRequest) !types.Hex {
    return self.fetchByAddress(types.Hex, opts, .eth_getCode);
}

pub fn getFilterOrLogChanges(self: *PubClient, filter_id: usize, method: meta.Extract(types.EthereumRpcMethods, "eth_getFilterChanges,eth_FilterLogs")) !log.Logs {
    const filter = try std.fmt.allocPrint(self.alloc, "0x{x}", .{filter_id});

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{filter}, .method = method, .id = self.chain_id };

    return self.fetchLogs(types.HexRequestParameters, request);
}

pub fn getGasPrice(self: *PubClient) !types.Gwei {
    return self.fetchWithEmptyArgs(u64, .eth_gasPrice);
}

pub fn getLogs(self: *PubClient, opts: log.LogRequestParams) !log.Logs {
    const from_block = if (opts.tag) |tag| @tagName(tag) else if (opts.fromBlock) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else null;
    const to_block = if (opts.tag) |tag| @tagName(tag) else if (opts.toBlock) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else null;

    const request: types.EthereumRequest([]const log.LogRequest) = .{ .params = &.{.{ .fromBlock = from_block, .toBlock = to_block, .address = opts.address, .blockHash = opts.blockHash, .topics = opts.topics }}, .method = .eth_getLogs, .id = self.chain_id };

    return self.fetchLogs([]const log.LogRequest, request);
}

pub fn getTransactionByBlockHashAndIndex(self: *PubClient, block_hash: types.Hex, index: usize) !transaction.Transaction {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{ block_hash, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) }, .method = .eth_getTransactionByBlockHashAndIndex, .id = self.chain_id };

    return self.fetchTransaction(transaction.Transaction, request);
}

pub fn getTransactionByBlockNumberAndIndex(self: *PubClient, opts: block.BlockNumberRequest, index: usize) !transaction.Transaction {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{ block_number, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) }, .method = .eth_getTransactionByBlockHashAndIndex, .id = self.chain_id };

    return self.fetchTransaction(transaction.Transaction, request);
}

pub fn getTransactionByHash(self: *PubClient, transaction_hash: types.Hex) !transaction.Transaction {
    if (!utils.isHash(transaction_hash)) return error.InvalidHash;

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{transaction_hash}, .method = .eth_getTransactionByHash, .id = self.chain_id };

    return self.fetchTransaction(transaction.Transaction, request);
}

pub fn getTransactionReceipt(self: *PubClient, transaction_hash: types.Hex) !transaction.TransactionReceipt {
    if (!utils.isHash(transaction_hash)) return error.InvalidHash;

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{transaction_hash}, .method = .eth_getTransactionReceipt, .id = self.chain_id };

    return self.fetchTransaction(transaction.TransactionReceipt, request);
}

pub fn getUncleByBlockHashAndIndex(self: *PubClient, block_hash: types.Hex, index: usize) !block.Block {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const params: Params = .{ block_hash, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) };

    const request: types.EthereumRequest(Params) = .{ .params = params, .method = .eth_getUncleByBlockHashAndIndex, .id = self.chain_id };

    return self.fetchBlock(request);
}

pub fn getUncleByBlockNumberAndIndex(self: *PubClient, opts: block.BlockNumberRequest, index: usize) !block.Block {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ types.Hex, types.Hex });
    const params: Params = .{ block_number, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) };

    const request: types.EthereumRequest(Params) = .{ .params = params, .method = .eth_getTransactionByBlockHashAndIndex, .id = self.chain_id };

    return self.fetchBlock(request);
}

pub fn getUncleCountByBlockHash(self: *PubClient, block_hash: types.Hex) !usize {
    return self.fetchByBlockHash(block_hash, .eth_getUncleCountByBlockHash);
}

pub fn getUncleCountByBlockNumber(self: *PubClient, opts: block.BlockNumberRequest) !usize {
    return self.fetchByBlockNumber(opts, .eth_getUncleCountByBlockNumber);
}

pub fn newBlockFilter(self: *PubClient) !usize {
    return self.fetchWithEmptyArgs(usize, .eth_newBlockFilter);
}

pub fn newLogFilter(self: *PubClient, opts: log.LogFilterRequestParams) !usize {
    const from_block = if (opts.tag) |tag| @tagName(tag) else if (opts.fromBlock) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else null;
    const to_block = if (opts.tag) |tag| @tagName(tag) else if (opts.toBlock) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else null;

    const request: types.EthereumRequest([]const log.LogRequest) = .{ .params = &.{.{ .fromBlock = from_block, .toBlock = to_block, .address = opts.address, .blockHash = opts.blockHash, .topics = opts.topics }}, .method = .eth_newFilter, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{ .emit_null_optional_fields = false });
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(usize), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

pub fn newPendingTransactionFilter(self: *PubClient) !usize {
    return self.fetchWithEmptyArgs(usize, .eth_newPendingTransactionFilter);
}

pub fn sendEthCall(self: *PubClient, call_object: transaction.EthCall, opts: block.BlockNumberRequest) !types.Hex {
    return self.fetchCall(types.Hex, call_object, opts);
}

pub fn sendRawTransaction(self: *PubClient, serialized_hex_tx: types.Hex) !types.Hex {
    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{serialized_hex_tx}, .method = .eth_sendRawTransaction, .id = self.chain_id };

    return self.fetchTransaction(types.Hex, request);
}

pub fn uninstalllFilter(self: *PubClient, id: usize) !bool {
    const filter_id = try std.fmt.allocPrint(self.alloc, "0x{x}", .{id});

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{filter_id}, .method = .eth_uninstallFilter, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(bool), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

pub fn switchChainId(self: *PubClient, new_chain_id: usize, new_url: []const u8) void {
    self.chain_id = new_chain_id;

    const uri = try Uri.parse(new_url);
    self.uri = uri;
}

pub fn printLastRpcError(self: *PubClient) void {
    const writer = std.io.getStdErr().writer();
    const last = self.errors.getLast();

    try writer.print("Error code: {d}\n", .{last.code});
    try writer.print("Error message: {d}\n", .{last.message});
}

pub fn printAllRpcErrors(self: *PubClient) void {
    const writer = std.io.getStdErr().writer();
    const errors = self.errors.items;

    for (errors) |err| {
        try writer.print("Error code: {d}\n", .{err.code});
        try writer.print("Error message: {d}\n", .{err.message});
    }
}

fn fetchByBlockNumber(self: *PubClient, opts: block.BlockNumberRequest, method: types.EthereumRpcMethods) !usize {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{block_number}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(usize), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchByBlockHash(self: *PubClient, block_hash: []const u8, method: types.EthereumRpcMethods) !usize {
    if (!utils.isHash(block_hash)) return error.InvalidHash;

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{block_hash}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(usize), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchByAddress(self: *PubClient, comptime T: type, opts: block.BalanceRequest, method: types.EthereumRpcMethods) !T {
    if (!try utils.isAddress(self.alloc, opts.address)) return error.InvalidAddress;
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = .{ opts.address, block_number }, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(T), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchWithEmptyArgs(self: *PubClient, comptime T: type, method: types.EthereumRpcMethods) !T {
    const Params = std.meta.Tuple(&[_]type{});
    const request: types.EthereumRequest(Params) = .{ .params = .{}, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(T), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchBlock(self: *PubClient, request: anytype) !block.Block {
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(block.Block), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchTransaction(self: *PubClient, comptime T: type, request: types.EthereumRequest(types.HexRequestParameters)) !T {
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{});
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(T), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchLogs(self: *PubClient, comptime T: type, request: types.EthereumRequest(T)) !log.Logs {
    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{ .emit_null_optional_fields = false });
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(log.Logs), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

fn fetchCall(self: PubClient, comptime T: type, call_object: transaction.EthCall, opts: block.BlockNumberRequest, method: types.EthereumRpcMethods) !T {
    const tag: block.BalanceRequest = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);

    const Params = std.meta.Tuple(&[_]type{ transaction.EthCall, types.Hex });
    const request: types.EthereumRequest(Params) = .{ .params = &.{ call_object, block_number }, .method = method, .id = self.chain_id };

    const req_body = try std.json.stringifyAlloc(self.alloc, request, .{ .emit_null_optional_fields = false });
    const req = try self.client.fetch(self.alloc, .{ .headers = self.headers.*, .payload = .{ .string = req_body }, .location = .{ .uri = self.uri }, .method = .POST });

    if (req.status != .ok) return error.InvalidRequest;

    const parsed = std.json.parseFromSliceLeaky(types.EthereumResponse(T), self.alloc, req.body.?, .{}) catch {
        if (std.json.parseFromSliceLeaky(types.EthereumErrorResponse, self.alloc, req.body.?, .{})) |result| {
            try self.errors.append(self.alloc, result.@"error");
            return error.RpcErrorResponse;
        } else |_| return error.RpcNullResponse;
    };

    return parsed.result;
}

test "GetBlockNumber" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const block_req = try pub_client.getBlockNumber();

    try testing.expectEqual(19062632, block_req);
}

test "GetChainId" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const chain = try pub_client.getChainId();

    try testing.expectEqual(1, chain);
}

test "GetBlock" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockByNumber(.{});
    try testing.expect(block_info == .blockMerge);
    try testing.expectEqual(block_info.blockMerge.number.?, 19062632);
    try testing.expectEqualStrings(block_info.blockMerge.hash.?, "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
}

test "GetBlockByHash" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockByHash(.{ .block_hash = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8" });
    try testing.expect(block_info == .blockMerge);
    try testing.expectEqual(block_info.blockMerge.number.?, 19062632);
}

test "GetBlockTransactionCountByHash" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockTransactionCountByHash("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
    try testing.expect(block_info != 0);
}

test "getBlockTransactionCountByNumber" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockTransactionCountByNumber(.{});
    try testing.expect(block_info != 0);
}
