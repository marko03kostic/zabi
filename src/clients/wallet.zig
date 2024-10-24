const ckzg4844 = @import("c-kzg-4844");
const constants = zabi_utils.constants;
const eip712 = @import("zabi-abi").eip712;
const encoder = zabi_encoding.abi_encoding;
const serialize = zabi_encoding.serialize;
const std = @import("std");
const testing = std.testing;
const transaction = zabi_types.transactions;
const types = zabi_types.ethereum;
const utils = zabi_utils.utils;
const zabi_encoding = @import("zabi-encoding");
const zabi_crypto = @import("zabi-crypto");
const zabi_types = @import("zabi-types");
const zabi_utils = @import("zabi-utils");

// Types
const AccessList = transaction.AccessList;
const Address = types.Address;
const Allocator = std.mem.Allocator;
const Blob = ckzg4844.KZG4844.Blob;
const Chains = types.PublicChains;
const EIP712Errors = eip712.EIP712Errors;
const KZG4844 = ckzg4844.KZG4844;
const LondonEthCall = transaction.LondonEthCall;
const LegacyEthCall = transaction.LegacyEthCall;
const Hash = types.Hash;
const InitOptsHttp = PubClient.InitOptions;
const InitOptsIpc = IpcClient.InitOptions;
const InitOptsWs = WebSocketClient.InitOptions;
const IpcClient = @import("IPC.zig");
const Keccak256 = std.crypto.hash.sha3.Keccak256;
const Mutex = std.Thread.Mutex;
const PubClient = @import("Client.zig");
const RPCResponse = types.RPCResponse;
const SerializeErrors = serialize.SerializeErrors;
const Sidecar = ckzg4844.KZG4844.Sidecar;
const Signer = zabi_crypto.Signer;
const Signature = zabi_crypto.signature.Signature;
const TransactionEnvelope = transaction.TransactionEnvelope;
const TransactionReceipt = transaction.TransactionReceipt;
const TypedDataDomain = eip712.TypedDataDomain;
const UnpreparedTransactionEnvelope = transaction.UnpreparedTransactionEnvelope;
const WebSocketClient = @import("WebSocket.zig");

/// The type of client used by the wallet instance.
pub const WalletClients = enum { http, websocket, ipc };

/// Wallet instance with rpc http/s client.
pub const WalletHttpClient = Wallet(.http);
/// Wallet instance with rpc ws/s client.
pub const WalletWsClient = Wallet(.websocket);
/// Wallet instance with rpc ipc client.
pub const WalletIpcClient = Wallet(.ipc);

pub const TransactionEnvelopePool = struct {
    mutex: Mutex = .{},
    pooled_envelopes: TransactionEnvelopeQueue,

    pub const Node = TransactionEnvelopeQueue.Node;

    const SearchCriteria = struct {
        type: transaction.TransactionTypes,
        nonce: u64,
    };

    const TransactionEnvelopeQueue = std.DoublyLinkedList(TransactionEnvelope);

    /// Finds a transaction envelope from the pool based on the
    /// transaction type and it's nonce in case there are transactions with the same type. This is thread safe.
    ///
    /// Returns null if no transaction was found
    pub fn findTransactionEnvelope(pool: *TransactionEnvelopePool, allocator: Allocator, search: SearchCriteria) ?TransactionEnvelope {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        var last_tx_node = pool.pooled_envelopes.last;

        while (last_tx_node) |tx_node| : (last_tx_node = tx_node.prev) {
            switch (tx_node.data) {
                inline else => |pooled_tx| if (pooled_tx.nonce != search.nonce) continue,
            }

            if (!std.mem.eql(u8, @tagName(tx_node.data), @tagName(search.type))) continue;
            defer allocator.destroy(tx_node);

            pool.unsafeReleaseEnvelopeFromPool(tx_node);
            return tx_node.data;
        }

        return null;
    }
    /// Adds a new node into the pool. This is thread safe.
    pub fn addEnvelopeToPool(pool: *TransactionEnvelopePool, node: *Node) void {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        pool.pooled_envelopes.append(node);
    }
    /// Removes a node from the pool. This is not thread safe.
    pub fn unsafeReleaseEnvelopeFromPool(pool: *TransactionEnvelopePool, node: *Node) void {
        pool.pooled_envelopes.remove(node);
    }
    /// Removes a node from the pool. This is thread safe.
    pub fn releaseEnvelopeFromPool(pool: *TransactionEnvelopePool, node: *Node) void {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        pool.pooled_envelopes.remove(node);
    }
    /// Gets the last node from the pool and removes it.
    /// This is thread safe.
    pub fn getFirstElementFromPool(pool: *TransactionEnvelopePool, allocator: Allocator) ?TransactionEnvelope {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        if (pool.pooled_envelopes.popFirst()) |node| {
            defer allocator.destroy(node);

            return node.data;
        } else return null;
    }
    /// Gets the last node from the pool and removes it.
    /// This is thread safe.
    pub fn getLastElementFromPool(pool: *TransactionEnvelopePool, allocator: Allocator) ?TransactionEnvelope {
        pool.mutex.lock();
        defer pool.mutex.unlock();

        if (pool.pooled_envelopes.pop()) |node| {
            defer allocator.destroy(node);

            return node.data;
        } else return null;
    }
    /// Destroys all created pointer. All future operations will deadlock.
    /// This is thread safe.
    pub fn deinit(pool: *TransactionEnvelopePool, allocator: Allocator) void {
        pool.mutex.lock();

        var first = pool.pooled_envelopes.first;
        while (first) |node| {
            defer allocator.destroy(node);
            first = node.next;
        }

        pool.* = undefined;
    }
};

/// Creates a wallet instance based on which type of client defined in
/// `WalletClients`. Depending on the type of client the underlaying methods
/// of `rpc_client` can be changed. The http and websocket client do not
/// mirror 100% in terms of their methods.
///
/// The client's methods can all be accessed under `rpc_client`.
/// The same goes for the signer.
pub fn Wallet(comptime client_type: WalletClients) type {
    return struct {
        /// The wallet underlaying rpc client type (ws, http or ipc)
        const ClientType = switch (client_type) {
            .http => PubClient,
            .websocket => WebSocketClient,
            .ipc => IpcClient,
        };

        /// The inital settings depending on the client type.
        const InitOpts = switch (client_type) {
            .http => InitOptsHttp,
            .websocket => InitOptsWs,
            .ipc => InitOptsIpc,
        };

        const WalletSelf = Wallet(client_type);

        /// Set of possible errors when starting the wallet.
        pub const InitErrors = ClientType.InitErrors || error{IdentityElement};

        /// Set of common errors produced by wallet actions.
        pub const Error = ClientType.BasicRequestErrors;

        /// Set of errors when preparing a transaction
        pub const PrepareError = Error || error{ InvalidBlockNumber, UnableToFetchFeeInfoFromBlock, MaxFeePerGasUnderflow, UnsupportedTransactionType };

        /// Set of errors that can be returned on the `assertTransaction` method.
        pub const AssertionErrors = error{
            InvalidChainId,
            TransactionTipToHigh,
            EmptyBlobs,
            TooManyBlobs,
            BlobVersionNotSupported,
            CreateBlobTransaction,
        };

        /// Set of possible errors when sending signed transactions
        pub const SendSignedTransactionErrors = Error || Signer.SigningErrors || SerializeErrors;

        /// Nonce manager that use's the rpc client as the source of truth
        /// for checking internally that the cached and managed values can be used.
        pub const NonceManager = struct {
            /// The address that will get it's nonce managed.
            address: Address,
            /// The current nonce in use.
            managed: u64,
            /// The cached nonce.
            cache: u64,

            const Self = @This();

            /// Sets the initial state of the `NonceManager`.
            pub fn initManager(address: Address) NonceManager {
                return .{
                    .address = address,
                    .managed = 0,
                    .cache = 0,
                };
            }
            /// Gets the nonce from either the cache or from the network.
            ///
            /// Resets the `manager` nonce value and the `cache` if the nonce value from the network
            /// is higher than one from the `cache`.
            pub fn getNonce(self: *Self, rpc_client: *ClientType) ClientType.BasicRequestErrors!u64 {
                const nonce: u64 = nonce: {
                    const nonce = try rpc_client.getAddressTransactionCount(.{
                        .address = self.address,
                        .tag = .pending,
                    });
                    defer nonce.deinit();

                    const cached_nonce = self.cache;
                    defer self.resetNonce();

                    if (cached_nonce > 0 and nonce.response <= cached_nonce)
                        break :nonce cached_nonce + 1;

                    self.cache = 0;
                    break :nonce nonce.response;
                };

                const nonce_from_manager = self.managed;

                return nonce + nonce_from_manager;
            }
            /// Increments the `manager` by one.
            pub fn incrementNonce(self: *Self) void {
                self.managed += 1;
            }
            /// Gets the nonce from either the cache or from the network and updates internally.
            ///
            /// Resets the `manager` nonce value and the `cache` if the nonce value from the network
            /// is higher than one from the `cache`.
            pub fn updateNonce(self: *Self, rpc_client: *ClientType) ClientType.BasicRequestErrors!u64 {
                self.incrementNonce();
                const nonce: u64 = nonce: {
                    const nonce = try rpc_client.getAddressTransactionCount(.{
                        .address = self.address,
                        .tag = .pending,
                    });
                    defer nonce.deinit();

                    const cached_nonce = self.cache;
                    defer self.resetNonce();

                    if (cached_nonce > 0 and nonce.response <= cached_nonce)
                        break :nonce cached_nonce + 1;

                    self.cache = 0;
                    break :nonce nonce.response;
                };

                self.cache = nonce;

                return nonce;
            }
            /// Resets the `manager` to 0.
            pub fn resetNonce(self: *Self) void {
                self.managed = 0;
            }
        };

        /// Allocator used by the wallet implementation
        allocator: Allocator,
        /// Pool to store all prepated transaction envelopes.\
        /// This is thread safe.
        envelopes_pool: TransactionEnvelopePool,
        /// Internall nonce manager.\
        /// Set it null to just use the network to update nonce values.
        nonce_manager: ?NonceManager,
        /// JSON-RPC client used to make request. Supports almost all `eth_` rpc methods.
        rpc_client: *ClientType,
        /// Signer that will sign transactions or ethereum messages.\
        /// Its based on a custom implementation meshed with zig's source code.
        signer: Signer,

        /// Sets the wallet initial state.
        ///
        /// The init opts will depend on the [client_type](/api/clients/wallet#walletclients).\
        /// Also add the hability to use a nonce manager or to use the network directly.
        ///
        /// **Example**
        /// ```zig
        /// const uri = try std.Uri.parse("http://localhost:6969/");
        ///
        /// var buffer: Hash = undefined;
        /// _ = try std.fmt.hexToBytes(&buffer, "ac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
        ///
        /// var wallet = try Wallet(.http).init(buffer, .{
        ///     .allocator = testing.allocator,
        ///     .network_config = .{
        ///         .endpoint = .{ .uri = uri },
        ///     },
        /// }, true);
        /// defer wallet.deinit();
        /// ```
        pub fn init(private_key: ?Hash, opts: InitOpts, nonce_manager: bool) (error{IdentityElement} || ClientType.InitErrors)!*WalletSelf {
            const self = try opts.allocator.create(WalletSelf);
            errdefer opts.allocator.destroy(self);

            const signer = try Signer.init(private_key);

            self.* = .{
                .allocator = opts.allocator,
                .rpc_client = undefined,
                .signer = signer,
                .envelopes_pool = .{ .pooled_envelopes = .{} },
                .nonce_manager = if (nonce_manager) NonceManager.initManager(signer.address_bytes) else null,
            };

            self.rpc_client = try ClientType.init(opts);

            return self;
        }
        /// Clears memory and destroys any created pointers
        pub fn deinit(self: *WalletSelf) void {
            self.envelopes_pool.deinit(self.allocator);
            self.rpc_client.deinit();

            const allocator = self.allocator;
            allocator.destroy(self);
        }
        /// Asserts that the transactions is ready to be sent.
        /// Will return errors where the values are not expected
        pub fn assertTransaction(self: *WalletSelf, tx: TransactionEnvelope) AssertionErrors!void {
            switch (tx) {
                .london => |tx_eip1559| {
                    if (tx_eip1559.chainId != @intFromEnum(self.rpc_client.network_config.chain_id)) return error.InvalidChainId;
                    if (tx_eip1559.maxPriorityFeePerGas > tx_eip1559.maxFeePerGas) return error.TransactionTipToHigh;
                },
                .cancun => |tx_eip4844| {
                    if (tx_eip4844.chainId != @intFromEnum(self.rpc_client.network_config.chain_id)) return error.InvalidChainId;
                    if (tx_eip4844.maxPriorityFeePerGas > tx_eip4844.maxFeePerGas) return error.TransactionTipToHigh;

                    if (tx_eip4844.blobVersionedHashes) |blob_hashes| {
                        if (blob_hashes.len == 0)
                            return error.EmptyBlobs;

                        if (blob_hashes.len > constants.MAX_BLOB_NUMBER_PER_BLOCK)
                            return error.TooManyBlobs;

                        for (blob_hashes) |hashes| {
                            if (hashes[0] != constants.VERSIONED_HASH_VERSION_KZG)
                                return error.BlobVersionNotSupported;
                        }
                    }

                    if (tx_eip4844.to == null)
                        return error.CreateBlobTransaction;
                },
                .berlin => |tx_eip2930| {
                    if (tx_eip2930.chainId != @intFromEnum(self.rpc_client.network_config.chain_id)) return error.InvalidChainId;
                },
                .legacy => |tx_legacy| {
                    if (tx_legacy.chainId != 0 and tx_legacy.chainId != @intFromEnum(self.rpc_client.network_config.chain_id)) return error.InvalidChainId;
                },
            }
        }
        /// Converts to a message that the contracts executing `AUTH` opcodes can understand.\
        /// For more details on the implementation see [here](https://eips.ethereum.org/EIPS/eip-3074#specification).
        ///
        /// You can pass null to `nonce` if you want to target a specific nonce.\
        /// Otherwise if with either use the `nonce_manager` if it can or fetch from the network.\
        /// Memory must be freed after calling this method.
        ///
        /// This is still experimental since the EIP has not being deployed into any mainnet.
        pub fn authMessageEip3074(
            self: *WalletSelf,
            invoker_address: Address,
            nonce: ?u64,
            commitment: Hash,
        ) ClientType.BasicRequestErrors![]u8 {
            const nonce_from: u256 = nonce: {
                if (nonce) |nonce_unwrapped|
                    break :nonce @intCast(nonce_unwrapped);

                if (self.nonce_manager) |*manager| {
                    break :nonce @intCast(try manager.getNonce(self.rpc_client));
                }

                const rpc_nonce = try self.rpc_client.getAddressTransactionCount(.{
                    .tag = .pending,
                    .address = self.signer.address_bytes,
                });
                defer rpc_nonce.deinit();

                break :nonce @intCast(rpc_nonce.response);
            };

            const address_int: u160 = @bitCast(invoker_address);

            const values: struct { u8, u256, u256, u256, Hash } = .{
                // MAGIC_NUMBER -> https://eips.ethereum.org/EIPS/eip-3074#specification
                0x04,
                @intCast(@intFromEnum(self.rpc_client.network_config.chain_id)),
                nonce_from,
                @intCast(address_int),
                commitment,
            };

            const message = try encoder.encodePacked(self.allocator, values);

            return message;
        }
        /// Find a specific prepared envelope from the pool based on the given search criteria.
        pub fn findTransactionEnvelopeFromPool(self: *WalletSelf, search: TransactionEnvelopePool.SearchCriteria) ?TransactionEnvelope {
            return self.envelopes_pool.findTransactionEnvelope(self.allocator, search);
        }
        /// Get the wallet address.
        ///
        /// Uses the wallet public key to generate the address.
        pub fn getWalletAddress(self: *WalletSelf) Address {
            return self.signer.address_bytes;
        }
        /// Converts unprepared transaction envelopes and stores them in a pool.
        ///
        /// This appends to the last node of the list.
        pub fn poolTransactionEnvelope(self: *WalletSelf, unprepared_envelope: UnpreparedTransactionEnvelope) PrepareError!void {
            const envelope = try self.allocator.create(TransactionEnvelopePool.Node);
            errdefer self.allocator.destroy(envelope);

            envelope.* = .{ .data = undefined };

            envelope.data = try self.prepareTransaction(unprepared_envelope);
            self.envelopes_pool.addEnvelopeToPool(envelope);
        }
        /// Prepares a transaction based on it's type so that it can be sent through the network.\
        ///
        /// Only the null struct properties will get changed.\
        /// Everything that gets set before will not be touched.
        pub fn prepareTransaction(
            self: *WalletSelf,
            unprepared_envelope: UnpreparedTransactionEnvelope,
        ) PrepareError!TransactionEnvelope {
            const address = self.getWalletAddress();

            switch (unprepared_envelope.type) {
                .cancun => {
                    var request: LondonEthCall = .{
                        .from = address,
                        .to = unprepared_envelope.to,
                        .gas = unprepared_envelope.gas,
                        .maxFeePerGas = unprepared_envelope.maxFeePerGas,
                        .maxPriorityFeePerGas = unprepared_envelope.maxPriorityFeePerGas,
                        .data = unprepared_envelope.data,
                        .value = unprepared_envelope.value orelse 0,
                    };

                    const curr_block = try self.rpc_client.getBlockByNumber(.{});
                    defer curr_block.deinit();

                    const base_fee = switch (curr_block.response) {
                        inline else => |block_info| block_info.baseFeePerGas,
                    };

                    const chain_id = unprepared_envelope.chainId orelse @intFromEnum(self.rpc_client.network_config.chain_id);
                    const accessList: []const AccessList = unprepared_envelope.accessList orelse &.{};
                    const max_fee_per_blob = unprepared_envelope.maxFeePerBlobGas orelse try self.rpc_client.estimateBlobMaxFeePerGas();
                    const blob_version = unprepared_envelope.blobVersionedHashes orelse &.{};

                    const nonce: u64 = unprepared_envelope.nonce orelse blk: {
                        if (self.nonce_manager) |*manager| {
                            const nonce = try manager.updateNonce(self.rpc_client);

                            break :blk nonce;
                        } else {
                            const nonce = try self.rpc_client.getAddressTransactionCount(.{
                                .address = self.signer.address_bytes,
                                .tag = .pending,
                            });
                            defer nonce.deinit();

                            break :blk nonce.response;
                        }
                    };

                    if (unprepared_envelope.maxFeePerGas == null or unprepared_envelope.maxPriorityFeePerGas == null) {
                        const fees = try self.rpc_client.estimateFeesPerGas(.{ .london = request }, base_fee);
                        request.maxPriorityFeePerGas = unprepared_envelope.maxPriorityFeePerGas orelse fees.london.max_priority_fee;
                        request.maxFeePerGas = unprepared_envelope.maxFeePerGas orelse fees.london.max_fee_gas;

                        if (unprepared_envelope.maxFeePerGas) |fee| {
                            if (fee < fees.london.max_priority_fee) return error.MaxFeePerGasUnderflow;
                        }
                    }

                    if (unprepared_envelope.gas == null) {
                        const gas = try self.rpc_client.estimateGas(.{ .london = request }, .{});
                        defer gas.deinit();

                        request.gas = gas.response;
                    }

                    return .{
                        .cancun = .{
                            .chainId = chain_id,
                            .nonce = nonce,
                            .gas = request.gas.?,
                            .maxFeePerGas = request.maxFeePerGas.?,
                            .maxPriorityFeePerGas = request.maxPriorityFeePerGas.?,
                            .maxFeePerBlobGas = max_fee_per_blob,
                            .to = request.to,
                            .data = request.data,
                            .value = request.value.?,
                            .accessList = accessList,
                            .blobVersionedHashes = blob_version,
                        },
                    };
                },
                .london => {
                    var request: LondonEthCall = .{
                        .to = unprepared_envelope.to,
                        .from = address,
                        .gas = unprepared_envelope.gas,
                        .maxFeePerGas = unprepared_envelope.maxFeePerGas,
                        .maxPriorityFeePerGas = unprepared_envelope.maxPriorityFeePerGas,
                        .data = unprepared_envelope.data,
                        .value = unprepared_envelope.value orelse 0,
                    };

                    const curr_block = try self.rpc_client.getBlockByNumber(.{});
                    defer curr_block.deinit();

                    const base_fee = switch (curr_block.response) {
                        inline else => |block_info| block_info.baseFeePerGas,
                    };

                    const chain_id = unprepared_envelope.chainId orelse @intFromEnum(self.rpc_client.network_config.chain_id);
                    const accessList: []const AccessList = unprepared_envelope.accessList orelse &.{};

                    const nonce: u64 = unprepared_envelope.nonce orelse blk: {
                        if (self.nonce_manager) |*manager| {
                            const nonce = try manager.updateNonce(self.rpc_client);

                            break :blk nonce;
                        } else {
                            const nonce = try self.rpc_client.getAddressTransactionCount(.{ .address = self.signer.address_bytes, .tag = .pending });
                            defer nonce.deinit();

                            break :blk nonce.response;
                        }
                    };

                    if (unprepared_envelope.maxFeePerGas == null or unprepared_envelope.maxPriorityFeePerGas == null) {
                        const fees = try self.rpc_client.estimateFeesPerGas(.{ .london = request }, base_fee);
                        request.maxPriorityFeePerGas = unprepared_envelope.maxPriorityFeePerGas orelse fees.london.max_priority_fee;
                        request.maxFeePerGas = unprepared_envelope.maxFeePerGas orelse fees.london.max_fee_gas;

                        if (unprepared_envelope.maxFeePerGas) |fee| {
                            if (fee < fees.london.max_priority_fee) return error.MaxFeePerGasUnderflow;
                        }
                    }

                    if (unprepared_envelope.gas == null) {
                        const gas = try self.rpc_client.estimateGas(.{ .london = request }, .{});
                        defer gas.deinit();

                        request.gas = gas.response;
                    }

                    return .{
                        .london = .{
                            .chainId = chain_id,
                            .nonce = nonce,
                            .gas = request.gas.?,
                            .maxFeePerGas = request.maxFeePerGas.?,
                            .maxPriorityFeePerGas = request.maxPriorityFeePerGas.?,
                            .to = request.to,
                            .data = request.data,
                            .value = request.value.?,
                            .accessList = accessList,
                        },
                    };
                },
                .berlin => {
                    var request: LegacyEthCall = .{
                        .from = address,
                        .to = unprepared_envelope.to,
                        .gas = unprepared_envelope.gas,
                        .gasPrice = unprepared_envelope.gasPrice,
                        .data = unprepared_envelope.data,
                        .value = unprepared_envelope.value orelse 0,
                    };

                    const curr_block = try self.rpc_client.getBlockByNumber(.{});
                    defer curr_block.deinit();

                    const base_fee = switch (curr_block.response) {
                        inline else => |block_info| block_info.baseFeePerGas,
                    };

                    const chain_id = unprepared_envelope.chainId orelse @intFromEnum(self.rpc_client.network_config.chain_id);
                    const accessList: []const AccessList = unprepared_envelope.accessList orelse &.{};

                    const nonce: u64 = unprepared_envelope.nonce orelse blk: {
                        if (self.nonce_manager) |*manager| {
                            const nonce = try manager.updateNonce(self.rpc_client);

                            break :blk nonce;
                        } else {
                            const nonce = try self.rpc_client.getAddressTransactionCount(.{ .address = self.signer.address_bytes, .tag = .pending });
                            defer nonce.deinit();

                            break :blk nonce.response;
                        }
                    };

                    if (unprepared_envelope.gasPrice == null) {
                        const fees = try self.rpc_client.estimateFeesPerGas(.{ .legacy = request }, base_fee);
                        request.gasPrice = fees.legacy.gas_price;
                    }

                    if (unprepared_envelope.gas == null) {
                        const gas = try self.rpc_client.estimateGas(.{ .legacy = request }, .{});
                        defer gas.deinit();

                        request.gas = gas.response;
                    }

                    return .{
                        .berlin = .{
                            .chainId = chain_id,
                            .nonce = nonce,
                            .gas = request.gas.?,
                            .gasPrice = request.gasPrice.?,
                            .to = request.to,
                            .data = request.data,
                            .value = request.value.?,
                            .accessList = accessList,
                        },
                    };
                },
                .legacy => {
                    var request: LegacyEthCall = .{
                        .from = address,
                        .to = unprepared_envelope.to,
                        .gas = unprepared_envelope.gas,
                        .gasPrice = unprepared_envelope.gasPrice,
                        .data = unprepared_envelope.data,
                        .value = unprepared_envelope.value orelse 0,
                    };

                    const curr_block = try self.rpc_client.getBlockByNumber(.{});
                    defer curr_block.deinit();

                    const base_fee = switch (curr_block.response) {
                        inline else => |block_info| block_info.baseFeePerGas,
                    };

                    const chain_id = unprepared_envelope.chainId orelse @intFromEnum(self.rpc_client.network_config.chain_id);

                    const nonce: u64 = unprepared_envelope.nonce orelse blk: {
                        if (self.nonce_manager) |*manager| {
                            const nonce = try manager.updateNonce(self.rpc_client);

                            break :blk nonce;
                        } else {
                            const nonce = try self.rpc_client.getAddressTransactionCount(.{ .address = self.signer.address_bytes, .tag = .pending });
                            defer nonce.deinit();

                            break :blk nonce.response;
                        }
                    };

                    if (unprepared_envelope.gasPrice == null) {
                        const fees = try self.rpc_client.estimateFeesPerGas(.{ .legacy = request }, base_fee);
                        request.gasPrice = fees.legacy.gas_price;
                    }

                    if (unprepared_envelope.gas == null) {
                        const gas = try self.rpc_client.estimateGas(.{ .legacy = request }, .{});
                        defer gas.deinit();

                        request.gas = gas.response;
                    }

                    return .{
                        .legacy = .{
                            .chainId = chain_id,
                            .nonce = nonce,
                            .gas = request.gas.?,
                            .gasPrice = request.gasPrice.?,
                            .to = request.to,
                            .data = request.data,
                            .value = request.value.?,
                        },
                    };
                },
                .deposit => return error.UnsupportedTransactionType,
                _ => return error.UnsupportedTransactionType,
            }
        }
        /// Recovers the address associated with the signature based on the message.\
        /// To reconstruct the message use `authMessageEip3074`
        ///
        /// You can pass null to `nonce` if you want to target a specific nonce.\
        /// Otherwise if with either use the `nonce_manager` if it can or fetch from the network.
        ///
        /// Reconstructs the message from them and returns the address bytes.
        pub fn recoverAuthMessageAddress(
            auth_message: []u8,
            sig: Signature,
        ) Signer.RecoverPubKeyErrors!Address {
            var hash: Hash = undefined;
            Keccak256.hash(auth_message, &hash, .{});

            return Signer.recoverAddress(sig, hash);
        }
        /// Search the internal `TransactionEnvelopePool` to find the specified transaction based on the `type` and nonce.
        ///
        /// If there are duplicate transaction that meet the search criteria it will send the first it can find.\
        /// The search is linear and starts from the first node of the pool.
        pub fn searchPoolAndSendTransaction(
            self: *WalletSelf,
            search_opts: TransactionEnvelopePool.SearchCriteria,
        ) (SendSignedTransactionErrors || AssertionErrors || error{TransactionNotFoundInPool})!RPCResponse(Hash) {
            const prepared = self.envelopes_pool.findTransactionEnvelope(self.allocator, search_opts) orelse return error.TransactionNotFoundInPool;

            try self.assertTransaction(prepared);

            return self.sendSignedTransaction(prepared);
        }
        /// Sends blob transaction to the network.
        /// Trusted setup must be loaded otherwise this will fail.
        pub fn sendBlobTransaction(
            self: *WalletSelf,
            blobs: []const Blob,
            unprepared_envelope: UnpreparedTransactionEnvelope,
            trusted_setup: *KZG4844,
        ) !RPCResponse(Hash) {
            if (unprepared_envelope.type != .cancun)
                return error.InvalidTransactionType;

            if (!trusted_setup.loaded)
                return error.TrustedSetupNotLoaded;

            const prepared = self.envelopes_pool.getLastElementFromPool(self.allocator) orelse try self.prepareTransaction(unprepared_envelope);

            try self.assertTransaction(prepared);

            const serialized = try serialize.serializeCancunTransactionWithBlobs(self.allocator, prepared, null, blobs, trusted_setup);
            defer self.allocator.free(serialized);

            var hash_buffer: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash_buffer, .{});

            const signed = try self.signer.sign(hash_buffer);
            const serialized_signed = try serialize.serializeCancunTransactionWithBlobs(self.allocator, prepared, signed, blobs, trusted_setup);
            defer self.allocator.free(serialized_signed);

            return self.rpc_client.sendRawTransaction(serialized_signed);
        }
        /// Sends blob transaction to the network.
        /// This uses and already prepared sidecar.
        pub fn sendSidecarTransaction(
            self: *WalletSelf,
            sidecars: []const Sidecar,
            unprepared_envelope: UnpreparedTransactionEnvelope,
        ) !RPCResponse(Hash) {
            if (unprepared_envelope.type != .cancun)
                return error.InvalidTransactionType;

            const prepared = self.envelopes_pool.getLastElementFromPool(self.allocator) orelse try self.prepareTransaction(unprepared_envelope);

            try self.assertTransaction(prepared);

            const serialized = try serialize.serializeCancunTransactionWithSidecars(self.allocator, prepared, null, sidecars);
            defer self.allocator.free(serialized);

            var hash_buffer: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash_buffer, .{});

            const signed = try self.signer.sign(hash_buffer);
            const serialized_signed = try serialize.serializeCancunTransactionWithSidecars(self.allocator, prepared, signed, sidecars);
            defer self.allocator.free(serialized_signed);

            return self.rpc_client.sendRawTransaction(serialized_signed);
        }
        /// Signs, serializes and send the transaction via `eth_sendRawTransaction`.
        ///
        /// Returns the transaction hash.
        pub fn sendSignedTransaction(self: *WalletSelf, tx: TransactionEnvelope) SendSignedTransactionErrors!RPCResponse(Hash) {
            const serialized = try serialize.serializeTransaction(self.allocator, tx, null);
            defer self.allocator.free(serialized);

            var hash_buffer: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(serialized, &hash_buffer, .{});

            const signed = try self.signer.sign(hash_buffer);
            const serialized_signed = try serialize.serializeTransaction(self.allocator, tx, signed);
            defer self.allocator.free(serialized_signed);

            return self.rpc_client.sendRawTransaction(serialized_signed);
        }
        /// Prepares, asserts, signs and sends the transaction via `eth_sendRawTransaction`.
        ///
        /// If any envelope is in the envelope pool it will use that instead in a LIFO order.\
        /// Will return an error if the envelope is incorrect
        pub fn sendTransaction(
            self: *WalletSelf,
            unprepared_envelope: UnpreparedTransactionEnvelope,
        ) (SendSignedTransactionErrors || AssertionErrors || PrepareError)!RPCResponse(Hash) {
            const prepared = self.envelopes_pool.getLastElementFromPool(self.allocator) orelse try self.prepareTransaction(unprepared_envelope);

            try self.assertTransaction(prepared);

            return self.sendSignedTransaction(prepared);
        }
        /// Signs and prepares an eip3074 authorization message.
        /// For more details on the implementation see [here](https://eips.ethereum.org/EIPS/eip-3074#specification).
        ///
        /// You can pass null to `nonce` if you want to target a specific nonce.\
        /// Otherwise if with either use the `nonce_manager` if it can or fetch from the network.
        ///
        /// This is still experimental since the EIP has not being deployed into any mainnet.
        pub fn signAuthMessageEip3074(
            self: *WalletSelf,
            invoker_address: Address,
            nonce: ?u64,
            commitment: Hash,
        ) (ClientType.BasicRequestErrors || Signer.SigningErrors)!Signature {
            const message = try self.authMessageEip3074(invoker_address, nonce, commitment);
            defer self.allocator.free(message);

            var hash_buffer: Hash = undefined;
            Keccak256.hash(message, &hash_buffer, .{});

            return self.signer.sign(hash_buffer);
        }
        /// Signs an ethereum message with the specified prefix.
        ///
        /// The Signatures recoverId doesn't include the chain_id.
        pub fn signEthereumMessage(self: *WalletSelf, message: []const u8) (Signer.SigningErrors || Allocator.Error)!Signature {
            const start = "\x19Ethereum Signed Message:\n";
            const concated_message = try std.fmt.allocPrint(self.allocator, "{s}{d}{s}", .{ start, message.len, message });
            defer self.allocator.free(concated_message);

            var hash: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(concated_message, &hash, .{});

            return self.signer.sign(hash);
        }
        /// Signs a EIP712 message according to the expecification
        /// https://eips.ethereum.org/EIPS/eip-712
        ///
        /// `types` parameter is expected to be a struct where the struct
        /// keys are used to grab the solidity type information so that the
        /// encoding and hashing can happen based on it. See the specification
        /// for more details.
        ///
        /// `primary_type` is the expected main type that you want to hash this message.
        /// Compilation will fail if the provided string doesn't exist on the `types` parameter
        ///
        /// `domain` is the values of the defined EIP712Domain. Currently it doesnt not support custom
        /// domain types.
        ///
        /// `message` is expected to be a struct where the solidity types are transalated to the native
        /// zig types. I.E string -> []const u8 or int256 -> i256 and so on.
        /// In the future work will be done where the compiler will offer more clearer types
        /// base on a meta programming type function.
        ///
        /// Returns the signature type.
        pub fn signTypedData(
            self: *WalletSelf,
            comptime eip_types: anytype,
            comptime primary_type: []const u8,
            domain: ?TypedDataDomain,
            message: anytype,
        ) (Signer.SigningErrors || EIP712Errors)!Signature {
            return self.signer.sign(try eip712.hashTypedData(self.allocator, eip_types, primary_type, domain, message));
        }
        /// Verifies if the auth message was signed by the provided address.\
        /// To reconstruct the message use `authMessageEip3074`.
        ///
        /// You can pass null to `expected_address` if you want to use this wallet instance
        /// associated address.
        pub fn verifyAuthMessage(
            self: *WalletSelf,
            expected_address: ?Address,
            auth_message: []u8,
            sig: Signature,
        ) (ClientType.BasicRequestErrors || Signer.RecoverPubKeyErrors)!bool {
            const expected_addr: u160 = @bitCast(expected_address orelse self.signer.address_bytes);

            const recovered_address: u160 = @bitCast(try recoverAuthMessageAddress(auth_message, sig));

            return expected_addr == recovered_address;
        }
        /// Verifies if a given signature was signed by the current wallet.
        pub fn verifyMessage(self: *WalletSelf, sig: Signature, message: []const u8) bool {
            var hash_buffer: [Keccak256.digest_length]u8 = undefined;
            Keccak256.hash(message, &hash_buffer, .{});
            return self.signer.verifyMessage(hash_buffer, sig);
        }
        /// Verifies a EIP712 message according to the expecification
        /// https://eips.ethereum.org/EIPS/eip-712
        ///
        /// `types` parameter is expected to be a struct where the struct
        /// keys are used to grab the solidity type information so that the
        /// encoding and hashing can happen based on it. See the specification
        /// for more details.
        ///
        /// `primary_type` is the expected main type that you want to hash this message.
        /// Compilation will fail if the provided string doesn't exist on the `types` parameter
        ///
        /// `domain` is the values of the defined EIP712Domain. Currently it doesnt not support custom
        /// domain types.
        ///
        /// `message` is expected to be a struct where the solidity types are transalated to the native
        /// zig types. I.E string -> []const u8 or int256 -> i256 and so on.
        /// In the future work will be done where the compiler will offer more clearer types
        /// base on a meta programming type function.
        ///
        /// Returns the signature type.
        pub fn verifyTypedData(
            self: *WalletSelf,
            sig: Signature,
            comptime eip712_types: anytype,
            comptime primary_type: []const u8,
            domain: ?TypedDataDomain,
            message: anytype,
        ) (EIP712Errors || Signer.RecoverPubKeyErrors)!bool {
            const hash = try eip712.hashTypedData(self.allocator, eip712_types, primary_type, domain, message);

            const address: u160 = @bitCast(try Signer.recoverAddress(sig, hash));
            const wallet_address: u160 = @bitCast(self.getWalletAddress());

            return address == wallet_address;
        }
        /// Waits until the transaction gets mined and we can grab the receipt.
        /// It fails if the retry counter is excedded.
        ///
        /// The behaviour of this method varies based on the client type.
        ///
        /// If it's called with the websocket client or the ipc client it will create a subscription for new block and wait
        /// until the transaction gets mined. Otherwise it will use the rpc_client `pooling_interval` property.
        pub fn waitForTransactionReceipt(self: *WalletSelf, tx_hash: Hash, confirmations: u8) (Error || error{
            FailedToGetReceipt,
            TransactionReceiptNotFound,
            TransactionNotFound,
            InvalidBlockNumber,
            FailedToUnsubscribe,
        })!RPCResponse(TransactionReceipt) {
            return self.rpc_client.waitForTransactionReceipt(tx_hash, confirmations);
        }
    };
}
