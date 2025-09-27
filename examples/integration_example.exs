#!/usr/bin/env elixir

# Integration Example: Bitpack + BPX
# This example shows how to use Bitpack for efficient bit-level packing
# combined with BPX for automatic compression selection.

Mix.install([
  {:jason, "~> 1.4"}
])

# Add the current project to the code path
Code.prepend_path(Path.join(__DIR__, "../lib"))

# Load the modules
Code.require_file(Path.join(__DIR__, "../lib/bitpack.ex"))
Code.require_file(Path.join(__DIR__, "../lib/bpx.ex"))

defmodule IntegrationExample do
  @moduledoc """
  Example demonstrating Bitpack + BPX integration for IoT sensor data.
  
  Scenario: IoT sensors collecting temperature, humidity, battery level,
  and status flags. We want maximum compression for network transmission.
  """

  def run do
    IO.puts("=== Bitpack + BPX Integration Example ===\n")
    
    # Define sensor data spec
    spec = [
      {:timestamp, {:u, 32}},      # Unix timestamp (32 bits)
      {:sensor_id, {:u, 16}},      # Sensor ID (16 bits)
      {:temperature, {:i, 12}},    # Temperature in 0.1°C, signed (-204.8 to +204.7°C)
      {:humidity, {:u, 7}},        # Humidity 0-100% (7 bits)
      {:battery, {:u, 8}},         # Battery level 0-255 (8 bits)
      {:online, {:bool}},          # Online status (1 bit)
      {:alarm, {:bool}},           # Alarm status (1 bit)
      {:checksum, {:u, 8}}         # Simple checksum (8 bits)
    ]

    # Generate sample sensor data
    sensor_data = generate_sensor_data(1000)
    
    IO.puts("Generated #{length(sensor_data)} sensor readings")
    IO.puts("Sample reading: #{inspect(Enum.at(sensor_data, 0))}\n")

    # Step 1: Pack with Bitpack
    IO.puts("Step 1: Packing with Bitpack...")
    bitpack_binary = Bitpack.pack(sensor_data, spec)
    bitpack_size = byte_size(bitpack_binary)
    
    IO.puts("  Bitpack size: #{format_bytes(bitpack_size)}")
    IO.puts("  Bytes per reading: #{Float.round(bitpack_size / length(sensor_data), 2)}")
    
    # Step 2: Compare with JSON
    json_binary = Jason.encode!(sensor_data) |> IO.iodata_to_binary()
    json_size = byte_size(json_binary)
    
    IO.puts("  JSON size: #{format_bytes(json_size)}")
    IO.puts("  Bitpack vs JSON: #{Float.round((1 - bitpack_size / json_size) * 100, 1)}% smaller\n")

    # Step 3: Wrap with BPX for additional compression
    IO.puts("Step 2: Wrapping with BPX...")
    bpx_envelope = BPX.wrap_auto(bitpack_binary, algos: [:deflate, :zstd, :brotli])
    bpx_size = byte_size(bpx_envelope)
    
    {:ok, bpx_info} = BPX.inspect_envelope(bpx_envelope)
    
    IO.puts("  BPX algorithm: #{bpx_info.algorithm}")
    IO.puts("  BPX envelope size: #{format_bytes(bpx_size)}")
    IO.puts("  Additional compression: #{Float.round(bpx_info.compression_ratio * 100, 1)}%")
    IO.puts("  Total size reduction vs JSON: #{Float.round((1 - bpx_size / json_size) * 100, 1)}%\n")

    # Step 4: Demonstrate round-trip
    IO.puts("Step 3: Verifying round-trip integrity...")
    {:ok, restored_bitpack, _meta} = BPX.unwrap(bpx_envelope)
    restored_data = Bitpack.unpack(restored_bitpack, spec)
    
    if restored_data == sensor_data do
      IO.puts("  ✓ Round-trip successful - data integrity verified")
    else
      IO.puts("  ✗ Round-trip failed - data corruption detected")
    end

    # Step 5: Performance comparison
    IO.puts("\nStep 4: Performance Summary")
    IO.puts("  Original JSON:     #{format_bytes(json_size)}")
    IO.puts("  Bitpack only:      #{format_bytes(bitpack_size)} (#{Float.round((1 - bitpack_size / json_size) * 100, 1)}% reduction)")
    IO.puts("  Bitpack + BPX:     #{format_bytes(bpx_size)} (#{Float.round((1 - bpx_size / json_size) * 100, 1)}% reduction)")
    IO.puts("  Compression ratio: #{Float.round(json_size / bpx_size, 1)}:1")
    
    # Step 6: Show network transmission benefits
    IO.puts("\nStep 5: Network Transmission Benefits")
    readings_per_day = 24 * 60  # Every minute
    daily_json = json_size * readings_per_day / length(sensor_data)
    daily_bpx = bpx_size * readings_per_day / length(sensor_data)
    
    IO.puts("  Daily data (1440 readings):")
    IO.puts("    JSON:          #{format_bytes(round(daily_json))}")
    IO.puts("    Bitpack+BPX:   #{format_bytes(round(daily_bpx))}")
    IO.puts("    Daily savings: #{format_bytes(round(daily_json - daily_bpx))}")
    IO.puts("    Monthly savings: #{format_bytes(round((daily_json - daily_bpx) * 30))}")
  end

  defp generate_sensor_data(count) do
    base_time = System.system_time(:second)
    
    Enum.map(1..count, fn i ->
      temp = :rand.uniform(400) - 200  # -20.0 to +20.0°C in 0.1°C units
      humidity = :rand.uniform(101) - 1  # 0-100%
      battery = :rand.uniform(256) - 1   # 0-255
      
      reading = %{
        timestamp: base_time + i * 60,  # Every minute
        sensor_id: rem(i - 1, 100) + 1, # Sensor IDs 1-100
        temperature: temp,
        humidity: humidity,
        battery: battery,
        online: :rand.uniform() > 0.05,  # 95% online
        alarm: :rand.uniform() > 0.9     # 10% alarm rate
      }
      
      # Add simple checksum
      checksum = rem(reading.temperature + reading.humidity + reading.battery, 256)
      Map.put(reading, :checksum, checksum)
    end)
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 1)}KB"
  end
  defp format_bytes(bytes) do
    "#{Float.round(bytes / (1024 * 1024), 1)}MB"
  end
end

# Run the example
IntegrationExample.run()
