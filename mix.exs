defmodule Bitpack.MixProject do
  use Mix.Project

  def project do
    [
      app: :bitpack,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.32", only: :dev, runtime: false},
      {:stream_data, "~> 0.6", only: :test},
      {:benchee, "~> 1.3", only: :dev},
      {:dialyxir, "~> 1.4", only: :dev, runtime: false},
      {:jason, "~> 1.4", only: [:dev, :test]}
    ]
  end

  defp escript do
    [main_module: Bitpack.CLI]
  end
end
