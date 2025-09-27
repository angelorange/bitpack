# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-27

### Added

#### Bitpack Core
- Bit-level packer/unpacker for rows with small fields
- Support for field types: `{:u, n}`, `{:i, n}`, `{:bool}`, `{:bytes, k}`
- Core API: `pack/2`, `unpack/2`, `pack_safe/2`, `unpack_safe/2`
- Utility functions: `validate_spec!/1`, `row_size/1`, `hexdump/1`, `inspect_row/2`
- CLI tool for NDJSON conversion
- Comprehensive test suite with property-based testing
- Performance benchmarks showing 86-92% compression vs JSON

#### BPX (Binary Payload eXchange)
- Generic compression envelope with automatic algorithm selection
- Support for multiple compression algorithms: `:none`, `:deflate`, `:brotli`, `:zstd`
- Self-describing format with magic bytes, version, algorithm info, and CRC32 checksum
- API: `wrap_auto/2`, `unwrap/1`, `inspect_envelope/1`
- CLI tool for file compression/decompression
- Data integrity verification with CRC32
- Configurable compression options (algorithm preference, minimum gain threshold)

#### Integration & Documentation
- Integration examples showing combined Bitpack + BPX usage
- Complete README with usage examples and benchmarks
- CI/CD pipeline with GitHub Actions
- Comprehensive documentation for both libraries

### Performance
- Bitpack: 86-92% smaller than JSON, 1.2x to 61x faster encoding/decoding
- BPX: Additional compression with integrity guarantees
- Combined: Up to 86%+ total compression vs JSON with data integrity

[0.1.0]: https://github.com/angelorange/bitpack/releases/tag/v0.1.0
