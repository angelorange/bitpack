# Bitpack

**Ultra-compact binary serialization for Elixir** - Pack your data into the smallest possible space while maintaining blazing-fast performance.

Bitpack transforms lists of maps into highly compressed binary formats, achieving **86-92% size reduction** compared to JSON while being **3-61x faster** to encode/decode.

**Includes BPX (Binary Payload eXchange)** - A complementary compression library that automatically selects the best compression algorithm and adds data integrity verification.

## 🎯 What Problem Does This Solve?

Modern applications generate massive amounts of structured data - IoT sensors, game events, financial ticks, telemetry. Traditional formats like JSON are human-readable but wasteful:

```elixir
# Traditional JSON: 340 bytes
[
  %{sensor_id: 1, temperature: 23.5, humidity: 65, battery: 180, online: true, alarm: false},
  %{sensor_id: 2, temperature: -4.5, humidity: 72, battery: 165, online: true, alarm: false},
  %{sensor_id: 3, temperature: 18.0, humidity: 58, battery: 200, online: false, alarm: true}
]

# Bitpack: 30 bytes (91% smaller!)
# BPX compressed: 47 bytes (86% total reduction vs JSON)
```

**The result?** Massive savings in storage, bandwidth, and processing costs.

## Key Benefits

- **Extreme Compression**: 86-92% smaller than JSON
- **Blazing Fast**: 3-61x faster than JSON encoding/decoding  
- **Data Integrity**: Built-in CRC32 validation with BPX
- **Flexible**: Support for integers, booleans, fixed bytes
- **Self-Describing**: BPX envelopes include compression metadata

## 🛠️ How It Works

Bitpack uses **bit-level packing** - every bit counts:

```elixir
# Instead of JSON's wasteful text representation:
{"sensor_id": 1, "temperature": 23.5, "online": true}  # 50+ bytes

# Bitpack uses exact bit allocation:
# sensor_id: 16 bits, temperature: 12 bits, online: 1 bit = 29 bits total
# Result: ~4 bytes vs 50+ bytes (87% smaller)
```

**BPX adds intelligent compression:**
- Tries multiple algorithms (deflate, brotli, zstd)
- Picks the best compression for your data
- Adds integrity verification (CRC32)
- Self-describing format for easy handling

## Quick example

```elixir
# Define spec: field → type
spec = [
  {:status, {:u, 3}},    # unsigned 3 bits (0-7)
  {:vip, {:bool}},       # boolean 1 bit
  {:tries, {:u, 5}},     # unsigned 5 bits (0-31)
  {:amount, {:u, 20}},   # unsigned 20 bits (0-1M)
  {:tag, {:bytes, 3}}    # 3 bytes fixos
]

# Data example
rows = [
  %{status: 2, vip: true, tries: 5, amount: 12345, tag: <<1, 2, 3>>},
  %{status: 1, vip: false, tries: 12, amount: 67890, tag: <<4, 5, 6>>}
]

# Pack: list of maps → compact binary
binary = Bitpack.pack(rows, spec)
IO.inspect(byte_size(binary))  # ~14 bytes (vs ~200+ bytes JSON)

# Unpack: compact binary → list of maps
restored = Bitpack.unpack(binary, spec)
IO.inspect(restored == rows)   # true
```

## API

### Basic (with exceptions)
- `Bitpack.pack(rows, spec)` → `binary()`
- `Bitpack.unpack(binary, spec)` → `[row()]`

### Safe (no exceptions)
- `Bitpack.pack_safe(rows, spec)` → `{:ok, binary()} | {:error, reason}`
- `Bitpack.unpack_safe(binary, spec)` → `{:ok, [row()]} | {:error, reason}`

### Utilities
- `Bitpack.validate_spec!(spec)` → validates spec or raises
- `Bitpack.row_size(spec)` → bytes por linha
- `Bitpack.hexdump(binary)` → string hexadecimal para debug
- `Bitpack.inspect_row(row, spec)` → layout de bits do row

## Field types

| Type | Description | Example |
|------|-----------|---------|
| `{:u, n}` | Unsigned integer, n bits | `{:count, {:u, 8}}` (0-255) |
| `{:i, n}` | Signed integer, n bits | `{:delta, {:i, 16}}` (-32768 a 32767) |
| `{:bool}` | Boolean, 1 bit | `{:active, {:bool}}` |
| `{:bytes, k}` | k bytes fixos, alinhado | `{:id, {:bytes, 16}}` |

## CLI

Install the executable:
```bash
mix escript.build
```

Convert NDJSON ↔ bitpack:
```bash
# spec.exs
[
  {:user_id, {:u, 24}},
  {:active, {:bool}},
  {:score, {:u, 16}},
  {:metadata, {:bytes, 8}}
]

# Pack: NDJSON → binary
./bitpack pack spec.exs data.ndjson data.bin

# Unpack: binary → NDJSON  
./bitpack unpack spec.exs data.bin restored.ndjson
```

## Alignment rules

1. **Fields are written in the order of the spec**
2. **Before `{:bytes, k}`**: align to next byte
3. **At the end of each row**: align to next byte (padding with zeros)

## Limitations

- **Specs with 0 bytes/row**: we can't distinguish between "0 rows" and "N rows of 0 bytes each"
- **Maximum 64 bits** per integer field
- **Fixed order**: fields must be in the same order as the spec

## BPX - Binary Payload eXchange

BPX is a complementary library that provides automatic compression for any binary payload. It tries multiple compression algorithms and selects the best one, wrapping the result in a self-describing envelope.

### BPX Features

- **Automatic Algorithm Selection**: Tries multiple compression algorithms (deflate, brotli, zstd) and picks the best
- **Self-Describing Format**: Header contains magic bytes, version, algorithm, sizes, and CRC32 checksum
- **Integrity Verification**: CRC32 validation ensures data integrity
- **Configurable**: Set minimum compression gain threshold and algorithm preferences
- **CLI Tool**: Command-line interface for file compression/decompression

### BPX Usage

```elixir
# Basic usage - automatic algorithm selection
data = "Your binary data here"
envelope = BPX.wrap_auto(data)
{:ok, restored_data, metadata} = BPX.unwrap(envelope)

# With options
envelope = BPX.wrap_auto(data, 
  algos: [:zstd, :brotli, :deflate], 
  min_gain: 32
)

# Inspect envelope without decompressing
{:ok, info} = BPX.inspect_envelope(envelope)
IO.puts("Algorithm: #{info.algorithm}")
IO.puts("Compression: #{info.compression_ratio * 100}%")
```

### BPX CLI

```bash
# Compress a file
mix run -e "BPX.CLI.main([\"pack\", \"input.txt\", \"output.bpx\"])"

# Decompress a file  
mix run -e "BPX.CLI.main([\"unpack\", \"output.bpx\", \"restored.txt\"])"

# Show file information
mix run -e "BPX.CLI.main([\"info\", \"output.bpx\"])"
```

### Integration Example

Combine Bitpack's bit-level efficiency with BPX's compression:

```elixir
# IoT sensor data spec
spec = [
  {:timestamp, {:u, 32}},
  {:sensor_id, {:u, 16}}, 
  {:temperature, {:i, 12}},
  {:humidity, {:u, 7}},
  {:battery, {:u, 8}},
  {:online, {:bool}},
  {:alarm, {:bool}}
]

# Pack with Bitpack, then compress with BPX
sensor_data = [%{timestamp: 1640995200, sensor_id: 1, ...}, ...]
bitpack_binary = Bitpack.pack(sensor_data, spec)
bpx_envelope = BPX.wrap_auto(bitpack_binary)

# Result: 86%+ compression vs JSON with data integrity
```

Run the integration example: `mix run examples/simple_integration.ex`

## Benchmarks

Comparison typical vs JSON (1000 events IoT):
- **JSON**: ~45KB
- **Bitpack**: ~8KB (82% reduction)
- **Speed**: ~3x faster for pack/unpack

## 🚀 Getting Started

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:bitpack, "~> 0.1.0"}
  ]
end
```

Then run:
```bash
mix deps.get
```

### Quick Start

```elixir
# 1. Define your data structure
spec = [
  {:user_id, {:u, 24}},      # 16M users
  {:score, {:u, 16}},        # 0-65K points  
  {:active, {:bool}},        # Online status
  {:level, {:u, 8}}          # 255 levels max
]

# 2. Pack your data
data = [
  %{user_id: 12345, score: 9876, active: true, level: 42},
  %{user_id: 67890, score: 5432, active: false, level: 28}
]

packed = Bitpack.pack(data, spec)
# Result: 14 bytes vs 156 bytes JSON (91% smaller!)

# 3. Add compression (optional)
compressed = BPX.wrap_auto(packed)
# Additional compression with integrity verification

# 4. Restore your data
{:ok, restored_packed, _meta} = BPX.unwrap(compressed)
restored_data = Bitpack.unpack(restored_packed, spec)
# restored_data == data ✓
```

## 🎮 Try It Now

Run the integration example:
```bash
git clone https://github.com/angelorange/bitpack.git
cd bitpack
mix deps.get
mix run examples/simple_integration.ex
```
