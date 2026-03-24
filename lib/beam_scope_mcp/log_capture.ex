defmodule BeamScopeMcp.LogCapture do
  @moduledoc """
  Captures logs into a circular buffer for retrieval via the get_logs tool.

  This module serves as both a GenServer (for state management) and an
  Erlang logger handler (for intercepting log messages).
  """
  use GenServer

  @buffer_size 1024

  @levels Map.new(~w[emergency alert critical error warning notice info debug]a, &{"#{&1}", &1})

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @doc """
  Get the last `n` log entries, optionally filtered.

  Options:
  - `:grep` - Regex pattern to filter logs (case insensitive)
  - `:level` - Filter by log level (e.g., "error", "warning")
  """
  def get_logs(n, opts \\ []) do
    grep = Keyword.get(opts, :grep)
    regex = grep && Regex.compile!(grep, "iu")
    level = Keyword.get(opts, :level)
    level_atom = level && Map.fetch!(@levels, level)
    GenServer.call(__MODULE__, {:get_logs, n, regex, level_atom})
  end

  @doc """
  Clear all captured logs.
  """
  def clear_logs do
    GenServer.call(__MODULE__, :clear_logs)
  end

  # ============================================================================
  # Erlang Logger Handler Callback
  # ============================================================================

  @doc false
  def log(%{meta: meta, level: level} = event, config) do
    # Skip logs from beam_scope itself to avoid noise
    if meta[:beam_scope_mcp] do
      :ok
    else
      %{formatter: {formatter_mod, formatter_config}} = config
      chardata = formatter_mod.format(event, formatter_config)
      GenServer.cast(__MODULE__, {:log, level, IO.chardata_to_string(chardata)})
    end
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_) do
    {:ok, %{buffer: CircularBuffer.new(@buffer_size)}}
  end

  @impl true
  def handle_cast({:log, level, message}, state) do
    buffer = CircularBuffer.insert(state.buffer, {level, message})
    {:noreply, %{state | buffer: buffer}}
  end

  @impl true
  def handle_call({:get_logs, n, regex, level_filter}, _from, state) do
    logs = CircularBuffer.to_list(state.buffer)

    logs =
      if level_filter do
        Stream.filter(logs, fn {level, _message} -> level == level_filter end)
      else
        logs
      end

    logs =
      if regex do
        Stream.filter(logs, fn {_level, message} -> Regex.match?(regex, message) end)
      else
        logs
      end

    messages = Stream.map(logs, &elem(&1, 1))
    {:reply, Enum.take(messages, -n), state}
  end

  def handle_call(:clear_logs, _from, state) do
    {:reply, :ok, %{state | buffer: CircularBuffer.new(@buffer_size)}}
  end
end
