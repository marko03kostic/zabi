## OpMainNetContracts

L1 and L2 optimism contracts

### Properties

```zig
struct {
  /// L2 specific.
  gasPriceOracle: Address = utils.addressToBytes("0x420000000000000000000000000000000000000F") catch unreachable
  /// L2 specific.
  l1Block: Address = utils.addressToBytes("0x4200000000000000000000000000000000000015") catch unreachable
  /// L2 specific.
  l2CrossDomainMessenger: Address = utils.addressToBytes("0x4200000000000000000000000000000000000007") catch unreachable
  /// L2 specific.
  l2Erc721Bridge: Address = utils.addressToBytes("0x4200000000000000000000000000000000000014") catch unreachable
  /// L2 specific.
  l2StandartBridge: Address = utils.addressToBytes("0x4200000000000000000000000000000000000010") catch unreachable
  /// L2 specific.
  l2ToL1MessagePasser: Address = utils.addressToBytes("0x4200000000000000000000000000000000000016") catch unreachable
  /// L1 specific. L2OutputOracleProxy contract.
  l2OutputOracle: Address = utils.addressToBytes("0xdfe97868233d1aa22e815a266982f2cf17685a27") catch unreachable
  /// L1 specific. OptimismPortalProxy contract.
  portalAddress: Address = utils.addressToBytes("0xbEb5Fc579115071764c7423A4f12eDde41f106Ed") catch unreachable
  /// L1 specific. DisputeGameFactoryProxy contract. Make sure that the chain has fault proofs enabled.
  disputeGameFactory: Address = utils.addressToBytes("0xe5965Ab5962eDc7477C8520243A95517CD252fA9") catch unreachable
  /// L1 specific. L1 bridge contract.
  l1StandardBridge: Address = utils.addressToBytes("0x99C9fc46f92E8a1c0deC1b1747d010903E884bE1") catch unreachable
}
```

## EnsContracts

ENS Contracts

### Properties

```zig
struct {
  ensUniversalResolver: Address = utils.addressToBytes("0x8cab227b1162f03b8338331adaad7aadc83b895e") catch unreachable
}
```

## Endpoint

Possible endpoint locations.
For http/s and ws/s use `Uri` and for IPC use `path`.

If a uri connection is set for the IPC client it will create and error and vice versa.

```zig
union(enum) {
    /// If the connections is url based use this
    uri: Uri,
    /// If the connection is IPC socket based use this.
    path: []const u8,
}
```

## NetworkConfig

The possible configuration of a network.

The only required field is the `endpoint` so that the client's
know where they can connect to.

All other fields have default values and adjust them as you need.

### Properties

```zig
struct {
  /// The base fee multiplier used to estimate the gas fees in a transaction
  base_fee_multiplier: f64 = 1.2
  /// The client chainId.
  chain_id: Chains = .ethereum
  /// Ens contract on configured chain.
  ens_contracts: ?EnsContracts = null
  /// The multicall3 contract address.
  multicall_contract: Address = utils.addressToBytes("0xcA11bde05977b3631167028862bE2a173976CA11") catch unreachable
  /// L1 and L2 op_stack contracts
  op_stack_contracts: ?OpMainNetContracts = null
  /// The interval to retry the request. This will get multiplied in ns_per_ms.
  pooling_interval: u64 = 2_000
  /// Retry count for failed requests.
  retries: u8 = 5
  /// Uri for the client to connect to
  endpoint: Endpoint
}
```

### GetUriSchema
Gets the uri schema. Returns null if the endpoint
is configured to be `path`.

### Signature

```zig
pub fn getUriSchema(self: NetworkConfig) ?[]const u8
```

### GetNetworkUri
Gets the uri struct if possible. Return null if the endpoint
is configured to be `path`.

### Signature

```zig
pub fn getNetworkUri(self: NetworkConfig) ?Uri
```

## arbitrum

The chain configuration for arbitrum mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://arb1.arbitrum.io/rpc") catch unreachable,
    },
    .chain_id = .arbitrum,
}
```

## arbitrum_nova

The chain configuration for arbitrum_nova mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://nova.arbitrum.io/rpc") catch unreachable,
    },
    .chain_id = .arbitrum_nova,
}
```

## avalanche

The chain configuration for avalanche c-chain mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://api.avax.network/ext/bc/C/rpc") catch unreachable,
    },
    .chain_id = .avalanche,
}
```

## base

The chain configuration for base mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://mainnet.base.org") catch unreachable,
    },
    .chain_id = .base,
    .op_stack_contracts = .{
        .portalAddress = utils.addressToBytes("0x56315b90c40730925ec5485cf004d835058518A0") catch unreachable,
        .l2OutputOracle = utils.addressToBytes("0x49048044D57e1C92A77f79988d21Fa8fAF74E97e") catch unreachable,
        .l1StandardBridge = utils.addressToBytes("0x3154Cf16ccdb4C6d922629664174b904d80F2C35") catch unreachable,
    },
}
```

## boba

The chain configuration for boba mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://mainnet.boba.network") catch unreachable,
    },
    .chain_id = .boba,
}
```

## bnb

The chain configuration for bsc mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://rpc.ankr.com/bsc") catch unreachable,
    },
    .chain_id = .bnb,
}
```

## celo

The chain configuration for celo mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://forno.celo.org") catch unreachable,
    },
    .chain_id = .celo,
}
```

## cronos

The chain configuration for cronos mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://evm.cronos.org") catch unreachable,
    },
    .chain_id = .cronos,
}
```

## ethereum_mainet

The chain configuration for ethereum mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://cloudflare-eth.com") catch unreachable,
    },
    .ens_contracts = .{},
}
```

## fantom

The chain configuration for fantom mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://rpc.ankr.com/fantom") catch unreachable,
    },
    .chain_id = .fantom,
}
```

## gnosis

The chain configuration for gnosis mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://rpc.gnosischain.com") catch unreachable,
    },
    .chain_id = .gnosis,
}
```

## optimism

The chain configuration for optimism mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://mainnet.optimism.io") catch unreachable,
    },
    .chain_id = .op_mainnet,
    .op_stack_contracts = .{},
}
```

## optimism_sepolia

The chain configuration for optimism sepolia testnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://sepolia.optimism.io") catch unreachable,
    },
    .chain_id = .op_sepolia,
    .op_stack_contracts = .{
        .disputeGameFactory = utils.addressToBytes("0x05F9613aDB30026FFd634f38e5C4dFd30a197Fa1") catch unreachable,
        .portalAddress = utils.addressToBytes("0x16Fc5058F25648194471939df75CF27A2fdC48BC") catch unreachable,
        .l2OutputOracle = utils.addressToBytes("0x90E9c4f8a994a250F6aEfd61CAFb4F2e895D458F") catch unreachable,
        .l1StandardBridge = utils.addressToBytes("0xFBb0621E0B23b5478B630BD55a5f21f67730B0F1") catch unreachable,
    },
}
```

## polygon

The chain configuration for polygon mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://polygon-rpc.com") catch unreachable,
    },
    .chain_id = .polygon,
}
```

## sepolia_mainet_testnet

The chain configuration for sepolia testnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://rpc.sepolia.org") catch unreachable,
    },
    .chain_id = .sepolia,
    .ens_contracts = .{
        .ensUniversalResolver = utils.addressToBytes("0xc8Af999e38273D658BE1b921b88A9Ddf005769cC") catch unreachable,
    },
}
```

## zora

The chain configuration for zora mainnet.

```zig
.{
    .endpoint = .{
        .uri = Uri.parse("https://rpc.zora.energy") catch unreachable,
    },
    .chain_id = .zora,
    .op_stack_contracts = .{
        .l1StandardBridge = utils.addressToBytes("0x3e2Ea9B92B7E48A52296fD261dc26fd995284631") catch unreachable,
        .portalAddress = utils.addressToBytes("0x1a0ad011913A150f69f6A19DF447A0CfD9551054") catch unreachable,
        .l2OutputOracle = utils.addressToBytes("0x9E6204F750cD866b299594e2aC9eA824E2e5f95c") catch unreachable,
    },
}
```

