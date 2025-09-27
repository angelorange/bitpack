defmodule BPX do
  @moduledoc """
  BPX (Binary Payload eXchange) - Generic envelope with automatic compression.

  Try multiple compression algorithms and choose the smallest result,
  packing with header that includes magic, version, algorithm, sizes and CRC32.

  ## Header Format

  ```
  "BPX" | VERSION(u8) | ALG(u8) | ORIG_LEN(u32) | COMP_LEN(u32) | CRC32(u32) | PAYLOAD...
  ```

  - Magic: "BPX" (3 bytes)
  - Version: 0x01 (1 byte)
  - Algorithm: 0=none, 1=deflate, 2=brotli, 3=zstd (1 byte)
  - Original length: original size in bytes (4 bytes, big-endian)
  - Compressed length: compressed size in bytes (4 bytes, big-endian)
  - CRC32: checksum of original payload (4 bytes, big-endian)
  - Payload: data (compressed or original)

  ## Examples

      # Compress automatically
      envelope = BPX.wrap_auto(data, algos: [:zstd, :deflate], min_gain: 16)

      # Uncompress
      {:ok, original, meta} = BPX.unwrap(envelope)
  """

  @magic "BPX"
  @version 1

  # Supported algorithms
  @algorithms %{
    0 => :none,
    1 => :deflate,
    2 => :brotli,
    3 => :zstd
  }

  @algorithm_ids Map.new(@algorithms, fn {id, alg} -> {alg, id} end)

  @type algorithm :: :none | :deflate | :brotli | :zstd
  @type wrap_options :: [
          algos: [algorithm()],
          min_gain: non_neg_integer()
        ]
  @type meta :: %{
          algorithm: algorithm(),
          original_size: non_neg_integer(),
          compressed_size: non_neg_integer(),
          compression_ratio: float()
        }

  @doc """
  Compress data automatically.

  Tests each specified algorithm and chooses the smallest result.
  Only uses compression if it saves at least `min_gain` bytes.

  ## Options

  - `algos`: list of algorithms to test (default: [:deflate])
  - `min_gain`: minimum gain in bytes to use compression (default: 16)

  ## Examples

      # Uses deflate if it saves at least 16 bytes
      envelope = BPX.wrap_auto(data)

      # Tests multiple algorithms
      envelope = BPX.wrap_auto(data, algos: [:zstd, :brotli, :deflate], min_gain: 32)
  """
  @spec wrap_auto(binary(), wrap_options()) :: binary()
  def wrap_auto(data, opts \\ []) when is_binary(data) do
    algos = Keyword.get(opts, :algos, [:deflate])
    min_gain = Keyword.get(opts, :min_gain, 16)

    original_size = byte_size(data)
    crc32 = :erlang.crc32(data)

    # Tests all available algorithms
    candidates =
      algos
      |> Enum.filter(&algorithm_available?/1)
      |> Enum.map(fn alg ->
        case compress(data, alg) do
          {:ok, compressed} -> {alg, compressed, byte_size(compressed)}
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Adds "no compression" option
    candidates = [{:none, data, original_size} | candidates]

    # Chooses the smallest result that meets the min_gain
    {best_alg, best_data, best_size} =
      candidates
      |> Enum.min_by(fn {_alg, _data, size} -> size end)

    # Uses compression only if it saves at least min_gain bytes
    {final_alg, final_data, final_size} =
      if best_alg != :none and original_size - best_size >= min_gain do
        {best_alg, best_data, best_size}
      else
        {:none, data, original_size}
      end

    # Builds the envelope
    build_envelope(final_alg, original_size, final_size, crc32, final_data)
  end

  @doc """
  Unpacks data from BPX envelope.

  Validates magic, version, CRC32 and sizes before decompressing.

  ## Return

  - `{:ok, data, meta}`: success with original data and metadata
  - `{:error, reason}`: error in validation or decompression

  ## Examples

      {:ok, data, meta} = BPX.unwrap(envelope)
      IO.inspect(meta.algorithm)        # :deflate
      IO.inspect(meta.compression_ratio) # 0.75 (25% of compression)
  """
  @spec unwrap(binary()) :: {:ok, binary(), meta()} | {:error, term()}
  def unwrap(envelope) when is_binary(envelope) do
    with {:ok, header, payload} <- parse_header(envelope),
         {:ok, data} <- decompress(payload, header.algorithm),
         :ok <- validate_data(data, header) do
      compression_ratio =
        if header.original_size == 0 do
          0.0
        else
          1.0 - header.compressed_size / header.original_size
        end

      meta = %{
        algorithm: header.algorithm,
        original_size: header.original_size,
        compressed_size: header.compressed_size,
        compression_ratio: compression_ratio
      }

      {:ok, data, meta}
    end
  end

  # Builds the envelope with header + payload
  defp build_envelope(algorithm, orig_size, comp_size, crc32, payload) do
    alg_id = Map.fetch!(@algorithm_ids, algorithm)

    header = <<
      @magic::binary,
      @version::8,
      alg_id::8,
      orig_size::32-big,
      comp_size::32-big,
      crc32::32-big
    >>

    <<header::binary, payload::binary>>
  end

  # Parses the envelope header
  defp parse_header(envelope) do
    case envelope do
      <<@magic::binary, @version::8, alg_id::8, orig_size::32-big, comp_size::32-big,
        crc32::32-big, payload::binary>> ->
        case Map.get(@algorithms, alg_id) do
          nil ->
            {:error, "unknown algorithm: #{alg_id}"}

          algorithm ->
            header = %{
              algorithm: algorithm,
              original_size: orig_size,
              compressed_size: comp_size,
              crc32: crc32
            }

            {:ok, header, payload}
        end

      <<@magic::binary, version::8, _rest::binary>> ->
        {:error, "unsupported version: #{version}"}

      _ ->
        {:error, "invalid BPX envelope"}
    end
  end

  # Compresses data with the specified algorithm
  defp compress(data, :none), do: {:ok, data}

  defp compress(data, :deflate) do
    try do
      compressed = :zlib.compress(data)
      {:ok, compressed}
    rescue
      _ -> {:error, :deflate_failed}
    end
  end

  defp compress(data, :brotli) do
    if Code.ensure_loaded?(:brotli) do
      try do
        compressed = apply(:brotli, :encode, [data])
        {:ok, compressed}
      rescue
        _ -> {:error, :brotli_failed}
      end
    else
      {:error, :brotli_not_available}
    end
  end

  defp compress(data, :zstd) do
    if Code.ensure_loaded?(:zstd) do
      try do
        compressed = apply(:zstd, :compress, [data])
        {:ok, compressed}
      rescue
        _ -> {:error, :zstd_failed}
      end
    else
      {:error, :zstd_not_available}
    end
  end

  # Decompresses data with the specified algorithm
  defp decompress(data, :none), do: {:ok, data}

  defp decompress(data, :deflate) do
    try do
      decompressed = :zlib.uncompress(data)
      {:ok, decompressed}
    rescue
      _ -> {:error, :deflate_decompression_failed}
    end
  end

  defp decompress(data, :brotli) do
    if Code.ensure_loaded?(:brotli) do
      try do
        decompressed = apply(:brotli, :decode, [data])
        {:ok, decompressed}
      rescue
        _ -> {:error, :brotli_decompression_failed}
      end
    else
      {:error, :brotli_not_available}
    end
  end

  defp decompress(data, :zstd) do
    if Code.ensure_loaded?(:zstd) do
      try do
        decompressed = apply(:zstd, :decompress, [data])
        {:ok, decompressed}
      rescue
        _ -> {:error, :zstd_decompression_failed}
      end
    else
      {:error, :zstd_not_available}
    end
  end

  # Validates decompressed data
  defp validate_data(data, header) do
    actual_size = byte_size(data)
    actual_crc = :erlang.crc32(data)

    cond do
      actual_size != header.original_size ->
        {:error, "size mismatch: expected #{header.original_size}, got #{actual_size}"}

      actual_crc != header.crc32 ->
        {:error, "CRC32 mismatch: expected #{header.crc32}, got #{actual_crc}"}

      true ->
        :ok
    end
  end

  # Checks if an algorithm is available
  defp algorithm_available?(:none), do: true
  defp algorithm_available?(:deflate), do: true
  defp algorithm_available?(:brotli), do: Code.ensure_loaded?(:brotli)
  defp algorithm_available?(:zstd), do: Code.ensure_loaded?(:zstd)

  @doc """
  Lists available algorithms in the current system.

  ## Example

      BPX.available_algorithms()
      # [:none, :deflate, :brotli]  # if brotli is installed
  """
  @spec available_algorithms() :: [algorithm()]
  def available_algorithms do
    [:none, :deflate, :brotli, :zstd]
    |> Enum.filter(&algorithm_available?/1)
  end

  @doc """
  Returns information about the BPX envelope without decompressing.

  ## Example

      {:ok, info} = BPX.inspect_envelope(envelope)
      IO.inspect(info.algorithm)     # :deflate
      IO.inspect(info.original_size) # 1024
  """
  @spec inspect_envelope(binary()) :: {:ok, map()} | {:error, term()}
  def inspect_envelope(envelope) do
    case parse_header(envelope) do
      {:ok, header, _payload} ->
        compression_ratio =
          if header.original_size == 0 do
            0.0
          else
            1.0 - header.compressed_size / header.original_size
          end

        info = %{
          algorithm: header.algorithm,
          original_size: header.original_size,
          compressed_size: header.compressed_size,
          compression_ratio: compression_ratio,
          envelope_size: byte_size(envelope)
        }

        {:ok, info}

      error ->
        error
    end
  end
end
