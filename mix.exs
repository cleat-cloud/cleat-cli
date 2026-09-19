defmodule Cleat.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :cleat_cli,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      escript: escript(),
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp escript do
    [
      main_module: Cleat.CLI,
      name: "cleat"
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.16", only: :test}
    ]
  end

  defp aliases do
    [
      install: ["cleat.install"],
      precommit: [
        "compile --warnings-as-errors",
        "format",
        "test"
      ]
    ]
  end
end
