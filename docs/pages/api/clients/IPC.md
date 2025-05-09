## InitErrors

Set of possible errors when starting the client.

```zig
Allocator.Error || std.Thread.SpawnError || error{ InvalidNetworkConfig, InvalidIPCPath, FailedToConnect }
```

## ReadLoopErrors

Set of possible errors when reading from the socket.

```zig
SetSockOptError || error{ FailedToJsonParseResponse, Closed, InvalidTypeMessage, UnexpectedError }
```

## SendRpcRequestErrors

Set of possible errors when send a rpc request.

```zig
Allocator.Error || EthereumZigErrors || std.posix.WriteError || ParseFromValueError || error{ReachedMaxRetryLimit}
```

## BasicRequestErrors

Set of generic errors when sending a rpc request.

```zig
SendRpcRequestErrors || error{NoSpaceLeft}
```

## InitOptions

Set of intial options for the IPC Client.

### Properties

```zig
struct {
  /// Allocator to use to create the ChildProcess and other allocations
  allocator: Allocator
  /// The reader buffer growth rate
  growth_rate: ?usize = null
  /// The target chains config.
  network_config: NetworkConfig
  /// Callback function for when the connection is closed.
  onClose: ?*const fn () void = null
  /// Callback function for everytime an event is parsed.
  onEvent: ?*const fn (args: JsonParsed(Value)) anyerror!void = null
  /// Callback function for everytime an error is caught.
  onError: ?*const fn (args: []const u8) anyerror!void = null
}
```

## Init
Starts the IPC client and create the connection.

This will also start the read loop in a seperate thread.

**Example**
```zig
 var client = try IPC.init(.{
    .allocator = testing.allocator,
    .network_config = .{
        .endpoint = .{ .path = "/tmp/anvil.ipc" },
    },
 });
 defer client.deinit();
```

### Signature

```zig
pub fn init(opts: InitOptions) InitErrors!*IPC
```

## Deinit
Clears memory, closes the stream and destroys any
previously created pointers.

All future calls will deadlock.

### Signature

```zig
pub fn deinit(self: *IPC) void
```

## Connect
Connects to the socket. Will try to reconnect in case of failures.\
Fails when match retries are reached or a invalid ipc path is provided

### Signature

```zig
pub fn connect(
    self: *IPC,
    path: []const u8,
) error{ InvalidIPCPath, FailedToConnect }!Stream
```

## BlobBaseFee
Grabs the current base blob fee.

RPC Method: [eth_blobBaseFee](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blobbasefee)

### Signature

```zig
pub fn blobBaseFee(self: *IPC) BasicRequestErrors!RPCResponse(Gwei)
```

## CreateAccessList
Create an accessList of addresses and storageKeys for a transaction to access

RPC Method: [eth_createAccessList](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_createaccesslist)

### Signature

```zig
pub fn createAccessList(
    self: *IPC,
    call_object: EthCall,
    opts: BlockNumberRequest,
) BasicRequestErrors!RPCResponse(AccessListResult)
```

## EstimateBlobMaxFeePerGas
Estimate the gas used for blobs
Uses `blobBaseFee` and `gasPrice` to calculate this estimation

### Signature

```zig
pub fn estimateBlobMaxFeePerGas(self: *IPC) BasicRequestErrors!Gwei
```

## EstimateFeesPerGas
Estimate maxPriorityFeePerGas and maxFeePerGas. Will make more than one network request.
Uses the `baseFeePerGas` included in the block to calculate the gas fees.
Will return an error in case the `baseFeePerGas` is null.

### Signature

```zig
pub fn estimateFeesPerGas(
    self: *IPC,
    call_object: EthCall,
    base_fee_per_gas: ?Gwei,
) (BasicRequestErrors || error{ InvalidBlockNumber, UnableToFetchFeeInfoFromBlock })!EstimateFeeReturn
```

## EstimateGas
Generates and returns an estimate of how much gas is necessary to allow the transaction to complete.
The transaction will not be added to the blockchain.
Note that the estimate may be significantly more than the amount of gas actually used by the transaction,
for a variety of reasons including EVM mechanics and node performance.

RPC Method: [eth_estimateGas](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_estimategas)

### Signature

```zig
pub fn estimateGas(
    self: *IPC,
    call_object: EthCall,
    opts: BlockNumberRequest,
) BasicRequestErrors!RPCResponse(Gwei)
```

## EstimateMaxFeePerGasManual
Estimates maxPriorityFeePerGas manually. If the node you are currently using
supports `eth_maxPriorityFeePerGas` consider using `estimateMaxFeePerGas`.

### Signature

```zig
pub fn estimateMaxFeePerGasManual(
    self: *IPC,
    base_fee_per_gas: ?Gwei,
) (BasicRequestErrors || error{ InvalidBlockNumber, UnableToFetchFeeInfoFromBlock })!Gwei
```

## EstimateMaxFeePerGas
Only use this if the node you are currently using supports `eth_maxPriorityFeePerGas`.

### Signature

```zig
pub fn estimateMaxFeePerGas(self: *IPC) BasicRequestErrors!RPCResponse(Gwei)
```

## FeeHistory
Returns historical gas information, allowing you to track trends over time.

RPC Method: [eth_feeHistory](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_feehistory)

### Signature

```zig
pub fn feeHistory(
    self: *IPC,
    blockCount: u64,
    newest_block: BlockNumberRequest,
    reward_percentil: ?[]const f64,
) BasicRequestErrors!RPCResponse(FeeHistory)
```

## GetAccounts
Returns a list of addresses owned by client.

RPC Method: [eth_accounts](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_accounts)

### Signature

```zig
pub fn getAccounts(self: *IPC) BasicRequestErrors!RPCResponse([]const Address)
```

## GetAddressBalance
Returns the balance of the account of given address.

RPC Method: [eth_getBalance](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getbalance)

### Signature

```zig
pub fn getAddressBalance(
    self: *IPC,
    opts: BalanceRequest,
) BasicRequestErrors!RPCResponse(Wei)
```

## GetAddressTransactionCount
Returns the number of transactions sent from an address.

RPC Method: [eth_getTransactionCount](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactioncount)

### Signature

```zig
pub fn getAddressTransactionCount(
    self: *IPC,
    opts: BalanceRequest,
) BasicRequestErrors!RPCResponse(u64)
```

## GetBlockByHash
Returns the number of most recent block.

RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)

### Signature

```zig
pub fn getBlockByHash(self: *IPC, opts: BlockHashRequest) (BasicRequestErrors || error{InvalidBlockHash})!RPCResponse(Block)
```

## GetBlockByHashType
Returns information about a block by hash.

Use this if the provided block type doesnt fit the expected object that it's returned from the endpoint
and you know exactly the shape that the data will be in.

RPC Method: [eth_getBlockByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbyhash)

### Signature

```zig
pub fn getBlockByHashType(
    self: *IPC,
    comptime T: type,
    opts: BlockHashRequest,
) (BasicRequestErrors || error{InvalidBlockHash})!RPCResponse(T)
```

## GetBlockByNumber
Returns information about a block by number.

RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)

### Signature

```zig
pub fn getBlockByNumber(
    self: *IPC,
    opts: BlockRequest,
) (BasicRequestErrors || error{InvalidBlockNumber})!RPCResponse(Block)
```

## GetBlockByNumberType
Returns information about a block by number.

Ask for a expected type since the way that our json parser works
on unions it will try to parse it until it can complete it for a
union member. This can be slow so if you know exactly what is the
expected type you can pass it and it will return the json parsed
response.

RPC Method: [eth_getBlockByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblockbynumber)

### Signature

```zig
pub fn getBlockByNumberType(
    self: *IPC,
    comptime T: type,
    opts: BlockRequest,
) (BasicRequestErrors || error{InvalidBlockNumber})!RPCResponse(T)
```

## GetBlockNumber
Returns the number of transactions in a block from a block matching the given block number.

RPC Method: [eth_blockNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_blocknumber)

### Signature

```zig
pub fn getBlockNumber(self: *IPC) BasicRequestErrors!RPCResponse(u64)
```

## GetBlockTransactionCountByHash
Returns the number of transactions in a block from a block matching the given block hash.

RPC Method: [eth_getBlockTransactionCountByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbyhash)

### Signature

```zig
pub fn getBlockTransactionCountByHash(
    self: *IPC,
    block_hash: Hash,
) BasicRequestErrors!RPCResponse(usize)
```

## GetBlockTransactionCountByNumber
Returns the number of transactions in a block from a block matching the given block number.

RPC Method: [eth_getBlockTransactionCountByNumber](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getblocktransactioncountbynumber)

### Signature

```zig
pub fn getBlockTransactionCountByNumber(
    self: *IPC,
    opts: BlockNumberRequest,
) BasicRequestErrors!RPCResponse(usize)
```

## GetChainId
Returns the chain ID used for signing replay-protected transactions.

RPC Method: [eth_chainId](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_chainid)

### Signature

```zig
pub fn getChainId(self: *IPC) BasicRequestErrors!RPCResponse(usize)
```

## GetClientVersion
Returns the node's client version

RPC Method: [web3_clientVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_clientversion)

### Signature

```zig
pub fn getClientVersion(self: *IPC) BasicRequestErrors!RPCResponse([]const u8)
```

## GetContractCode
Returns code at a given address.

RPC Method: [eth_getCode](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getcode)

### Signature

```zig
pub fn getContractCode(
    self: *IPC,
    opts: BalanceRequest,
) BasicRequestErrors!RPCResponse(Hex)
```

## GetCurrentRpcEvent
Get the first event of the rpc channel.

Only call this if you are sure that the channel has messages
because this will block until a message is able to be fetched.

### Signature

```zig
pub fn getCurrentRpcEvent(self: *IPC) JsonParsed(Value)
```

## GetCurrentSubscriptionEvent
Get the first event of the subscription channel.

Only call this if you are sure that the channel has messages
because this will block until a message is able to be fetched.

### Signature

```zig
pub fn getCurrentSubscriptionEvent(self: *IPC) JsonParsed(Value)
```

## GetFilterOrLogChanges
Polling method for a filter, which returns an array of logs which occurred since last poll or
Returns an array of all logs matching filter with given id depending on the selected method
https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterchanges
https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getfilterlogs

### Signature

```zig
pub fn getFilterOrLogChanges(
    self: *IPC,
    filter_id: u128,
    method: EthereumRpcMethods,
) (BasicRequestErrors || error{ InvalidFilterId, InvalidRpcMethod })!RPCResponse(Logs)
```

## GetGasPrice
Returns an estimate of the current price per gas in wei.
For example, the Besu client examines the last 100 blocks and returns the median gas unit price by default.

RPC Method: [eth_gasPrice](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gasprice)

### Signature

```zig
pub fn getGasPrice(self: *IPC) BasicRequestErrors!RPCResponse(Gwei)
```

## GetLogs
Returns an array of all logs matching a given filter object.

RPC Method: [eth_getLogs](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getlogs)

### Signature

```zig
pub fn getLogs(
    self: *IPC,
    opts: LogRequest,
    tag: ?BalanceBlockTag,
) (BasicRequestErrors || error{InvalidLogRequestParams})!RPCResponse(Logs)
```

## GetLogsSubEvent
Parses the `Value` in the sub-channel as a log event

### Signature

```zig
pub fn getLogsSubEvent(self: *IPC) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(Log))
```

## GetNewHeadsBlockSubEvent
Parses the `Value` in the sub-channel as a new heads block event

### Signature

```zig
pub fn getNewHeadsBlockSubEvent(self: *IPC) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(Block))
```

## GetNetworkListenStatus
Returns true if client is actively listening for network connections.

RPC Method: [net_listening](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_listening)

### Signature

```zig
pub fn getNetworkListenStatus(self: *IPC) BasicRequestErrors!RPCResponse(bool)
```

## GetNetworkPeerCount
Returns number of peers currently connected to the client.

RPC Method: [net_peerCount](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_peerCount)

### Signature

```zig
pub fn getNetworkPeerCount(self: *IPC) BasicRequestErrors!RPCResponse(usize)
```

## GetNetworkVersionId
Returns the current network id.

RPC Method: [net_version](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/net_version)

### Signature

```zig
pub fn getNetworkVersionId(self: *IPC) BasicRequestErrors!RPCResponse(usize)
```

## GetPendingTransactionsSubEvent
Parses the `Value` in the sub-channel as a pending transaction hash event

### Signature

```zig
pub fn getPendingTransactionsSubEvent(self: *IPC) BasicRequestErrors!RPCResponse(EthereumSubscribeResponse(Hash))
```

## GetProof
Returns the account and storage values, including the Merkle proof, of the specified account

RPC Method: [eth_getProof](https://docs.infura.io/api/networks/ethereum/json-rpc-methods/eth_getproof)

### Signature

```zig
pub fn getProof(
    self: *IPC,
    opts: ProofRequest,
    tag: ?ProofBlockTag,
) (BasicRequestErrors || error{ExpectBlockNumberOrTag})!RPCResponse(ProofResult)
```

## GetProtocolVersion
Returns the current Ethereum protocol version.

RPC Method: [eth_protocolVersion](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_protocolversion)

### Signature

```zig
pub fn getProtocolVersion(self: *IPC) BasicRequestErrors!RPCResponse(u64)
```

## GetRawTransactionByHash
Returns the raw transaction data as a hexadecimal string for a given transaction hash

RPC Method: [eth_getRawTransactionByHash](https://docs.chainstack.com/reference/base-getrawtransactionbyhash)

### Signature

```zig
pub fn getRawTransactionByHash(
    self: *IPC,
    tx_hash: Hash,
) BasicRequestErrors!RPCResponse(Hex)
```

## GetSha3Hash
Returns the Keccak256 hash of the given message.

RPC Method: [web_sha3](https://ethereum.org/en/developers/docs/apis/json-rpc#web3_sha3)

### Signature

```zig
pub fn getSha3Hash(
    self: *IPC,
    message: []const u8,
) BasicRequestErrors!RPCResponse(Hash)
```

## GetStorage
Returns the value from a storage position at a given address.

RPC Method: [eth_getStorageAt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getstorageat)

### Signature

```zig
pub fn getStorage(
    self: *IPC,
    address: Address,
    storage_key: Hash,
    opts: BlockNumberRequest,
) BasicRequestErrors!RPCResponse(Hash)
```

## GetSyncStatus
Returns null if the node has finished syncing. Otherwise it will return
the sync progress.

RPC Method: [eth_syncing](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_syncing)

### Signature

```zig
pub fn getSyncStatus(self: *IPC) ?RPCResponse(SyncProgress)
```

## GetTransactionByBlockHashAndIndex
Returns information about a transaction by block hash and transaction index position.

RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)

### Signature

```zig
pub fn getTransactionByBlockHashAndIndex(
    self: *IPC,
    block_hash: Hash,
    index: usize,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(Transaction)
```

## GetTransactionByBlockHashAndIndexType
Returns information about a transaction by block hash and transaction index position.

Use this if the provided transaction type doesnt fit the expected object that it's returned from the endpoint
and you know exactly the shape that the data will be in.

RPC Method: [eth_getTransactionByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblockhashandindex)

### Signature

```zig
pub fn getTransactionByBlockHashAndIndexType(
    self: *IPC,
    comptime T: type,
    block_hash: Hash,
    index: usize,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(T)
```

## GetTransactionByBlockNumberAndIndex
Returns information about a transaction by block number and transaction index position.

RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)

### Signature

```zig
pub fn getTransactionByBlockNumberAndIndex(
    self: *IPC,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(Transaction)
```

## GetTransactionByBlockNumberAndIndexType
Returns information about a transaction by block number and transaction index position.

Use this if the provided transaction type doesnt fit the expected object that it's returned from the endpoint
and you know exactly the shape that the data will be in.

RPC Method: [eth_getTransactionByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyblocknumberandindex)

### Signature

```zig
pub fn getTransactionByBlockNumberAndIndexType(
    self: *IPC,
    comptime T: type,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(T)
```

## GetTransactionByHash
Returns the information about a transaction requested by transaction hash.

RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)

### Signature

```zig
pub fn getTransactionByHash(self: *IPC, transaction_hash: Hash) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(Transaction)
```

## GetTransactionByHashType
Returns the information about a transaction requested by transaction hash.

Use this if the provided transaction type doesnt fit the expected object that it's returned from the endpoint
and you know exactly the shape that the data will be in.

RPC Method: [eth_getTransactionByHash](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionbyhash)

### Signature

```zig
pub fn getTransactionByHashType(
    self: *IPC,
    comptime T: type,
    transaction_hash: Hash,
) (BasicRequestErrors || error{TransactionNotFound})!RPCResponse(T)
```

## GetTransactionReceipt
Returns the receipt of a transaction by transaction hash.

RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn getTransactionReceipt(
    self: *IPC,
    transaction_hash: Hash,
) (BasicRequestErrors || error{TransactionReceiptNotFound})!RPCResponse(TransactionReceipt)
```

## GetTransactionReceiptType
Returns the receipt of a transaction by transaction hash.

Use this if the provided receipt type doesnt fit the expected object that it's returned from the endpoint
and you know exactly the shape that the data will be in.

RPC Method: [eth_getTransactionReceipt](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn getTransactionReceiptType(
    self: *IPC,
    comptime T: type,
    transaction_hash: Hash,
) (BasicRequestErrors || error{TransactionReceiptNotFound})!RPCResponse(TransactionReceipt)
```

## GetTxPoolContent
The content inspection property can be queried to list the exact details of all the transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.

The result is an object with two fields pending and queued.
Each of these fields are associative arrays, in which each entry maps an origin-address to a batch of scheduled transactions.
These batches themselves are maps associating nonces with actual transactions.

RPC Method: [txpool_content](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolContent(self: *IPC) BasicRequestErrors!RPCResponse(TxPoolContent)
```

## GetTxPoolContentFrom
Retrieves the transactions contained within the txpool,
returning pending as well as queued transactions of this address, grouped by nonce

RPC Method: [txpool_contentFrom](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolContentFrom(
    self: *IPC,
    from: Address,
) BasicRequestErrors!RPCResponse([]const PoolTransactionByNonce)
```

## GetTxPoolInspectStatus
The inspect inspection property can be queried to list a textual summary of all the transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.
This is a method specifically tailored to developers to quickly see the transactions in the pool and find any potential issues.

RPC Method: [txpool_inspect](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolInspectStatus(self: *IPC) BasicRequestErrors!RPCResponse(TxPoolInspect)
```

## GetTxPoolStatus
The status inspection property can be queried for the number of transactions currently pending for inclusion in the next block(s),
as well as the ones that are being scheduled for future execution only.

RPC Method: [txpool_status](https://geth.ethereum.org/docs/interacting-with-geth/rpc/ns-txpool)

### Signature

```zig
pub fn getTxPoolStatus(self: *IPC) BasicRequestErrors!RPCResponse(TxPoolStatus)
```

## GetUncleByBlockHashAndIndex
Returns information about a uncle of a block by hash and uncle index position.

RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)

### Signature

```zig
pub fn getUncleByBlockHashAndIndex(
    self: *IPC,
    block_hash: Hash,
    index: usize,
) (BasicRequestErrors || error{InvalidBlockHashOrIndex})!RPCResponse(Block)
```

## GetUncleByBlockHashAndIndexType
Returns information about a uncle of a block by hash and uncle index position.

Use this if the provided block type doesnt fit the expected object that it's returned from the endpoint
and you know exactly the shape that the data will be in.

RPC Method: [eth_getUncleByBlockHashAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblockhashandindex)

### Signature

```zig
pub fn getUncleByBlockHashAndIndexType(
    self: *IPC,
    comptime T: type,
    block_hash: Hash,
    index: usize,
) (BasicRequestErrors || error{InvalidBlockHashOrIndex})!RPCResponse(T)
```

## GetUncleByBlockNumberAndIndex
Returns information about a uncle of a block by number and uncle index position.

RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)

### Signature

```zig
pub fn getUncleByBlockNumberAndIndex(
    self: *IPC,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRequestErrors || error{InvalidBlockNumberOrIndex})!RPCResponse(Block)
```

## GetUncleByBlockNumberAndIndexType
Returns information about a uncle of a block by number and uncle index position.

Use this if the provided block type doesnt fit the expected object that it's returned from the endpoint
and you know exactly the shape that the data will be in.

RPC Method: [eth_getUncleByBlockNumberAndIndex](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclebyblocknumberandindex)

### Signature

```zig
pub fn getUncleByBlockNumberAndIndexType(
    self: *IPC,
    comptime T: type,
    opts: BlockNumberRequest,
    index: usize,
) (BasicRequestErrors || error{InvalidBlockNumberOrIndex})!RPCResponse(T)
```

## GetUncleCountByBlockHash
Returns the number of uncles in a block from a block matching the given block hash.

RPC Method: [`eth_getUncleCountByBlockHash`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblockhash)

### Signature

```zig
pub fn getUncleCountByBlockHash(
    self: *IPC,
    block_hash: Hash,
) BasicRequestErrors!RPCResponse(usize)
```

## GetUncleCountByBlockNumber
Returns the number of uncles in a block from a block matching the given block number.

RPC Method: [`eth_getUncleCountByBlockNumber`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_getunclecountbyblocknumber)

### Signature

```zig
pub fn getUncleCountByBlockNumber(
    self: *IPC,
    opts: BlockNumberRequest,
) BasicRequestErrors!RPCResponse(usize)
```

## Multicall3
Runs the selected multicall3 contracts.
This enables to read from multiple contract by a single `eth_call`.
Uses the contracts created [here](https://www.multicall3.com/)

To learn more about the multicall contract please go [here](https://github.com/mds1/multicall)

You will need to decoded each of the `Result`.

**Example:**
```zig
 const supply: Function = .{
      .type = .function,
      .name = "totalSupply",
      .stateMutability = .view,
      .inputs = &.{},
      .outputs = &.{.{ .type = .{ .uint = 256 }, .name = "supply" }},
  };

  const balance: Function = .{
      .type = .function,
      .name = "balanceOf",
      .stateMutability = .view,
      .inputs = &.{.{ .type = .{ .address = {} }, .name = "balanceOf" }},
      .outputs = &.{.{ .type = .{ .uint = 256 }, .name = "supply" }},
  };

  const a: []const MulticallTargets = &.{
      .{ .function = supply, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
      .{ .function = balance, .target_address = comptime utils.addressToBytes("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48") catch unreachable },
  };

  const res = try client.multicall3(a, .{ {}, .{try utils.addressToBytes("0xFded38DF0180039867E54EBdec2012D534862cE3")} }, true);
  defer res.deinit();
```

### Signature

```zig
pub fn multicall3(
    self: *IPC,
    comptime targets: []const MulticallTargets,
    function_arguments: MulticallArguments(targets),
    allow_failure: bool,
) Multicall(.ipc).Error!AbiDecoded([]const Result)
```

## NewBlockFilter
Creates a filter in the node, to notify when a new block arrives.
To check if the state has changed, call `getFilterOrLogChanges`.

RPC Method: [`eth_newBlockFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newblockfilter)

### Signature

```zig
pub fn newBlockFilter(self: *IPC) BasicRequestErrors!RPCResponse(u128)
```

## NewLogFilter
Creates a filter object, based on filter options, to notify when the state changes (logs).
To check if the state has changed, call `getFilterOrLogChanges`.

RPC Method: [`eth_newFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newfilter)

### Signature

```zig
pub fn newLogFilter(self: *IPC, opts: LogRequest, tag: ?BalanceBlockTag) BasicRequestErrors!RPCResponse(u128)
```

## NewPendingTransactionFilter
Creates a filter in the node, to notify when new pending transactions arrive.
To check if the state has changed, call `getFilterOrLogChanges`.

RPC Method: [`eth_newPendingTransactionFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_newpendingtransactionfilter)

### Signature

```zig
pub fn newPendingTransactionFilter(self: *IPC) BasicRequestErrors!RPCResponse(u128)
```

## ReadLoop
Creates a read loop to read the socket messages.
If a message is too long it will double the buffer size to read the message.

### Signature

```zig
pub fn readLoop(self: *IPC) ReadLoopErrors!void
```

## ReadLoopOwnedThread
Function prepared to start the read loop in a seperate thread.

### Signature

```zig
pub fn readLoopOwnedThread(self: *IPC) void
```

## ParseSubscriptionEvent
Parses a subscription event `Value` into `T`.
Usefull for events that currently zabi doesn't have custom support.

### Signature

```zig
pub fn parseSubscriptionEvent(
    self: *IPC,
    comptime T: type,
) ParseFromValueError!RPCResponse(EthereumSubscribeResponse(T))
```

## SendEthCall
Executes a new message call immediately without creating a transaction on the block chain.
Often used for executing read-only smart contract functions,
for example the balanceOf for an ERC-20 contract.

Call object must be prefilled before hand. Including the data field.
This will just make the request to the network.

RPC Method: [`eth_call`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_call)

### Signature

```zig
pub fn sendEthCall(
    self: *IPC,
    call_object: EthCall,
    opts: BlockNumberRequest,
) BasicRequestErrors!RPCResponse(Hex)
```

## SendRawTransaction
Creates new message call transaction or a contract creation for signed transactions.
Transaction must be serialized and signed before hand.

RPC Method: [`eth_sendRawTransaction`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_sendrawtransaction)

### Signature

```zig
pub fn sendRawTransaction(
    self: *IPC,
    serialized_tx: Hex,
) BasicRequestErrors!RPCResponse(Hash)
```

## SendRpcRequest
Writes message to websocket server and parses the reponse from it.
This blocks until it gets the response back from the server.

### Signature

```zig
pub fn sendRpcRequest(
    self: *IPC,
    comptime T: type,
    message: []u8,
) SendRpcRequestErrors!RPCResponse(T)
```

## UninstallFilter
Uninstalls a filter with given id. Should always be called when watch is no longer needed.
Additionally Filters timeout when they aren't requested with `getFilterOrLogChanges` for a period of time.

RPC Method: [`eth_uninstallFilter`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_uninstallfilter)

### Signature

```zig
pub fn uninstallFilter(
    self: *IPC,
    id: usize,
) BasicRequestErrors!RPCResponse(bool)
```

## Unsubscribe
Unsubscribe from different Ethereum event types with a regular RPC call
with eth_unsubscribe as the method and the subscriptionId as the first parameter.

RPC Method: [`eth_unsubscribe`](https://docs.alchemy.com/reference/eth-unsubscribe)

### Signature

```zig
pub fn unsubscribe(
    self: *IPC,
    sub_id: u128,
) BasicRequestErrors!RPCResponse(bool)
```

## WatchNewBlocks
Emits new blocks that are added to the blockchain.

RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/eth-subscribe)

### Signature

```zig
pub fn watchNewBlocks(self: *IPC) BasicRequestErrors!RPCResponse(u128)
```

## WatchLogs
Emits logs attached to a new block that match certain topic filters and address.

RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/logs)

### Signature

```zig
pub fn watchLogs(
    self: *IPC,
    opts: WatchLogsRequest,
) BasicRequestErrors!RPCResponse(u128)
```

## WatchTransactions
Emits transaction hashes that are sent to the network and marked as "pending".

RPC Method: [`eth_subscribe`](https://docs.alchemy.com/reference/newpendingtransactions)

### Signature

```zig
pub fn watchTransactions(self: *IPC) BasicRequestErrors!RPCResponse(u128)
```

## WatchWebsocketEvent
Creates a new subscription for desired events. Sends data as soon as it occurs

This expects the method to be a valid websocket subscription method.
Since we have no way of knowing all possible or custom RPC methods that nodes can provide.

Returns the subscription Id.

### Signature

```zig
pub fn watchWebsocketEvent(
    self: *IPC,
    method: []const u8,
) BasicRequestErrors!RPCResponse(u128)
```

## WaitForTransactionReceipt
Waits until a transaction gets mined and the receipt can be grabbed.
This is retry based on either the amount of `confirmations` given.

If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.

RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn waitForTransactionReceipt(self: *IPC, tx_hash: Hash, confirmations: u8) (BasicRequestErrors || ParseFromValueError || error{
    TransactionNotFound,
    TransactionReceiptNotFound,
    FailedToGetReceipt,
    FailedToUnsubscribe,
    InvalidBlockNumber,
})!RPCResponse(TransactionReceipt)
```

## WaitForTransactionReceiptType
Waits until a transaction gets mined and the receipt can be grabbed.
This is retry based on either the amount of `confirmations` given.

If 0 confirmations are given the transaction receipt can be null in case
the transaction has not been mined yet. It's recommened to have atleast one confirmation
because some nodes might be slower to sync.

Use this if the provided block type doesnt fit the expected object that it's returned from the endpoint
and you know exactly the shape that the data will be in.

RPC Method: [`eth_getTransactionReceipt`](https://ethereum.org/en/developers/docs/apis/json-rpc#eth_gettransactionreceipt)

### Signature

```zig
pub fn waitForTransactionReceiptType(self: *IPC, comptime T: type, tx_hash: Hash, confirmations: u8) (BasicRequestErrors || ParseFromValueError || error{
    TransactionReceiptNotFound,
    TransactionNotFound,
    FailedToGetReceipt,
    FailedToUnsubscribe,
    InvalidBlockNumber,
})!RPCResponse(T)
```

## WriteSocketMessage
Write messages to the websocket server.

### Signature

```zig
pub fn writeSocketMessage(
    self: *IPC,
    data: []u8,
) IpcReader.WriteError!void
```

