defmodule Bitpack.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/angelorange/bitpack"

  def project do
    [
      app: :bitpack,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [
        main_module: Bitpack.CLI,
        name: "bitpack"
      ],

      # Hex package configuration
      package: package(),
      description: description(),

      # Documentation
      name: "Bitpack",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  # defp elixirc_paths(:test), do: ["lib", "test/support"]
  # defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type "mix help deps" for examples and options.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.0", only: :test},
      {:benchee, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.31", only: [:dev, :docs], runtime: false}
    ]
  end

  defp description do
    """
    Bitpack is a high-performance bit-level packer for rows/events with small fields.
    Includes BPX (Binary Payload eXchange) for automatic compression with integrity verification.
    Perfect for IoT, gaming, telemetry, and any scenario requiring compact binary serialization.
    """
  end

  defp package do
    [
      name: "bitpack",
      files: ~w(lib examples .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      maintainers: ["Angelo Rangeira"]
    ]
  end

  defp docs do
    [
      main: "readme",
      name: "Bitpack",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        Core: [Bitpack],
        BPX: [BPX],
        CLI: [Bitpack.CLI, BPX.CLI]
      ]
    ]
  end
end
