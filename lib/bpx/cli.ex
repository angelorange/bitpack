defmodule BPX.CLI do
  @moduledoc """
  Command-line interface for BPX compression operations.

  Supports packing and unpacking files with automatic compression algorithm selection.
  """

  def main(args) do
    case parse_args(args) do
      {:pack, input_file, output_file, opts} ->
        pack_command(input_file, output_file, opts)

      {:unpack, input_file, output_file} ->
        unpack_command(input_file, output_file)

      {:info, input_file} ->
        info_command(input_file)

      {:help} ->
        print_help()

      {:error, message} ->
        IO.puts(:stderr, "Error: #{message}")
        print_help()
        System.halt(1)
    end
  end

  defp parse_args(["pack", input_file, output_file | opts]) do
    parsed_opts = parse_pack_options(opts, [])
    {:pack, input_file, output_file, parsed_opts}
  end

  defp parse_args(["unpack", input_file, output_file]) do
    {:unpack, input_file, output_file}
  end

  defp parse_args(["info", input_file]) do
    {:info, input_file}
  end

  defp parse_args(["--help"]) do
    {:help}
  end

  defp parse_args(["-h"]) do
    {:help}
  end

  defp parse_args([]) do
    {:help}
  end

  defp parse_args(_) do
    {:error, "Invalid arguments"}
  end

  defp parse_pack_options([], acc), do: acc

  defp parse_pack_options(["--algos", algos_str | rest], acc) do
    algos =
      algos_str
      |> String.split(",")
      |> Enum.map(&String.to_atom/1)

    parse_pack_options(rest, [{:algos, algos} | acc])
  end

  defp parse_pack_options(["--min-gain", gain_str | rest], acc) do
    case Integer.parse(gain_str) do
      {gain, ""} -> parse_pack_options(rest, [{:min_gain, gain} | acc])
      _ -> [{:error, "Invalid min-gain value: #{gain_str}"}]
    end
  end

  defp parse_pack_options([unknown | _], _acc) do
    [{:error, "Unknown option: #{unknown}"}]
  end

  defp pack_command(input_file, output_file, opts) do
    case File.read(input_file) do
      {:ok, data} ->
        IO.puts("Packing #{input_file} (#{format_bytes(byte_size(data))})...")

        algos = Keyword.get(opts, :algos, [:zstd, :brotli, :deflate])
        min_gain = Keyword.get(opts, :min_gain, 16)

        available_algos = BPX.available_algorithms()
        filtered_algos = Enum.filter(algos, &(&1 in available_algos))

        final_algos =
          if filtered_algos == [] do
            IO.puts(:stderr, "Warning: No requested algorithms available, using :deflate")
            [:deflate]
          else
            filtered_algos
          end

        envelope = BPX.wrap_auto(data, algos: final_algos, min_gain: min_gain)

        case File.write(output_file, envelope) do
          :ok ->
            {:ok, info} = BPX.inspect_envelope(envelope)

            IO.puts("✓ Packed successfully!")
            IO.puts("  Algorithm: #{info.algorithm}")
            IO.puts("  Original:  #{format_bytes(info.original_size)}")
            IO.puts("  Envelope:  #{format_bytes(info.envelope_size)}")

            IO.puts(
              "  Saved:     #{format_bytes(info.original_size - info.envelope_size)} (#{Float.round(info.compression_ratio * 100, 1)}%)"
            )

          {:error, reason} ->
            IO.puts(:stderr, "Failed to write output: #{:file.format_error(reason)}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "Failed to read input: #{:file.format_error(reason)}")
        System.halt(1)
    end
  end

  defp unpack_command(input_file, output_file) do
    case File.read(input_file) do
      {:ok, envelope} ->
        IO.puts("Unpacking #{input_file} (#{format_bytes(byte_size(envelope))})...")

        case BPX.unwrap(envelope) do
          {:ok, data, meta} ->
            case File.write(output_file, data) do
              :ok ->
                IO.puts("✓ Unpacked successfully!")
                IO.puts("  Algorithm: #{meta.algorithm}")
                IO.puts("  Envelope:  #{format_bytes(byte_size(envelope))}")
                IO.puts("  Original:  #{format_bytes(meta.original_size)}")
                IO.puts("  Restored:  #{format_bytes(byte_size(data))}")

              {:error, reason} ->
                IO.puts(:stderr, "Failed to write output: #{:file.format_error(reason)}")
                System.halt(1)
            end

          {:error, reason} ->
            IO.puts(:stderr, "Failed to unpack: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "Failed to read input: #{:file.format_error(reason)}")
        System.halt(1)
    end
  end

  defp info_command(input_file) do
    case File.read(input_file) do
      {:ok, envelope} ->
        case BPX.inspect_envelope(envelope) do
          {:ok, info} ->
            IO.puts("BPX Envelope Information:")
            IO.puts("  File:        #{input_file}")
            IO.puts("  Algorithm:   #{info.algorithm}")
            IO.puts("  Original:    #{format_bytes(info.original_size)}")
            IO.puts("  Compressed:  #{format_bytes(info.compressed_size)}")
            IO.puts("  Envelope:    #{format_bytes(info.envelope_size)}")
            IO.puts("  Compression: #{Float.round(info.compression_ratio * 100, 1)}%")
            IO.puts("  Overhead:    #{info.envelope_size - info.compressed_size} bytes")

          {:error, reason} ->
            IO.puts(:stderr, "Not a valid BPX file: #{reason}")
            System.halt(1)
        end

      {:error, reason} ->
        IO.puts(:stderr, "Failed to read file: #{:file.format_error(reason)}")
        System.halt(1)
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"

  defp format_bytes(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 1)}KB"
  end

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024 do
    "#{Float.round(bytes / (1024 * 1024), 1)}MB"
  end

  defp format_bytes(bytes) do
    "#{Float.round(bytes / (1024 * 1024 * 1024), 1)}GB"
  end

  defp print_help do
    IO.puts("""
    BPX CLI - Binary Payload eXchange with automatic compression

    Usage:
      bpx pack <input> <output> [options]
      bpx unpack <input> <output>
      bpx info <file>
      bpx --help

    Commands:
      pack      Compress file with automatic algorithm selection
      unpack    Decompress BPX file
      info      Show BPX file information without unpacking

    Pack Options:
      --algos ALGOS     Comma-separated list of algorithms to try
                        Available: none,deflate,brotli,zstd
                        Default: zstd,brotli,deflate
      --min-gain BYTES  Minimum bytes saved to use compression
                        Default: 16

    Examples:
      # Pack with default settings
      bpx pack document.pdf document.bpx

      # Pack with specific algorithms and min gain
      bpx pack data.json data.bpx --algos zstd,deflate --min-gain 32

      # Unpack file
      bpx unpack document.bpx restored.pdf

      # Show file info
      bpx info document.bpx

    Available algorithms on this system:
      #{BPX.available_algorithms() |> Enum.join(", ")}
    """)
  end
end
