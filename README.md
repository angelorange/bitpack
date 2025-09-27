# Bitpack

Bitpacker for rows/events with small fields (bools, short ints, fixed bytes).
Converts `[map()]` ↔ compact binary according to a spec (schema) of bits per field.

## Why use it

- **Reduces I/O/bandwidth**: much smaller than JSON/CSV before the DB
- **Staging "raw" barato**: for reprocessing/auditing
- **Determinístico e rápido**: use `<< >>`, iodata, padding previsível

## When to use

- **Ingest/ETL**: Kafka/S3/HTTP before materializing in the DB
- **Telemetry/IoT**: events with many flags/counts
- **Games/bitmaps**: flags in mass
- **Caches compactos**: many booleans/ints

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

# Exemplo de dados
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

## Installation

```elixir
def deps do
  [
    {:bitpack, "~> 0.1.0"}
  ]
end
```

