defmodule BitpackTest do
  use ExUnit.Case, async: true

  test "round-trip with bits + bytes" do
    spec = [
      {:status, {:u, 3}},
      {:vip,    {:bool}},
      {:tries,  {:u, 5}},
      {:amount, {:u, 20}},
      {:tag,    {:bytes, 3}}
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
      Bitpack.pack([%{count: 9}], spec)  # 9 não cabe em 3 bits
    end
  end

  test "validation: bytes length mismatch raises" do
    spec = [blob: {:bytes, 4}]
    assert_raise ArgumentError, fn ->
      Bitpack.pack([%{blob: <<1,2,3>>}], spec)
    end
  end
end
