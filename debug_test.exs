spec = [field_0: {:bytes, 0}]
rows = [%{field_0: ""}]

IO.puts("=== Debug test for {:bytes, 0} ===")
IO.inspect(spec, label: "Spec")
IO.inspect(rows, label: "Rows")

bin = Bitpack.pack(rows, spec)
IO.inspect(bin, label: "Packed binary")
IO.inspect(byte_size(bin), label: "Binary size")

result = Bitpack.unpack(bin, spec)
IO.inspect(result, label: "Unpacked result")
IO.inspect(length(result), label: "Result length")

IO.puts("\n=== Expected vs Actual ===")
IO.puts("Expected: #{inspect(rows)}")
IO.puts("Actual:   #{inspect(result)}")
IO.puts("Match: #{rows == result}")
