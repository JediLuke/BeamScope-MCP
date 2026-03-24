defmodule BeamScopeMcp.Application do
  @moduledoc false
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    port =
      case Application.get_env(:beam_scope_mcp, :port) do
        nil ->
          raise """
          BeamScopeMcp port not configured!

          Set it in your project's config:

              config :beam_scope_mcp, port: 9995

          Or in config/runtime.exs via environment variable:

              if port = System.get_env("BEAM_SCOPE_MCP_PORT") do
                config :beam_scope_mcp, port: String.to_integer(port)
              end
          """

        port ->
          port
      end

    app_name = Application.get_env(:beam_scope_mcp, :app_name, "Elixir App")

    # Add our logger handler
    add_logger_handler()

    children = [
      # Log capture with circular buffer
      BeamScopeMcp.LogCapture,
      # TCP server
      {BeamScopeMcp.Server, port: port, app_name: app_name}
    ]

    opts = [strategy: :one_for_one, name: BeamScopeMcp.Supervisor]
    result = Supervisor.start_link(children, opts)

    case result do
      {:ok, pid} ->
        Logger.info("BeamScopeMcp MCP server started on port #{port}")
        {:ok, pid}

      {:error, {:shutdown, {:failed_to_start_child, BeamScopeMcp.Server, {:shutdown, :eaddrinuse}}}} ->
        Logger.error("Port #{port} is already in use!")
        {:error, :port_in_use}

      {:error, reason} ->
        Logger.error("Failed to start BeamScopeMcp: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp add_logger_handler do
    :logger.add_handler(
      BeamScopeMcp.LogCapture,
      BeamScopeMcp.LogCapture,
      %{formatter: Logger.default_formatter(colors: [enabled: false])}
    )
  end
end
