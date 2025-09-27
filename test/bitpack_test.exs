defmodule BitpackTest do
  use ExUnit.Case, async: true

  test "round-trip with bits + bytes" do
    spec = [
      {:status, {:u, 3}},
      {:vip, {:bool}},
      {:tries, {:u, 5}},
      {:amount, {:u, 20}},
      {:tag, {:bytes, 3}}
    ]

    rows =
      for i <- 0..50 do
        %{
          status: rem(i, 8),
          vip: rem(i, 2) == 1,
          tries: rem(i, 32),
          amount: i * 12345,
          tag: <<i, i + 1, i + 2>>
        }
      end

    bin = Bitpack.pack(rows, spec)
    assert Bitpack.unpack(bin, spec) == rows
  end

  test "validation: unsigned out of range raises" do
    spec = [count: {:u, 3}]

    assert_raise ArgumentError, fn ->
      # 9 não cabe em 3 bits
      Bitpack.pack([%{count: 9}], spec)
    end
  end

  test "validation: bytes length mismatch raises" do
    spec = [blob: {:bytes, 4}]

    assert_raise ArgumentError, fn ->
      Bitpack.pack([%{blob: <<1, 2, 3>>}], spec)
    end
  end

  test "pack_safe/2 returns {:ok, binary} on success" do
    spec = [count: {:u, 8}]
    rows = [%{count: 42}]

    assert {:ok, bin} = Bitpack.pack_safe(rows, spec)
    assert is_binary(bin)
  end

  test "pack_safe/2 returns {:error, reason} on failure" do
    spec = [count: {:u, 3}]
    # 9 doesn't fit in 3 bits
    rows = [%{count: 9}]

    assert {:error, reason} = Bitpack.pack_safe(rows, spec)
    assert is_binary(reason)
  end

  test "unpack_safe/2 returns {:ok, rows} on success" do
    spec = [count: {:u, 8}]
    rows = [%{count: 42}]
    bin = Bitpack.pack(rows, spec)

    assert {:ok, ^rows} = Bitpack.unpack_safe(bin, spec)
  end

  test "validate_spec!/1 accepts valid spec" do
    spec = [
      {:status, {:u, 3}},
      {:vip, {:bool}},
      {:data, {:bytes, 4}}
    ]

    assert ^spec = Bitpack.validate_spec!(spec)
  end

  test "validate_spec!/1 rejects invalid spec" do
    assert_raise ArgumentError, fn ->
      Bitpack.validate_spec!([])
    end

    assert_raise ArgumentError, fn ->
      Bitpack.validate_spec!([{:bad, {:u, 0}}])
    end

    assert_raise ArgumentError, fn ->
      Bitpack.validate_spec!([{:dup, {:u, 8}}, {:dup, {:bool}}])
    end
  end

  test "row_size/1 calculates correct byte size" do
    spec = [
      {:status, {:u, 3}},
      {:vip, {:bool}},
      {:tries, {:u, 5}},
      {:amount, {:u, 20}},
      {:tag, {:bytes, 3}}
    ]

    # 3 + 1 + 5 + 20 = 29 bits, aligned to byte = 32 bits = 4 bytes
    # then 3 bytes for tag field = 7 bytes total
    assert Bitpack.row_size(spec) == 7
  end

  test "hexdump/1 formats binary data" do
    bin = <<0x48, 0x65, 0x6C, 0x6C, 0x6F>>
    dump = Bitpack.hexdump(bin)

    assert dump =~ "48 65 6C 6C 6F"
    assert dump =~ "|Hello|"
  end

  test "inspect_row/2 shows field layout" do
    spec = [status: {:u, 3}, vip: {:bool}]
    row = %{status: 5, vip: true}

    inspection = Bitpack.inspect_row(row, spec)

    assert inspection =~ "status:u3=5"
    assert inspection =~ "vip:bool=true"
    assert inspection =~ "Total: 1 bytes"
  end
end
