defmodule BeamScopeMcp do
  @moduledoc """
  BeamScopeMcp - A robust MCP server for Elixir applications.

  Unlike TideWave which uses HTTP transport through Phoenix, BeamScopeMcp uses
  a persistent TCP connection that survives app restarts. The TypeScript
  bridge maintains the connection to your AI coding agent and automatically
  reconnects when your Elixir app restarts.

  ## Tools

  - `get_logs` - Retrieve application logs with filtering
  - `project_eval` - Evaluate Elixir code in the application context
  - `get_docs` - Get documentation for modules/functions
  - `search_package_docs` - Search Hex documentation

  ## Installation

  Add to your application's dependencies:

      {:beam_scope_mcp, path: "../beam_scope"}

  Configure the port (REQUIRED — no default):

      config :beam_scope_mcp,
        port: 9995,
        app_name: "MyApp"

  The server starts automatically with your application.

  ## Usage with Claude Code / Cursor / etc

  Configure your MCP client to use the TypeScript bridge:

      {
        "mcpServers": {
          "beam-scope": {
            "command": "node",
            "args": ["/path/to/beam_scope_mcp/dist/index.js"],
            "env": { "BEAM_SCOPE_MCP_PORT": "9995" }
          }
        }
      }
  """

  @doc """
  Clears all captured logs from the buffer.

  Useful when you want subsequent log retrievals to only contain fresh logs.
  """
  def clear_logs do
    BeamScopeMcp.LogCapture.clear_logs()
  end
end
