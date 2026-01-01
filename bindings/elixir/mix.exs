defmodule Liquidz.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/pepicrft/liquidz"

  def project do
    [
      app: :liquidz,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_targets: ["all"],
      make_clean: ["clean"],
      package: package(),
      description: description(),
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    "High-performance Liquid template engine for Elixir, powered by Zig."
  end

  defp package do
    [
      name: "liquidz",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib c_src Makefile mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
