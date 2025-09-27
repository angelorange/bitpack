defmodule Bitpack.MixProject do
  use Mix.Project

  def project do
    [
      app: :bitpack,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [
        main_module: Bitpack.CLI,
        name: "bitpack"
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type "mix help deps" for examples and options.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:stream_data, "~> 1.0", only: :test},
      {:benchee, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
end
