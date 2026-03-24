defmodule BeamScopeMcp.Tools.Trace do
  @moduledoc """
  Lightweight function call tracing via :dbg.

  Writes trace events to a file rather than returning them directly,
  since traces are temporal (collected over time) and can be large.
  The agent reads the file afterwards with its normal file reading tools.
  """

  require Logger

  @trace_dir "/tmp/beam_scope_traces"
  @max_calls_cap 200
  @max_seconds_cap 30

  @doc """
  Start tracing calls to a module/function.

  Params:
  - "module" (required) — module name as string (e.g. "Merlinex.Core.Manager")
  - "function" (optional) — function name, omit for all functions in module
  - "max_calls" (required) — stop after this many calls (max #{@max_calls_cap})
  - "max_seconds" (required) — stop after this many seconds (max #{@max_seconds_cap})
  """
  def trace_calls(params) do
    with {:ok, module} <- parse_module(params["module"]),
         {:ok, function} <- parse_function(params["function"]),
         {:ok, max_calls} <- parse_max_calls(params["max_calls"]),
         {:ok, max_seconds} <- parse_max_seconds(params["max_seconds"]) do
      start_trace(module, function, max_calls, max_seconds)
    end
  end

  defp parse_module(nil),
    do: {:error, "\"module\" parameter is required (e.g. \"Merlinex.Core.Manager\")"}
  defp parse_module(mod_string) when is_binary(mod_string) do
    module =
      if String.starts_with?(mod_string, "Elixir.") do
        String.to_atom(mod_string)
      else
        String.to_atom("Elixir." <> mod_string)
      end

    case Code.ensure_loaded(module) do
      {:module, _} -> {:ok, module}
      {:error, _} -> {:error, "Module #{mod_string} not found or not loaded"}
    end
  end
  defp parse_module(_), do: {:error, "\"module\" must be a string"}

  defp parse_function(nil), do: {:ok, nil}
  defp parse_function(fun_string) when is_binary(fun_string),
    do: {:ok, String.to_atom(fun_string)}
  defp parse_function(_), do: {:error, "\"function\" must be a string"}

  defp parse_max_calls(nil),
    do: {:error, "\"max_calls\" parameter is required (e.g. 50). Maximum: #{@max_calls_cap}"}
  defp parse_max_calls(n) when is_integer(n) and n > 0,
    do: {:ok, min(n, @max_calls_cap)}
  defp parse_max_calls(_),
    do: {:error, "\"max_calls\" must be a positive integer. Maximum: #{@max_calls_cap}"}

  defp parse_max_seconds(nil),
    do: {:error, "\"max_seconds\" parameter is required (e.g. 10). Maximum: #{@max_seconds_cap}"}
  defp parse_max_seconds(n) when is_integer(n) and n > 0,
    do: {:ok, min(n, @max_seconds_cap)}
  defp parse_max_seconds(_),
    do: {:error, "\"max_seconds\" must be a positive integer. Maximum: #{@max_seconds_cap}"}

  defp start_trace(module, function, max_calls, max_seconds) do
    File.mkdir_p!(@trace_dir)

    mod_short = module |> Atom.to_string() |> String.replace("Elixir.", "")
    fun_suffix = if function, do: ".#{function}", else: ""
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
    filename = "#{mod_short}#{fun_suffix}_#{timestamp}.log"
    filepath = Path.join(@trace_dir, filename)

    # Start the trace in a supervised task
    parent = self()

    spawn(fn ->
      try do
        run_trace(module, function, max_calls, max_seconds, filepath, parent)
      rescue
        e ->
          File.write!(filepath, "Trace error: #{Exception.message(e)}\n", [:append])
          send(parent, {:trace_done, filepath, {:error, Exception.message(e)}})
      end
    end)

    # Wait briefly for the trace to start (or fail immediately)
    receive do
      {:trace_started, ^filepath} ->
        {:ok, """
        Trace started. Results will be written to:
        #{filepath}

        Tracing: #{mod_short}#{fun_suffix}
        Limits: #{max_calls} calls or #{max_seconds} seconds (whichever comes first)

        The trace is running in the background. Read the file to see results.
        The file will contain a summary line when tracing completes.\
        """}

      {:trace_done, ^filepath, {:error, reason}} ->
        {:error, "Trace failed to start: #{reason}"}
    after
      2000 ->
        {:ok, """
        Trace starting (may take a moment). Results will be written to:
        #{filepath}

        Tracing: #{mod_short}#{fun_suffix}
        Limits: #{max_calls} calls or #{max_seconds} seconds\
        """}
    end
  end

  defp run_trace(module, function, max_calls, max_seconds, filepath, parent) do
    # Write header
    mod_short = module |> Atom.to_string() |> String.replace("Elixir.", "")
    fun_str = if function, do: ".#{function}", else: " (all functions)"
    header = """
    # BeamScope Trace: #{mod_short}#{fun_str}
    # Started: #{DateTime.utc_now() |> DateTime.to_string()}
    # Limits: #{max_calls} calls, #{max_seconds} seconds
    #
    """
    File.write!(filepath, header)

    # Set up counter
    call_count = :counters.new(1, [:atomics])

    # Set up dbg tracer that writes to file
    :dbg.tracer(:process, {fn msg, _state ->
      count = :counters.get(call_count, 1) + 1
      :counters.put(call_count, 1, count)

      line = format_trace_event(msg, count)
      File.write!(filepath, line, [:append])

      if count >= max_calls do
        # Signal we've hit the limit
        File.write!(filepath, "\n# Stopped: reached #{max_calls} call limit\n", [:append])
        :dbg.stop_clear()
      end

      count
    end, 0})

    # Set trace pattern with match spec that includes return values
    match_spec = [{:_, [], [{:return_trace}]}]

    if function do
      :dbg.tp(module, function, match_spec)
    else
      :dbg.tpl(module, match_spec)
    end

    # Trace all processes
    :dbg.p(:all, [:call, :timestamp])

    send(parent, {:trace_started, filepath})

    # Wait for timeout
    Process.sleep(max_seconds * 1000)

    # Clean up
    final_count = :counters.get(call_count, 1)
    :dbg.stop_clear()

    File.write!(filepath, "\n# Stopped: reached #{max_seconds} second time limit (#{final_count} calls captured)\n", [:append])
  rescue
    e ->
      :dbg.stop_clear()
      File.write!(filepath, "\n# Error: #{Exception.message(e)}\n", [:append])
  end

  @doc """
  Stop any running trace immediately. Safety net in case a trace needs to be aborted.
  """
  def stop_trace(_params) do
    :dbg.stop_clear()
    {:ok, "All traces stopped and cleaned up."}
  rescue
    _ -> {:ok, "No active traces to stop."}
  end

  defp format_trace_event({:trace_ts, pid, :call, {mod, fun, args}, timestamp}, count) do
    time = format_timestamp(timestamp)
    mod_short = mod |> Atom.to_string() |> String.replace("Elixir.", "")
    args_str = args |> Enum.map(&inspect(&1, limit: 20, pretty: false)) |> Enum.join(", ")
    pid_str = inspect(pid)

    "[#{time}] ##{count} #{pid_str} #{mod_short}.#{fun}(#{args_str})\n"
  end

  defp format_trace_event({:trace_ts, pid, :return_from, {mod, fun, arity}, result, timestamp}, count) do
    time = format_timestamp(timestamp)
    mod_short = mod |> Atom.to_string() |> String.replace("Elixir.", "")
    result_str = inspect(result, limit: 20, pretty: false)
    pid_str = inspect(pid)

    "[#{time}] ##{count} #{pid_str} #{mod_short}.#{fun}/#{arity} => #{result_str}\n"
  end

  defp format_trace_event(msg, count) do
    "[?] ##{count} #{inspect(msg, limit: 30)}\n"
  end

  defp format_timestamp({mega, sec, micro}) do
    total_seconds = mega * 1_000_000 + sec
    {:ok, dt} = DateTime.from_unix(total_seconds)
    ms = div(micro, 1000)
    Calendar.strftime(dt, "%H:%M:%S") <> ".#{String.pad_leading("#{ms}", 3, "0")}"
  end
end
