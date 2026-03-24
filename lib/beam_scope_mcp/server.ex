defmodule BeamScopeMcp.Server do
  @moduledoc """
  TCP server that bridges the TypeScript MCP server to Elixir.

  This server listens for JSON commands over TCP and dispatches them to
  the appropriate tool handlers. The connection is persistent - when a
  client disconnects, the server waits for a new connection.

  Architecture:
  MCP Client (Claude/Cursor) -> TypeScript Bridge (stdio) -> TCP -> This Server -> Tools
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    port = Keyword.fetch!(opts, :port)
    app_name = Keyword.get(opts, :app_name, "Elixir App")

    case :gen_tcp.listen(port, [:binary, packet: :line, active: false, reuseaddr: true]) do
      {:ok, listen_socket} ->
        Logger.info("BeamScopeMcp TCP server listening for #{app_name} on port #{port}")

        {:ok, %{listen_socket: listen_socket, port: port, app_name: app_name},
         {:continue, :accept}}

      {:error, :eaddrinuse} ->
        Logger.error("Port #{port} is already in use for #{app_name}!")
        {:stop, :eaddrinuse}

      {:error, reason} ->
        Logger.error("Failed to start TCP server on port #{port}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:accept, %{listen_socket: listen_socket} = state) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        Logger.info("BeamScopeMcp: Client connected")
        {:noreply, Map.put(state, :client, client), {:continue, :recv_loop}}

      {:error, reason} ->
        Logger.error("Failed to accept connection: #{inspect(reason)}")
        {:noreply, state, {:continue, :accept}}
    end
  end

  def handle_continue(:recv_loop, %{client: client} = state) do
    case :gen_tcp.recv(client, 0) do
      {:ok, data} ->
        response = handle_message(String.trim(data))
        json_response = Jason.encode!(response) <> "\n"
        :gen_tcp.send(client, json_response)
        {:noreply, state, {:continue, :recv_loop}}

      {:error, :closed} ->
        Logger.info("BeamScopeMcp: Client disconnected, waiting for reconnection...")
        {:noreply, Map.delete(state, :client), {:continue, :accept}}

      {:error, reason} ->
        Logger.error("Error receiving data: #{inspect(reason)}")
        :gen_tcp.close(client)
        {:noreply, Map.delete(state, :client), {:continue, :accept}}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("BeamScopeMcp.Server received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Handle the "hello" handshake from TypeScript bridge
  defp handle_message("hello") do
    %{status: "ok", message: "Hello from BeamScopeMcp MCP Server", version: "0.1.0"}
  end

  defp handle_message(json_string) do
    case Jason.decode(json_string) do
      {:ok, %{"action" => "status"}} ->
        %{status: "ok", message: "BeamScopeMcp MCP Server is running"}

      {:ok, %{"action" => "get_logs"} = params} ->
        handle_tool_result(BeamScopeMcp.Tools.Logs.get_logs(params))

      {:ok, %{"action" => "project_eval"} = params} ->
        handle_tool_result(BeamScopeMcp.Tools.Eval.project_eval(params))

      {:ok, %{"action" => "get_docs"} = params} ->
        handle_tool_result(BeamScopeMcp.Tools.Docs.get_docs(params))

      {:ok, command} ->
        Logger.warning("BeamScopeMcp received unknown command: #{inspect(command)}")
        %{error: "Unknown command", command: command}

      {:error, _} ->
        Logger.error("BeamScopeMcp received invalid JSON: #{inspect(json_string)}")
        %{error: "Invalid JSON"}
    end
  end

  defp handle_tool_result({:ok, result}) when is_binary(result),
    do: %{status: "ok", result: result}

  defp handle_tool_result({:ok, result}), do: %{status: "ok", result: result}
  defp handle_tool_result({:error, reason}), do: %{error: reason}
end
