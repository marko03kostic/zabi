## PrepareErrors

Set of possible errors when running `allocPrepare`

```zig
Allocator.Error || error{NoSpaceLeft}
```

## AbiParameter

Struct to represent solidity Abi Paramters

### Properties

```zig
struct {
  name: []const u8
  type: ParamType
  internalType: ?[]const u8 = null
  components: ?[]const AbiParameter = null
}
```

### Encode
Encode the paramters based on the values provided and `self`.
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values

Caller owns the memory.

Consider using `encodeAbiParametersComptime` if the parameter is
comptime know and you want better typesafety from the compiler

### Signature

```zig
pub fn encode(
    self: @This(),
    allocator: Allocator,
    values: anytype,
) EncodeErrors![]u8
```

### Decode
Decode the paramters based on self.
Runtime reflection based on the provided values will occur to determine
what is the correct method to use to encode the values

Caller owns the memory only if the param type is a dynamic array

Consider using `decodeAbiParameters` if the parameter is
comptime know and you want better typesafety from the compiler

### Signature

```zig
pub fn decode(
    self: @This(),
    comptime T: type,
    allocator: Allocator,
    encoded: []const u8,
    options: DecodeOptions,
) DecoderErrors!AbiDecoded(T)
```

### Prepare
Format the struct into a human readable string.
Intended to use for hashing purposes.

### Signature

```zig
pub fn prepare(
    self: @This(),
    writer: anytype,
) PrepareErrors!void
```

## AbiEventParameter

Struct to represent solidity Abi Event Paramters

### Properties

```zig
struct {
  name: []const u8
  type: ParamType
  internalType: ?[]const u8 = null
  indexed: bool
  components: ?[]const AbiParameter = null
}
```

### Prepare
Format the struct into a human readable string.
Intended to use for hashing purposes.

### Signature

```zig
pub fn prepare(
    self: @This(),
    writer: anytype,
) PrepareErrors!void
```

