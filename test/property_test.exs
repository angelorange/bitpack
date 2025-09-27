defmodule BitpackPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import Bitwise

  @moduletag timeout: 60_000

  property "pack/unpack round-trip preserves data" do
    check all(
            spec <- spec_generator(),
            rows <- rows_generator(spec, 1..10)
          ) do
      binary = Bitpack.pack(rows, spec)
      assert Bitpack.unpack(binary, spec) == rows
    end
  end

  property "packed data is deterministic" do
    check all(
            spec <- spec_generator(),
            rows <- rows_generator(spec, 1..5)
          ) do
      binary1 = Bitpack.pack(rows, spec)
      binary2 = Bitpack.pack(rows, spec)
      assert binary1 == binary2
    end
  end

  property "row_size/1 matches actual packed size for single row" do
    check all(
            spec <- spec_generator(),
            row <- row_generator(spec)
          ) do
      expected_size = Bitpack.row_size(spec)
      actual_binary = Bitpack.pack([row], spec)
      assert byte_size(actual_binary) == expected_size
    end
  end

  property "pack_safe/2 succeeds for valid data" do
    check all(
            spec <- spec_generator(),
            rows <- rows_generator(spec, 1..5)
          ) do
      assert {:ok, binary} = Bitpack.pack_safe(rows, spec)
      assert is_binary(binary)
      assert {:ok, ^rows} = Bitpack.unpack_safe(binary, spec)
    end
  end

  property "hexdump/1 produces valid output" do
    check all(
            spec <- spec_generator(),
            rows <- rows_generator(spec, 1..3)
          ) do
      binary = Bitpack.pack(rows, spec)
      dump = Bitpack.hexdump(binary)

      # Should contain hex characters and pipe separators
      assert dump =~ ~r/[0-9A-F]/
      assert dump =~ "|"
    end
  end

  # Generators

  defp spec_generator do
    gen all(
          field_count <- integer(1..8),
          fields <- list_of(field_generator(), length: field_count)
        ) do
      # Ensure unique field names
      spec =
        fields
        |> Enum.with_index()
        |> Enum.map(fn {{_name, type}, idx} ->
          {String.to_atom("field_#{idx}"), type}
        end)

      # Filter out specs that would result in 0 bytes per row
      # This is a known limitation: we can't distinguish between
      # "0 rows" and "N rows of 0 bytes each"
      if spec_produces_zero_bytes?(spec) do
        # Add at least one bit field to ensure non-zero size
        [{:padding, {:u, 1}} | spec]
      else
        spec
      end
    end
  end

  defp spec_produces_zero_bytes?(spec) do
    total_bits =
      Enum.reduce(spec, 0, fn
        {_name, {:u, n}}, acc ->
          acc + n

        {_name, {:i, n}}, acc ->
          acc + n

        {_name, {:bool}}, acc ->
          acc + 1

        {_name, {:bytes, n}}, acc ->
          aligned_acc = div(acc + 7, 8) * 8
          aligned_acc + n * 8
      end)

    div(total_bits + 7, 8) == 0
  end

  defp field_generator do
    one_of([
      # Unsigned integers (1-32 bits for reasonable test performance)
      gen all(n <- integer(1..32)) do
        {:dummy, {:u, n}}
      end,

      # Signed integers (2-32 bits)
      gen all(n <- integer(2..32)) do
        {:dummy, {:i, n}}
      end,

      # Booleans
      constant({:dummy, {:bool}}),

      # Bytes (0-8 bytes for reasonable test performance)
      gen all(n <- integer(0..8)) do
        {:dummy, {:bytes, n}}
      end
    ])
  end

  defp rows_generator(spec, count_range) do
    gen all(
          count <- integer(count_range),
          rows <- list_of(row_generator(spec), length: count)
        ) do
      rows
    end
  end

  defp row_generator(spec) do
    gen all(
          values <-
            fixed_list(
              Enum.map(spec, fn {name, type} ->
                {name, value_generator(type)}
              end)
            )
        ) do
      Map.new(values)
    end
  end

  defp value_generator({:u, n}) do
    max_val = (1 <<< n) - 1
    integer(0..max_val)
  end

  defp value_generator({:i, n}) do
    min_val = -(1 <<< (n - 1))
    max_val = (1 <<< (n - 1)) - 1
    integer(min_val..max_val)
  end

  defp value_generator({:bool}) do
    boolean()
  end

  defp value_generator({:bytes, n}) do
    binary(length: n)
  end
end
