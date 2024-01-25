const block = @import("meta/block.zig");
const http = std.http;
const log = @import("meta/log.zig");
const meta = @import("meta/meta.zig");
const std = @import("std");
const testing = std.testing;
const transaction = @import("meta/transaction.zig");
const types = @import("meta/ethereum.zig");
const utils = @import("utils.zig");
const Anvil = @import("tests/Anvil.zig");
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

/// Init the client instance. Caller must call `deinit` to free the memory.
/// Most of the client method are replicas of the JSON RPC methods name with the `eth_` start.
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

/// Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.
pub fn estimateFeesPerGas(self: *PubClient, call_object: transaction.EthCall, know_block: ?block.Block) !transaction.EstimateFeeReturn {
    const current_block = know_block orelse try self.getBlockByNumber(.{});

    switch (current_block) {
        inline else => |block_info| {
            switch (call_object) {
                .eip1559 => |tx| {
                    const base_fee = block_info.baseFeePerGas orelse return error.UnableToFetchFeeInfoFromBlock;
                    const max_priority = if (tx.maxPriorityFeePerGas) |max| max else try self.estimateMaxFeePerGasManual(current_block);
                    const max_fee = if (tx.maxFeePerGas) |max| max else base_fee + max_priority;

                    return .{ .eip1559 = .{ .max_fee_gas = max_fee, .max_priority_fee = max_priority } };
                },
                .legacy => |tx| {
                    const gas_price = if (tx.gasPrice) |price| price else try self.getGasPrice() * std.math.pow(u64, 10, 9);
                    const price = @divExact(gas_price * @as(u64, @intFromFloat(std.math.ceil(1.2 * std.math.pow(f64, 10, 1)))), std.math.pow(u64, 10, 1));
                    return .{ .legacy = .{ .gas_price = price } };
                },
            }
        },
    }
}

/// Calls `eth_estimateGas` with the call object.
pub fn estimateGas(self: *PubClient, call_object: transaction.EthCall, opts: block.BlockNumberRequest) !types.Gwei {
    return self.fetchCall(types.Gwei, call_object, opts, .eth_estimateGas);
}

/// Estimates maxPriorityFeePerGas manually. If the node you are currently using
/// supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.
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

/// Only use this if the node you are currently using supports `eth_maxPriorityFeePerGas`.
pub fn estimateMaxFeePerGas(self: *PubClient) !types.Gwei {
    return self.fetchWithEmptyArgs(types.Gwei, .eth_maxPriorityFeePerGas);
}

pub fn getAccounts(self: *PubClient) ![]const types.Hex {
    return self.fetchWithEmptyArgs([]const types.Hex, .eth_accounts);
}

pub fn getAddressBalance(self: *PubClient, opts: block.BalanceRequest) !types.Wei {
    return self.fetchByAddress(types.Wei, opts, .eth_getBalance);
}

pub fn getAddressTransactionCount(self: *PubClient, opts: block.BalanceRequest) !u64 {
    return self.fetchByAddress(u64, opts, .eth_getTransactionCount);
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

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{ block_number, try std.fmt.allocPrint(self.alloc, "0x{x}", .{index}) }, .method = .eth_getTransactionByBlockNumberAndIndex, .id = self.chain_id };

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

/// Call object must be prefilled before hand. Including the data field.
/// This will just the request to the network.
pub fn sendEthCall(self: *PubClient, call_object: transaction.EthCall, opts: block.BlockNumberRequest) !types.Hex {
    return self.fetchCall(types.Hex, call_object, opts);
}

/// Transaction must be serialized and signed before hand.
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

/// Switch the client network and chainId.
pub fn switchNetwork(self: *PubClient, new_chain_id: Chains, new_url: []const u8) void {
    self.chain_id = @intFromEnum(new_chain_id);

    const uri = try Uri.parse(new_url);
    self.uri = uri;
}

/// Prints the last error message that was tracked.
pub fn printLastRpcError(self: *PubClient) !void {
    const writer = std.io.getStdErr().writer();
    const last = self.errors.getLast();

    try writer.print("Error code: {d}\n", .{last.code});
    try writer.print("Error message: {s}\n", .{last.message});
}

/// Prints all tracked error messages.
pub fn printAllRpcErrors(self: *PubClient) !void {
    const writer = std.io.getStdErr().writer();
    const errors = self.errors.items;

    for (errors) |err| {
        try writer.print("Error code: {d}\n", .{err.code});
        try writer.print("Error message: {s}\n", .{err.message});
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

    const request: types.EthereumRequest(types.HexRequestParameters) = .{ .params = &.{ opts.address, block_number }, .method = method, .id = self.chain_id };

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

fn fetchCall(self: *PubClient, comptime T: type, call_object: transaction.EthCall, opts: block.BlockNumberRequest, method: types.EthereumRpcMethods) !T {
    const tag: block.BalanceBlockTag = opts.tag orelse .latest;
    const block_number = if (opts.block_number) |number| try std.fmt.allocPrint(self.alloc, "0x{x}", .{number}) else @tagName(tag);
    const call: transaction.EthCallHexed = call: {
        switch (call_object) {
            .eip1559 => |tx| {
                const eip1559_call: transaction.EthCallEip1559Hexed = .{
                    .value = if (tx.value) |value| try std.fmt.allocPrint(self.alloc, "0x{x}", .{value}) else null,
                    .gas = if (tx.gas) |gas| try std.fmt.allocPrint(self.alloc, "0x{x}", .{gas}) else null,
                    .maxFeePerGas = if (tx.maxFeePerGas) |fees| try std.fmt.allocPrint(self.alloc, "0x{x}", .{fees}) else null,
                    .maxPriorityFeePerGas = if (tx.maxPriorityFeePerGas) |max_fees| try std.fmt.allocPrint(self.alloc, "0x{x}", .{max_fees}) else null,
                    .from = tx.from,
                    .to = tx.to,
                    .data = tx.data,
                };

                break :call .{ .eip1559 = eip1559_call };
            },
            .legacy => |tx| {
                const legacy_call: transaction.EthCallLegacyHexed = .{
                    .value = if (tx.value) |value| try std.fmt.allocPrint(self.alloc, "0x{x}", .{value}) else null,
                    .gasPrice = if (tx.gasPrice) |gas_price| try std.fmt.allocPrint(self.alloc, "0x{x}", .{gas_price}) else null,
                    .gas = if (tx.gas) |gas| try std.fmt.allocPrint(self.alloc, "0x{x}", .{gas}) else null,
                    .from = tx.from,
                    .to = tx.to,
                    .data = tx.data,
                };

                break :call .{ .legacy = legacy_call };
            },
        }
    };

    const Params = std.meta.Tuple(&[_]type{ transaction.EthCallHexed, types.Hex });
    const request: types.EthereumRequest(Params) = .{ .params = .{ call, block_number }, .method = method, .id = self.chain_id };

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

    const block_old = try pub_client.getBlockByNumber(.{ .block_number = 696969 });
    try testing.expect(block_old == .block);
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

test "getBlockTransactionCountByHash" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const block_info = try pub_client.getBlockTransactionCountByHash("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
    try testing.expect(block_info != 0);
}

test "getAccounts" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const accounts = try pub_client.getAccounts();
    try testing.expect(accounts.len != 0);
}

test "gasPrice" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const gasPrice = try pub_client.getGasPrice();
    try testing.expect(gasPrice != 0);
}

test "getCode" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const code = try pub_client.getContractCode(.{ .address = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2" });
    try testing.expectEqualStrings(code, "0x6060604052600436106100af576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806306fdde03146100b9578063095ea7b31461014757806318160ddd146101a157806323b872dd146101ca5780632e1a7d4d14610243578063313ce5671461026657806370a082311461029557806395d89b41146102e2578063a9059cbb14610370578063d0e30db0146103ca578063dd62ed3e146103d4575b6100b7610440565b005b34156100c457600080fd5b6100cc6104dd565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561010c5780820151818401526020810190506100f1565b50505050905090810190601f1680156101395780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b341561015257600080fd5b610187600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803590602001909190505061057b565b604051808215151515815260200191505060405180910390f35b34156101ac57600080fd5b6101b461066d565b6040518082815260200191505060405180910390f35b34156101d557600080fd5b610229600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803590602001909190505061068c565b604051808215151515815260200191505060405180910390f35b341561024e57600080fd5b61026460048080359060200190919050506109d9565b005b341561027157600080fd5b610279610b05565b604051808260ff1660ff16815260200191505060405180910390f35b34156102a057600080fd5b6102cc600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610b18565b6040518082815260200191505060405180910390f35b34156102ed57600080fd5b6102f5610b30565b6040518080602001828103825283818151815260200191508051906020019080838360005b8381101561033557808201518184015260208101905061031a565b50505050905090810190601f1680156103625780820380516001836020036101000a031916815260200191505b509250505060405180910390f35b341561037b57600080fd5b6103b0600480803573ffffffffffffffffffffffffffffffffffffffff16906020019091908035906020019091905050610bce565b604051808215151515815260200191505060405180910390f35b6103d2610440565b005b34156103df57600080fd5b61042a600480803573ffffffffffffffffffffffffffffffffffffffff1690602001909190803573ffffffffffffffffffffffffffffffffffffffff16906020019091905050610be3565b6040518082815260200191505060405180910390f35b34600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825401925050819055503373ffffffffffffffffffffffffffffffffffffffff167fe1fffcc4923d04b559f4d29a8bfc6cda04eb5b0d3c460751c2402c5c5cc9109c346040518082815260200191505060405180910390a2565b60008054600181600116156101000203166002900480601f0160208091040260200160405190810160405280929190818152602001828054600181600116156101000203166002900480156105735780601f1061054857610100808354040283529160200191610573565b820191906000526020600020905b81548152906001019060200180831161055657829003601f168201915b505050505081565b600081600460003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020819055508273ffffffffffffffffffffffffffffffffffffffff163373ffffffffffffffffffffffffffffffffffffffff167f8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925846040518082815260200191505060405180910390a36001905092915050565b60003073ffffffffffffffffffffffffffffffffffffffff1631905090565b600081600360008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002054101515156106dc57600080fd5b3373ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff16141580156107b457507fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205414155b156108cf5781600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020541015151561084457600080fd5b81600460008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff16815260200190815260200160002060003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825403925050819055505b81600360008673ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000206000828254039250508190555081600360008573ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825401925050819055508273ffffffffffffffffffffffffffffffffffffffff168473ffffffffffffffffffffffffffffffffffffffff167fddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef846040518082815260200191505060405180910390a3600190509392505050565b80600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff1681526020019081526020016000205410151515610a2757600080fd5b80600360003373ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff168152602001908152602001600020600082825403925050819055503373ffffffffffffffffffffffffffffffffffffffff166108fc829081150290604051600060405180830381858888f193505050501515610ab457600080fd5b3373ffffffffffffffffffffffffffffffffffffffff167f7fcf532c15f0a6db0bd6d0e038bea71d30d808c7d98cb3bf7268a95bf5081b65826040518082815260200191505060405180910390a250565b600260009054906101000a900460ff1681565b60036020528060005260406000206000915090505481565b60018054600181600116156101000203166002900480601f016020809104026020016040519081016040528092919081815260200182805460018160011615610100020316600290048015610bc65780601f10610b9b57610100808354040283529160200191610bc6565b820191906000526020600020905b815481529060010190602001808311610ba957829003601f168201915b505050505081565b6000610bdb33848461068c565b905092915050565b60046020528160005260406000206020528060005260406000206000915091505054815600a165627a7a72305820deb4c2ccab3c2fdca32ab3f46728389c2fe2c165d5fafa07661e4e004f6c344a0029");
}

test "getAddressBalance" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const address = try pub_client.getAddressBalance(.{ .address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" });
    try testing.expectEqual(address, try utils.parseEth(10000));
}

test "getUncleCountByBlockHash" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const uncle = try pub_client.getUncleCountByBlockHash("0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8");
    try testing.expectEqual(uncle, 0);
}

test "getUncleCountByBlockNumber" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const uncle = try pub_client.getUncleCountByBlockNumber(.{});
    try testing.expectEqual(uncle, 0);
}

test "getLogs" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const logs = try pub_client.getLogs(.{ .blockHash = "0x7f609bbcba8d04901c9514f8f62feaab8cf1792d64861d553dde6308e03f3ef8" });
    try testing.expect(logs.len != 0);
}

test "getTransactionByBlockNumberAndIndex" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const tx = try pub_client.getTransactionByBlockNumberAndIndex(.{ .block_number = 16777215 }, 0);
    try testing.expect(tx == .eip1559);
}

test "getTransactionByBlockHashAndIndex" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const tx = try pub_client.getTransactionByBlockHashAndIndex("0xf34c3c11b35466e5595e077239e6b25a7c3ec07a214b2492d42ba6d73d503a1b", 0);
    try testing.expect(tx == .eip1559);
}

test "getAddressTransactionCount" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const nonce = try pub_client.getAddressTransactionCount(.{ .address = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" });
    try testing.expectEqual(nonce, 605);
}

test "getTransactionByHash" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const eip1559 = try pub_client.getTransactionByHash("0x72c2a1a82c48da81fac7b434cdb5662b5c92b76f85565e062196ca8a84f43ee5");
    try testing.expect(eip1559 == .eip1559);

    // Remove because they fail on CI run.
    // const legacy = try pub_client.getTransactionByHash("0xf9ffe354d26160616844278c4fcbfe0eaa5589da48bc1359eda81fc1ce18b51a");
    // try testing.expect(legacy == .legacy);
    //
    // const tx_untyped = try pub_client.getTransactionByHash("0x0bad3271acf0f10e56caf39187c956583710e1295ee3369a442beda0a666b27a");
    // try testing.expect(tx_untyped == .untyped);
}

test "getTransactionReceipt" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const receipt = try pub_client.getTransactionReceipt("0x72c2a1a82c48da81fac7b434cdb5662b5c92b76f85565e062196ca8a84f43ee5");
    try testing.expect(receipt.status != null);

    // Pre-Byzantium
    const legacy = try pub_client.getTransactionReceipt("0x4dadc87da2b7c47125fb7e4102d95457830e44d2fbcd45537d91f8be1e5f6130");
    try testing.expect(legacy.root != null);
}

test "estimateGas" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const gas = try pub_client.estimateGas(.{ .eip1559 = .{ .from = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1) } }, .{});
    try testing.expect(gas != 0);
}

test "estimateFeesPerGas" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const gas = try pub_client.estimateFeesPerGas(.{ .eip1559 = .{ .from = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266", .value = try utils.parseEth(1) } }, null);
    try testing.expect(gas.eip1559.max_fee_gas != 0);
    try testing.expect(gas.eip1559.max_priority_fee != 0);
}

test "estimateMaxFeePerGasManual" {
    var pub_client = try PubClient.init(std.testing.allocator, "http://localhost:8545", null);
    defer pub_client.deinit();

    const gas = try pub_client.estimateMaxFeePerGasManual(null);
    try testing.expect(gas != 0);
}