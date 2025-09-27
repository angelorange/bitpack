defmodule BitpackBench do
  @moduledoc """
  Benchmarks comparing Bitpack with JSON for various data scenarios.
  """

  def run do
    # IoT sensor data scenario
    iot_spec = [
      {:sensor_id, {:u, 16}},      # 0-65535
      {:temperature, {:i, 12}},    # -2048 to 2047 (scaled by 10)
      {:humidity, {:u, 7}},        # 0-100%
      {:battery, {:u, 7}},         # 0-100%
      {:active, {:bool}},          # on/off
      {:error_flags, {:u, 8}},     # 8 error bits
      {:timestamp_offset, {:u, 16}} # seconds from base
    ]

    # Gaming events scenario  
    game_spec = [
      {:player_id, {:u, 20}},      # 0-1M players
      {:action_type, {:u, 4}},     # 16 action types
      {:x_pos, {:u, 12}},          # 0-4095 map coords
      {:y_pos, {:u, 12}},          # 0-4095 map coords
      {:health, {:u, 8}},          # 0-255 HP
      {:mana, {:u, 8}},            # 0-255 MP
      {:level, {:u, 8}},           # 0-255 level
      {:flags, {:u, 16}},          # various flags
      {:item_id, {:u, 16}}         # 0-65535 items
    ]

    # Financial transaction scenario
    finance_spec = [
      {:account_id, {:u, 32}},     # account number
      {:amount, {:u, 32}},         # cents (up to ~42M)
      {:currency, {:u, 8}},        # currency code
      {:type, {:u, 4}},            # transaction type
      {:approved, {:bool}},        # approval status
      {:risk_score, {:u, 8}},      # 0-255 risk
      {:merchant_id, {:u, 24}},    # merchant ID
      {:timestamp, {:u, 32}}       # unix timestamp
    ]

    scenarios = [
      {"IoT Sensors", iot_spec, &generate_iot_data/1},
      {"Gaming Events", game_spec, &generate_game_data/1},
      {"Financial Transactions", finance_spec, &generate_finance_data/1}
    ]

    row_counts = [100, 1000, 10000]

    for {name, spec, generator} <- scenarios do
      IO.puts("\n=== #{name} ===")
      
      for count <- row_counts do
        IO.puts("\n--- #{count} rows ---")
        
        rows = generator.(count)
        
        # Benchmark packing
        {pack_time_us, bitpack_binary} = :timer.tc(fn -> 
          Bitpack.pack(rows, spec) 
        end)
        
        {json_time_us, json_binary} = :timer.tc(fn -> 
          Jason.encode!(rows) 
        end)
        
        # Benchmark unpacking
        {unpack_time_us, _} = :timer.tc(fn -> 
          Bitpack.unpack(bitpack_binary, spec) 
        end)
        
        {json_decode_time_us, _} = :timer.tc(fn -> 
          Jason.decode!(json_binary) 
        end)
        
        # Calculate metrics
        bitpack_size = byte_size(bitpack_binary)
        json_size = byte_size(json_binary)
        compression_ratio = (1 - bitpack_size / json_size) * 100
        
        pack_speedup = json_time_us / pack_time_us
        unpack_speedup = json_decode_time_us / unpack_time_us
        
        IO.puts("  Size:")
        IO.puts("    Bitpack: #{format_bytes(bitpack_size)}")
        IO.puts("    JSON:    #{format_bytes(json_size)}")
        IO.puts("    Compression: #{Float.round(compression_ratio, 1)}%")
        
        IO.puts("  Pack time:")
        IO.puts("    Bitpack: #{format_time(pack_time_us)}")
        IO.puts("    JSON:    #{format_time(json_time_us)}")
        IO.puts("    Speedup: #{Float.round(pack_speedup, 1)}x")
        
        IO.puts("  Unpack time:")
        IO.puts("    Bitpack: #{format_time(unpack_time_us)}")
        IO.puts("    JSON:    #{format_time(json_decode_time_us)}")
        IO.puts("    Speedup: #{Float.round(unpack_speedup, 1)}x")
      end
    end
  end

  defp generate_iot_data(count) do
    for i <- 1..count do
      %{
        sensor_id: rem(i, 65536),
        temperature: :rand.uniform(4095) - 2048,  # -2048 to 2047
        humidity: :rand.uniform(101) - 1,
        battery: :rand.uniform(101) - 1,
        active: rem(i, 2) == 0,
        error_flags: :rand.uniform(256) - 1,
        timestamp_offset: :rand.uniform(65536) - 1
      }
    end
  end

  defp generate_game_data(count) do
    for i <- 1..count do
      %{
        player_id: rem(i, 1_000_000),
        action_type: rem(i, 16),
        x_pos: :rand.uniform(4096) - 1,
        y_pos: :rand.uniform(4096) - 1,
        health: :rand.uniform(256) - 1,
        mana: :rand.uniform(256) - 1,
        level: rem(i, 256),
        flags: :rand.uniform(65536) - 1,
        item_id: :rand.uniform(65536) - 1
      }
    end
  end

  defp generate_finance_data(count) do
    for i <- 1..count do
      %{
        account_id: rem(i, 4_294_967_296),
        amount: :rand.uniform(42_000_000),
        currency: rem(i, 256),
        type: rem(i, 16),
        approved: rem(i, 3) != 0,
        risk_score: :rand.uniform(256) - 1,
        merchant_id: rem(i, 16_777_216),
        timestamp: 1_600_000_000 + i * 60
      }
    end
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes}B"
  defp format_bytes(bytes) when bytes < 1024 * 1024 do
    "#{Float.round(bytes / 1024, 1)}KB"
  end
  defp format_bytes(bytes) do
    "#{Float.round(bytes / (1024 * 1024), 1)}MB"
  end

  defp format_time(microseconds) when microseconds < 1000 do
    "#{microseconds}μs"
  end
  defp format_time(microseconds) when microseconds < 1_000_000 do
    "#{Float.round(microseconds / 1000, 1)}ms"
  end
  defp format_time(microseconds) do
    "#{Float.round(microseconds / 1_000_000, 2)}s"
  end
end

BitpackBench.run()
