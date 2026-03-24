defmodule BeamScopeMcp.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :beam_scope_mcp,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "A robust MCP server for Elixir applications with reconnection support"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {BeamScopeMcp.Application, []}
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:circular_buffer, "~> 0.4"}
    ]
  end
end
