defmodule Bitpack.CLI do
  @moduledoc """
  Command-line interface for Bitpack operations.

  Supports conversion between NDJSON and bitpack binary format.
  """

  def main(args) do
    case parse_args(args) do
      {:pack, spec_file, input_file, output_file} ->
        pack_command(spec_file, input_file, output_file)

      {:unpack, spec_file, input_file, output_file} ->
        unpack_command(spec_file, input_file, output_file)

      {:help} ->
        print_help()

      {:error, message} ->
        IO.puts(:stderr, "Error: #{message}")
        print_help()
        System.halt(1)
    end
  end

  defp parse_args(["pack", spec_file, input_file, output_file]) do
    {:pack, spec_file, input_file, output_file}
  end

  defp parse_args(["unpack", spec_file, input_file, output_file]) do
    {:unpack, spec_file, input_file, output_file}
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

  defp pack_command(spec_file, input_file, output_file) do
    with {:ok, spec} <- load_spec(spec_file),
         {:ok, ndjson_data} <- File.read(input_file),
         {:ok, rows} <- parse_ndjson(ndjson_data),
         {:ok, binary} <- Bitpack.pack_safe(rows, spec),
         :ok <- File.write(output_file, binary) do
      IO.puts("Successfully packed #{length(rows)} rows to #{output_file}")
      IO.puts("Output size: #{byte_size(binary)} bytes")
    else
      {:error, reason} ->
        IO.puts(:stderr, "Pack failed: #{reason}")
        System.halt(1)
    end
  end

  defp unpack_command(spec_file, input_file, output_file) do
    with {:ok, spec} <- load_spec(spec_file),
         {:ok, binary} <- File.read(input_file),
         {:ok, rows} <- Bitpack.unpack_safe(binary, spec),
         {:ok, ndjson} <- encode_ndjson(rows),
         :ok <- File.write(output_file, ndjson) do
      IO.puts("Successfully unpacked #{length(rows)} rows to #{output_file}")
    else
      {:error, reason} ->
        IO.puts(:stderr, "Unpack failed: #{reason}")
        System.halt(1)
    end
  end

  defp load_spec(spec_file) do
    case File.read(spec_file) do
      {:ok, content} ->
        try do
          {spec, _} = Code.eval_string(content)
          Bitpack.validate_spec!(spec)
          {:ok, spec}
        rescue
          e -> {:error, "Invalid spec file: #{Exception.message(e)}"}
        end

      {:error, reason} ->
        {:error, "Cannot read spec file: #{:file.format_error(reason)}"}
    end
  end

  defp parse_ndjson(ndjson_data) do
    try do
      rows =
        ndjson_data
        |> String.trim()
        |> String.split("\n")
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&Jason.decode!/1)
        |> Enum.map(&atomize_keys/1)

      {:ok, rows}
    rescue
      e -> {:error, "Invalid NDJSON: #{Exception.message(e)}"}
    end
  end

  defp encode_ndjson(rows) do
    try do
      ndjson =
        rows
        |> Enum.map(&Jason.encode!/1)
        |> Enum.join("\n")
        |> Kernel.<>("\n")

      {:ok, ndjson}
    rescue
      e -> {:error, "JSON encoding failed: #{Exception.message(e)}"}
    end
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), v} end)
  end

  defp print_help do
    IO.puts("""
    Bitpack CLI - Compact binary packing for structured data

    Usage:
      bitpack pack <spec_file> <input.ndjson> <output.bin>
      bitpack unpack <spec_file> <input.bin> <output.ndjson>
      bitpack --help

    Commands:
      pack      Convert NDJSON to compact binary format
      unpack    Convert binary format back to NDJSON

    Arguments:
      spec_file     Elixir file containing the field specification
      input.ndjson  Newline-delimited JSON input file
      output.bin    Binary output file
      input.bin     Binary input file  
      output.ndjson NDJSON output file

    Example spec file (spec.exs):
      [
        {:status, {:u, 3}},
        {:vip, {:bool}},
        {:tries, {:u, 5}},
        {:amount, {:u, 20}},
        {:tag, {:bytes, 3}}
      ]

    Example usage:
      bitpack pack spec.exs data.ndjson data.bin
      bitpack unpack spec.exs data.bin restored.ndjson
    """)
  end
end
