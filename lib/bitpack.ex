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

  @doc "Unpack a binary into a list of rows according to spec."
  @spec unpack(binary(), spec()) :: [row()]
  def unpack(bin, spec), do: do_unpack(bin, spec, [])

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

  defp do_unpack(<<>>, _spec, acc), do: Enum.reverse(acc)

  defp do_unpack(bin, spec, acc) do
    {row, rest} = unpack_row(bin, spec, %{})
    do_unpack(rest, spec, [row | acc])
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
