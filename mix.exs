defmodule ExLogdrain.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_logdrain,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    base = [extra_applications: [:logger]]

    if Mix.env() != :test do
      base ++ [mod: {ExLogdrain.Application, []}]
    else
      base
    end
  end

  defp deps do
    [
      {:bandit, "~> 1.11.1"},
      {:duckdbex, "~> 0.4.1"}
    ]
  end
end
