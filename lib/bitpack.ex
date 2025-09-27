defmodule Bitpack do
  import Bitwise

  @moduledoc """
  Bit-level pack/unpack for rows of small fields.

  Supported field specs (MVP):
    * {:u, n}       - unsigned integer (n bits)
    * {:i, n}       - signed integer (n bits, two's complement)
    * {:bool}       - boolean (1 bit)
    * {:bytes, k}   - fixed-size bytes (k bytes), byte-aligned in-stream

  Contract (MVP):
    * Fields são escritos **na ordem do spec**.
    * Antes de um campo {:bytes, k}, alinhamos para o próximo byte.
    * Ao final de **cada linha**, alinhamos para o próximo byte (padding com zeros).
  """

  @type spec_field ::
          {atom(), {:u, pos_integer()}}
          | {atom(), {:i, pos_integer()}}
          | {atom(), {:bool}}
          | {atom(), {:bytes, non_neg_integer()}}
  @type spec :: [spec_field]
  @type row :: map()

  @doc "Pack a list of rows according to spec into a compact binary."
  @spec pack([row()], spec()) :: binary()
  def pack(rows, spec) do
    rows
    |> Enum.reduce([], fn row, acc -> [pack_row(row, spec) | acc] end)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
  end

  @doc "Safe version of pack/2 that returns {:ok, binary()} | {:error, reason}."
  @spec pack_safe([row()], spec()) :: {:ok, binary()} | {:error, term()}
  def pack_safe(rows, spec) do
    try do
      validate_spec!(spec)
      result = pack(rows, spec)
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc "Unpack a binary into a list of rows according to spec."
  @spec unpack(binary(), spec()) :: [row()]
  def unpack(bin, spec), do: do_unpack(bin, spec, [])

  @doc "Safe version of unpack/2 that returns {:ok, [row()]} | {:error, reason}."
  @spec unpack_safe(binary(), spec()) :: {:ok, [row()]} | {:error, term()}
  def unpack_safe(bin, spec) do
    try do
      validate_spec!(spec)
      result = unpack(bin, spec)
      {:ok, result}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  @doc "Validate a spec, raising if invalid. Returns the spec if valid."
  @spec validate_spec!(spec()) :: spec()
  def validate_spec!(spec) when is_list(spec) do
    if spec == [] do
      raise ArgumentError, "spec cannot be empty"
    end

    field_names = MapSet.new()

    Enum.reduce(spec, field_names, fn field, acc ->
      case field do
        {name, {:u, n}} when is_atom(name) and is_integer(n) and n > 0 and n <= 64 ->
          if MapSet.member?(acc, name) do
            raise ArgumentError, "duplicate field name: #{inspect(name)}"
          end

          MapSet.put(acc, name)

        {name, {:i, n}} when is_atom(name) and is_integer(n) and n > 0 and n <= 64 ->
          if MapSet.member?(acc, name) do
            raise ArgumentError, "duplicate field name: #{inspect(name)}"
          end

          MapSet.put(acc, name)

        {name, {:bool}} when is_atom(name) ->
          if MapSet.member?(acc, name) do
            raise ArgumentError, "duplicate field name: #{inspect(name)}"
          end

          MapSet.put(acc, name)

        {name, {:bytes, n}} when is_atom(name) and is_integer(n) and n >= 0 ->
          if MapSet.member?(acc, name) do
            raise ArgumentError, "duplicate field name: #{inspect(name)}"
          end

          MapSet.put(acc, name)

        {name, type} when is_atom(name) ->
          raise ArgumentError, "invalid field type for #{inspect(name)}: #{inspect(type)}"

        other ->
          raise ArgumentError, "invalid spec field format: #{inspect(other)}"
      end
    end)

    spec
  end

  def validate_spec!(spec) do
    raise ArgumentError, "spec must be a list, got: #{inspect(spec)}"
  end

  @doc "Calculate the size in bytes for each row according to the spec."
  @spec row_size(spec()) :: non_neg_integer()
  def row_size(spec) do
    validate_spec!(spec)

    total_bits =
      Enum.reduce(spec, 0, fn
        {_name, {:u, n}}, acc ->
          acc + n

        {_name, {:i, n}}, acc ->
          acc + n

        {_name, {:bool}}, acc ->
          acc + 1

        {_name, {:bytes, n}}, acc ->
          # Align to byte boundary before bytes field
          aligned_acc = div(acc + 7, 8) * 8
          aligned_acc + n * 8
      end)

    # Final alignment to byte boundary
    div(total_bits + 7, 8)
  end

  @doc "Generate a hexdump representation of binary data for debugging."
  @spec hexdump(binary()) :: String.t()
  def hexdump(bin) when is_binary(bin) do
    bin
    |> :binary.bin_to_list()
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.map(fn {chunk, offset} ->
      hex_part =
        chunk
        |> Enum.map(&String.pad_leading(Integer.to_string(&1, 16), 2, "0"))
        |> Enum.join(" ")
        # 16 * 3 - 1 = 47
        |> String.pad_trailing(47)

      ascii_part =
        chunk
        |> Enum.map(fn byte ->
          if byte >= 32 and byte <= 126, do: <<byte>>, else: "."
        end)
        |> Enum.join()

      offset_str = String.pad_leading(Integer.to_string(offset * 16, 16), 8, "0")
      "#{offset_str}  #{hex_part}  |#{ascii_part}|"
    end)
    |> Enum.join("\n")
  end

  @doc "Inspect how a single row would be packed according to spec, showing bit layout."
  @spec inspect_row(row(), spec()) :: String.t()
  def inspect_row(row, spec) do
    validate_spec!(spec)

    {final_bits, parts} =
      Enum.reduce(spec, {<<>>, []}, fn field, {acc_bits, acc_parts} ->
        case field do
          {name, {:u, n}} ->
            value = Map.get(row, name, 0)
            bits = <<acc_bits::bitstring, value::unsigned-integer-size(n)>>
            part = "#{name}:u#{n}=#{value} (#{n} bits)"
            {bits, [part | acc_parts]}

          {name, {:i, n}} ->
            value = Map.get(row, name, 0)
            bits = <<acc_bits::bitstring, value::signed-integer-size(n)>>
            part = "#{name}:i#{n}=#{value} (#{n} bits)"
            {bits, [part | acc_parts]}

          {name, {:bool}} ->
            value = Map.get(row, name, false)
            bit_val = if value, do: 1, else: 0
            bits = <<acc_bits::bitstring, bit_val::size(1)>>
            part = "#{name}:bool=#{value} (1 bit)"
            {bits, [part | acc_parts]}

          {name, {:bytes, n}} ->
            value = Map.get(row, name, <<>>)
            aligned_bits = align_bits(acc_bits)
            bits = <<aligned_bits::bitstring, value::binary-size(n)>>
            part = "#{name}:bytes#{n}=#{inspect(value)} (#{n * 8} bits, byte-aligned)"
            {bits, [part | acc_parts]}
        end
      end)

    field_descriptions =
      parts
      |> Enum.reverse()
      |> Enum.join("\n  ")

    final_aligned = align_bits(final_bits)
    total_bytes = byte_size(final_aligned)

    """
    Row inspection:
      #{field_descriptions}
    Total: #{total_bytes} bytes (with padding)
    """
  end

  defp pack_row(row, spec) do
    bits =
      Enum.reduce(spec, <<>>, fn
        {k, {:u, n}}, acc when n > 0 ->
          v = fetch_u!(row, k, n)
          <<acc::bitstring, v::unsigned-integer-size(n)>>

        {k, {:i, n}}, acc when n > 0 ->
          v = fetch_i!(row, k, n)
          <<acc::bitstring, v::signed-integer-size(n)>>

        {k, {:bool}}, acc ->
          v =
            case Map.fetch!(row, k) do
              true ->
                1

              false ->
                0

              other ->
                raise ArgumentError, "expected boolean for #{inspect(k)}, got: #{inspect(other)}"
            end

          <<acc::bitstring, v::size(1)>>

        {k, {:bytes, n}}, acc when n >= 0 ->
          bin = Map.fetch!(row, k)

          unless is_binary(bin) and byte_size(bin) == n do
            raise ArgumentError, "expected #{inspect(k)} to be #{n} bytes, got #{byte_size(bin)}"
          end

          acc = align_bits(acc)
          <<acc::bitstring, bin::binary-size(n)>>

        field, _acc ->
          raise ArgumentError, "invalid spec field: #{inspect(field)}"
      end)

    align_bits(bits)
  end

  defp do_unpack(<<>>, spec, acc) do
    # Special case: if we have an empty binary but the spec would produce 0-byte rows,
    # we can't determine how many rows were originally packed. This is a limitation
    # of the format when all fields are 0-bit/0-byte.
    row_bytes = calculate_row_bytes(spec)

    if row_bytes == 0 and acc == [] do
      # We assume empty input means empty output for 0-byte specs
      []
    else
      Enum.reverse(acc)
    end
  end

  defp do_unpack(bin, spec, acc) do
    case unpack_row(bin, spec, %{}) do
      {row, <<>>} ->
        # If we consumed all remaining bits, we're done
        Enum.reverse([row | acc])

      {row, rest} ->
        # Continue with remaining bits
        do_unpack(rest, spec, [row | acc])
    end
  end

  # Helper function to calculate row size without validation (for internal use)
  defp calculate_row_bytes(spec) do
    total_bits =
      Enum.reduce(spec, 0, fn
        {_name, {:u, n}}, acc ->
          acc + n

        {_name, {:i, n}}, acc ->
          acc + n

        {_name, {:bool}}, acc ->
          acc + 1

        {_name, {:bytes, n}}, acc ->
          # Align to byte boundary before bytes field
          aligned_acc = div(acc + 7, 8) * 8
          aligned_acc + n * 8
      end)

    # Final alignment to byte boundary
    div(total_bits + 7, 8)
  end

  defp unpack_row(bin, spec, row) do
    {rest_bits, out} =
      Enum.reduce(spec, {bin, row}, fn
        {k, {:u, n}}, {bits, r} ->
          <<v::unsigned-integer-size(n), rest::bitstring>> = bits
          {rest, Map.put(r, k, v)}

        {k, {:i, n}}, {bits, r} ->
          <<v::signed-integer-size(n), rest::bitstring>> = bits
          {rest, Map.put(r, k, v)}

        {k, {:bool}}, {bits, r} ->
          <<b::size(1), rest::bitstring>> = bits
          {rest, Map.put(r, k, b == 1)}

        {k, {:bytes, n}}, {bits, r} ->
          {rest2, chunk} = take_bytes(bits, n)
          {rest2, Map.put(r, k, chunk)}
      end)

    next = align_to_next_byte(rest_bits)
    {out, next}
  end

  defp align_to_next_byte(bs) when is_bitstring(bs) do
    case rem(bit_size(bs), 8) do
      0 ->
        bs

      r ->
        <<_pad::size(r), rest::binary>> = bs
        rest
    end
  end

  defp take_bytes(bits, n) do
    bits = align_to_next_byte(bits)
    <<chunk::binary-size(n), rest2::bitstring>> = bits
    {rest2, chunk}
  end

  defp align_bits(bits) do
    rem = rem(bit_size(bits), 8)
    if rem == 0, do: bits, else: <<bits::bitstring, 0::size(8 - rem)>>
  end

  defp fetch_u!(row, k, n) do
    v = Map.fetch!(row, k)
    max = (1 <<< n) - 1

    unless is_integer(v) and v >= 0 and v <= max do
      raise ArgumentError, "field #{inspect(k)} out of range 0..#{max}, got: #{inspect(v)}"
    end

    v
  end

  defp fetch_i!(row, k, n) do
    v = Map.fetch!(row, k)
    min = -(1 <<< (n - 1))
    max = (1 <<< (n - 1)) - 1

    unless is_integer(v) and v >= min and v <= max do
      raise ArgumentError, "field #{inspect(k)} out of range #{min}..#{max}, got: #{inspect(v)}"
    end

    v
  end
end
