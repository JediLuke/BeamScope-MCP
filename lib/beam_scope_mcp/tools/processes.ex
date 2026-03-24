defmodule BeamScopeMcp.Tools.Processes do
  @moduledoc """
  Tools for listing and inspecting BEAM processes.
  """

  @default_limit 50
  @process_info_keys [:registered_name, :current_function, :message_queue_len, :memory, :status]

  @doc """
  List running processes with optional filtering.

  Params:
  - "limit" (optional, default 50) — max processes to return
  - "sort_by" (optional) — "memory", "message_queue_len", or "reductions"
  - "min_message_queue" (optional) — only show processes with at least this many messages
  - "name_filter" (optional) — filter by registered name (substring match)
  """
  def list_processes(params) do
    limit = Map.get(params, "limit", @default_limit)
    sort_by = Map.get(params, "sort_by")
    min_mq = Map.get(params, "min_message_queue", 0)
    name_filter = Map.get(params, "name_filter")

    processes =
      Process.list()
      |> Enum.map(fn pid ->
        info = Process.info(pid, @process_info_keys)
        if info, do: {pid, Map.new(info)}, else: nil
      end)
      |> Enum.reject(&is_nil/1)
      |> maybe_filter_by_name(name_filter)
      |> maybe_filter_by_mq(min_mq)
      |> maybe_sort(sort_by)
      |> Enum.take(limit)

    total = length(Process.list())
    shown = length(processes)

    header = "Showing #{shown} of #{total} processes\n\n"

    rows =
      processes
      |> Enum.map(fn {pid, info} ->
        name = case info[:registered_name] do
          [] -> inspect(pid)
          name -> "#{name} (#{inspect(pid)})"
        end

        {mod, fun, arity} = info[:current_function] || {:unknown, :unknown, 0}
        mq = info[:message_queue_len] || 0
        mem = info[:memory] || 0

        "#{name}\n  function: #{mod}.#{fun}/#{arity}\n  memory: #{mem} B | queue: #{mq} | status: #{info[:status]}"
      end)
      |> Enum.join("\n\n")

    truncated = if shown < total, do: "\n\n(truncated — use limit, sort_by, or filters to narrow)", else: ""

    {:ok, header <> rows <> truncated}
  end

  @doc """
  Get detailed info about a specific process.

  Params:
  - "pid" (required) — PID string like "<0.123.0>" or registered name
  """
  def get_process_info(params) do
    case resolve_pid(params["pid"]) do
      {:ok, pid} ->
        keys = [
          :registered_name, :current_function, :initial_call,
          :message_queue_len, :memory, :status, :links, :monitors,
          :trap_exit, :reductions, :current_stacktrace
        ]

        case Process.info(pid, keys) do
          nil ->
            {:error, "Process #{inspect(pid)} is not alive"}

          info ->
            formatted = format_process_info(pid, Map.new(info))
            {:ok, formatted}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the internal state of a GenServer/process.

  Params:
  - "pid" (required) — PID string or registered name
  - "timeout" (optional, default 5000) — timeout in ms
  """
  def get_process_state(params) do
    timeout = Map.get(params, "timeout", 5000)

    case resolve_pid(params["pid"]) do
      {:ok, pid} ->
        try do
          state = :sys.get_state(pid, timeout)
          {:ok, inspect(state, pretty: true, limit: 50)}
        catch
          :exit, {:timeout, _} ->
            {:error, "Timeout getting state — process may not support :sys protocol or is busy"}
          :exit, reason ->
            {:error, "Failed to get state: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Get the process dictionary for a specific process.

  Params:
  - "pid" (required) — PID string or registered name
  """
  def get_process_dictionary(params) do
    case resolve_pid(params["pid"]) do
      {:ok, pid} ->
        case Process.info(pid, :dictionary) do
          {:dictionary, dict} ->
            formatted =
              dict
              |> Enum.map(fn {k, v} ->
                "#{inspect(k)}: #{inspect(v, pretty: true, limit: 30)}"
              end)
              |> Enum.join("\n\n")

            if formatted == "" do
              {:ok, "Process dictionary is empty"}
            else
              {:ok, "Process dictionary (#{length(dict)} entries):\n\n#{formatted}"}
            end

          nil ->
            {:error, "Process #{inspect(pid)} is not alive"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── Helpers ──

  defp resolve_pid(nil), do: {:error, "\"pid\" parameter is required"}

  defp resolve_pid(pid_string) when is_binary(pid_string) do
    # Try as registered name first
    case pid_string |> String.to_atom() |> Process.whereis() do
      nil ->
        # Try parsing as PID string like "<0.123.0>" or "0.123.0"
        try do
          cleaned = pid_string |> String.trim_leading("<") |> String.trim_trailing(">")
          pid = :erlang.list_to_pid(~c"<#{cleaned}>")
          if Process.alive?(pid), do: {:ok, pid}, else: {:error, "Process #{pid_string} is not alive"}
        rescue
          _ -> {:error, "Could not resolve \"#{pid_string}\" — use a PID like \"<0.123.0>\" or a registered name"}
        end

      pid ->
        {:ok, pid}
    end
  end

  defp resolve_pid(_), do: {:error, "\"pid\" must be a string"}

  defp maybe_filter_by_name(processes, nil), do: processes
  defp maybe_filter_by_name(processes, filter) do
    filter_down = String.downcase(filter)
    Enum.filter(processes, fn {_pid, info} ->
      case info[:registered_name] do
        [] -> false
        name -> name |> Atom.to_string() |> String.downcase() |> String.contains?(filter_down)
      end
    end)
  end

  defp maybe_filter_by_mq(processes, 0), do: processes
  defp maybe_filter_by_mq(processes, min) do
    Enum.filter(processes, fn {_pid, info} ->
      (info[:message_queue_len] || 0) >= min
    end)
  end

  defp maybe_sort(processes, nil), do: processes
  defp maybe_sort(processes, "memory"),
    do: Enum.sort_by(processes, fn {_, info} -> info[:memory] || 0 end, :desc)
  defp maybe_sort(processes, "message_queue_len"),
    do: Enum.sort_by(processes, fn {_, info} -> info[:message_queue_len] || 0 end, :desc)
  defp maybe_sort(processes, "reductions") do
    Enum.sort_by(processes, fn {pid, _} ->
      case Process.info(pid, [:reductions]) do
        [{:reductions, r}] -> r
        _ -> 0
      end
    end, :desc)
  end
  defp maybe_sort(processes, _), do: processes

  defp format_process_info(pid, info) do
    name = case info[:registered_name] do
      [] -> "unregistered"
      name -> Atom.to_string(name)
    end

    {mod, fun, arity} = info[:current_function] || {:unknown, :unknown, 0}
    {i_mod, i_fun, i_arity} = info[:initial_call] || {:unknown, :unknown, 0}

    stacktrace = case info[:current_stacktrace] do
      entries when is_list(entries) and length(entries) > 0 ->
        entries
        |> Enum.map(fn {m, f, a, loc} ->
          file = Keyword.get(loc, :file, ~c"?") |> List.to_string()
          line = Keyword.get(loc, :line, 0)
          "    #{m}.#{f}/#{a} (#{file}:#{line})"
        end)
        |> Enum.join("\n")
      _ -> "    (none)"
    end

    """
    Process: #{inspect(pid)}
    Name: #{name}
    Status: #{info[:status]}
    Current: #{mod}.#{fun}/#{arity}
    Initial: #{i_mod}.#{i_fun}/#{i_arity}
    Memory: #{info[:memory]} B
    Message Queue: #{info[:message_queue_len]}
    Reductions: #{info[:reductions]}
    Trap Exit: #{info[:trap_exit]}
    Links: #{inspect(info[:links])}
    Monitors: #{inspect(info[:monitors])}

    Stacktrace:
    #{stacktrace}
    """
  end
end
