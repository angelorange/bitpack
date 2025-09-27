defmodule SimpleIntegration do
  @moduledoc """
  Simple integration example showing Bitpack + BPX usage.
  
  Run with: mix run examples/simple_integration.ex
  """

  def run do
    IO.puts("=== Bitpack + BPX Integration Example ===\n")
    
    # Define IoT sensor spec
    spec = [
      {:timestamp, {:u, 32}},
      {:sensor_id, {:u, 16}},
      {:temperature, {:i, 12}},  # -204.8 to +204.7°C in 0.1°C units
      {:humidity, {:u, 7}},      # 0-100%
      {:battery, {:u, 8}},       # 0-255
      {:online, {:bool}},
      {:alarm, {:bool}}
    ]

    # Sample data
    data = [
      %{timestamp: 1640995200, sensor_id: 1, temperature: 235, humidity: 65, battery: 180, online: true, alarm: false},
      %{timestamp: 1640995260, sensor_id: 2, temperature: -45, humidity: 72, battery: 165, online: true, alarm: false},
      %{timestamp: 1640995320, sensor_id: 3, temperature: 180, humidity: 58, battery: 200, online: false, alarm: true}
    ]

    IO.puts("Sample data (#{length(data)} readings):")
    Enum.each(data, &IO.puts("  #{inspect(&1)}"))
    IO.puts("")

    # Step 1: JSON baseline
    json_data = Jason.encode!(data)
    json_size = byte_size(json_data)
    IO.puts("JSON size: #{json_size} bytes")

    # Step 2: Bitpack compression
    bitpack_data = Bitpack.pack(data, spec)
    bitpack_size = byte_size(bitpack_data)
    bitpack_reduction = Float.round((1 - bitpack_size / json_size) * 100, 1)
    
    IO.puts("Bitpack size: #{bitpack_size} bytes (#{bitpack_reduction}% smaller than JSON)")
    IO.puts("Bytes per reading: #{Float.round(bitpack_size / length(data), 2)}")

    # Step 3: BPX envelope
    bpx_envelope = BPX.wrap_auto(bitpack_data)
    bpx_size = byte_size(bpx_envelope)
    total_reduction = Float.round((1 - bpx_size / json_size) * 100, 1)
    
    {:ok, info} = BPX.inspect_envelope(bpx_envelope)
    IO.puts("BPX envelope: #{bpx_size} bytes using #{info.algorithm}")
    IO.puts("Total reduction vs JSON: #{total_reduction}%")
    IO.puts("Compression ratio: #{Float.round(json_size / bpx_size, 1)}:1")

    # Step 4: Verify round-trip
    {:ok, restored_bitpack, _meta} = BPX.unwrap(bpx_envelope)
    restored_data = Bitpack.unpack(restored_bitpack, spec)
    
    if restored_data == data do
      IO.puts("✓ Round-trip verification successful")
    else
      IO.puts("✗ Round-trip verification failed")
    end

    IO.puts("\n=== Summary ===")
    IO.puts("Original JSON:     #{json_size} bytes")
    IO.puts("Bitpack only:      #{bitpack_size} bytes")
    IO.puts("Bitpack + BPX:     #{bpx_size} bytes")
    IO.puts("Space savings:     #{json_size - bpx_size} bytes (#{total_reduction}%)")
  end
end

SimpleIntegration.run()
