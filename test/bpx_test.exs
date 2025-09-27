defmodule BPXTest do
  use ExUnit.Case, async: true

  test "round-trip with no compression" do
    data = "Hello, World!"
    envelope = BPX.wrap_auto(data, algos: [:none])
    
    assert {:ok, ^data, meta} = BPX.unwrap(envelope)
    assert meta.algorithm == :none
    assert meta.original_size == byte_size(data)
    assert meta.compressed_size == byte_size(data)
    assert meta.compression_ratio == 0.0
  end

  test "round-trip with deflate compression" do
    # Dados repetitivos que comprimem bem
    data = String.duplicate("ABCDEFGH", 100)
    envelope = BPX.wrap_auto(data, algos: [:deflate], min_gain: 1)
    
    assert {:ok, ^data, meta} = BPX.unwrap(envelope)
    assert meta.algorithm == :deflate
    assert meta.original_size == byte_size(data)
    assert meta.compressed_size < byte_size(data)
    assert meta.compression_ratio > 0.0
  end

  test "chooses best compression algorithm" do
    # Dados que comprimem bem
    data = String.duplicate("Test data for compression", 50)
    
    envelope = BPX.wrap_auto(data, algos: [:deflate], min_gain: 1)
    {:ok, _, meta} = BPX.unwrap(envelope)
    
    # Deve ter escolhido deflate por comprimir melhor que :none
    assert meta.algorithm == :deflate
    assert meta.compression_ratio > 0.0
  end

  test "falls back to no compression when min_gain not met" do
    # Dados pequenos que não comprimem bem
    data = "small"
    envelope = BPX.wrap_auto(data, algos: [:deflate], min_gain: 100)
    
    assert {:ok, ^data, meta} = BPX.unwrap(envelope)
    assert meta.algorithm == :none
    assert meta.compression_ratio == 0.0
  end

  test "validates CRC32 on unwrap" do
    data = "Test data"
    envelope = BPX.wrap_auto(data)
    
    # Corrompe apenas o payload, mantendo o tamanho correto no header
    <<header::binary-size(16), payload::binary>> = envelope
    corrupted_payload = String.duplicate("X", byte_size(payload))
    corrupted = <<header::binary, corrupted_payload::binary>>
    
    assert {:error, reason} = BPX.unwrap(corrupted)
    assert reason =~ "CRC32 mismatch"
  end

  test "validates size on unwrap" do
    data = "Test data"
    envelope = BPX.wrap_auto(data)
    
    # Corrompe o tamanho no header
    <<"BPX", 1, alg, _orig_size::32-big, comp_size::32-big, crc::32-big, payload::binary>> = envelope
    wrong_size = <<
      "BPX"::binary, 1::8, alg::8, 
      999::32-big, comp_size::32-big, crc::32-big, 
      payload::binary
    >>
    
    assert {:error, reason} = BPX.unwrap(wrong_size)
    assert reason =~ "size mismatch"
  end

  test "rejects invalid magic" do
    data = "Test"
    envelope = BPX.wrap_auto(data)
    
    # Corrompe o magic
    <<"BPX", rest::binary>> = envelope
    invalid = <<"XXX", rest::binary>>
    
    assert {:error, "invalid BPX envelope"} = BPX.unwrap(invalid)
  end

  test "rejects unsupported version" do
    data = "Test"
    envelope = BPX.wrap_auto(data)
    
    # Muda a versão
    <<"BPX", _version, rest::binary>> = envelope
    future_version = <<"BPX", 99, rest::binary>>
    
    assert {:error, "unsupported version: 99"} = BPX.unwrap(future_version)
  end

  test "rejects unknown algorithm" do
    data = "Test"
    envelope = BPX.wrap_auto(data)
    
    # Muda o algoritmo para um ID inválido
    <<"BPX", version, _alg, rest::binary>> = envelope
    unknown_alg = <<"BPX", version, 99, rest::binary>>
    
    assert {:error, reason} = BPX.unwrap(unknown_alg)
    assert reason =~ "unknown algorithm: 99"
  end

  test "inspect_envelope returns metadata without decompressing" do
    data = String.duplicate("compress me", 20)
    envelope = BPX.wrap_auto(data, algos: [:deflate], min_gain: 1)
    
    assert {:ok, info} = BPX.inspect_envelope(envelope)
    assert info.algorithm == :deflate
    assert info.original_size == byte_size(data)
    assert info.compressed_size < byte_size(data)
    assert info.compression_ratio > 0.0
    assert info.envelope_size == byte_size(envelope)
  end

  test "available_algorithms includes at least none and deflate" do
    algos = BPX.available_algorithms()
    
    assert :none in algos
    assert :deflate in algos
    assert is_list(algos)
  end

  test "handles empty data" do
    data = ""
    envelope = BPX.wrap_auto(data)
    
    assert {:ok, ^data, meta} = BPX.unwrap(envelope)
    assert meta.algorithm == :none
    assert meta.original_size == 0
  end

  test "handles large data efficiently" do
    # 1MB de dados repetitivos
    data = String.duplicate("Large data chunk for testing compression efficiency", 20_000)
    envelope = BPX.wrap_auto(data, algos: [:deflate], min_gain: 1000)
    
    assert {:ok, ^data, meta} = BPX.unwrap(envelope)
    assert meta.algorithm == :deflate
    assert meta.compression_ratio > 0.8  # Deve comprimir muito bem
  end

  test "preserves binary data integrity" do
    # Dados binários com todos os bytes possíveis
    data = for i <- 0..255, into: <<>>, do: <<i>>
    envelope = BPX.wrap_auto(data)
    
    assert {:ok, ^data, _meta} = BPX.unwrap(envelope)
  end

  test "multiple algorithms selection" do
    data = String.duplicate("Test compression with multiple algorithms", 30)
    
    # Testa com múltiplos algoritmos disponíveis
    available_algos = BPX.available_algorithms() -- [:none]
    envelope = BPX.wrap_auto(data, algos: available_algos, min_gain: 1)
    
    assert {:ok, ^data, meta} = BPX.unwrap(envelope)
    assert meta.algorithm in available_algos
    assert meta.compression_ratio > 0.0
  end
end
