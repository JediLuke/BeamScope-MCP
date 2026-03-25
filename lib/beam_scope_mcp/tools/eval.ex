defmodule BeamScopeMcp.Tools.Eval do
  @moduledoc """
  Tool for evaluating Elixir code in the application context.
  """

  @default_timeout 30_000
  @default_inspect_opts [charlists: :as_lists, limit: 50, pretty: true]

  @doc """
  Evaluate Elixir code.

  Expected params:
  - "code" (required) - Elixir code string to evaluate
  - "timeout" (optional) - max execution time in ms, defaults to 30000
  """
  def project_eval(params) do
    case params do
      %{"code" => code} when is_binary(code) ->
        timeout = Map.get(params, "timeout", @default_timeout)
        eval_code(code, timeout)

      _ ->
        {:error, "Missing required parameter: code (string)"}
    end
  end

  defp eval_code(code, timeout) do
    parent = self()

    {pid, ref} =
      spawn_monitor(fn ->
        # Set metadata to avoid capturing our own logs
        Logger.metadata(beam_scope_mcp: true)
        result = eval_with_captured_io(code)
        send(parent, {:result, result})
      end)

    receive do
      {:result, result} ->
        Process.demonitor(ref, [:flush])
        {:ok, result}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, "Process exited: #{Exception.format_exit(reason)}"}
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        Process.exit(pid, :kill)
        {:error, "Evaluation timed out after #{timeout}ms"}
    end
  end

  defp eval_with_captured_io(code) do
    {{success?, result}, io} =
      capture_io(fn ->
        try do
          # Use with_diagnostics to capture compiler warnings/errors as data.
          # Without this, compile errors go to :standard_error and are invisible.
          {eval_result, diagnostics} = Code.with_diagnostics(fn ->
            Code.eval_string(code, [], env())
          end)

          case diagnostics do
            [] ->
              {result, _bindings} = eval_result
              {true, result}
            diags ->
              {result, _bindings} = eval_result
              diag_text = Enum.map_join(diags, "\n", fn d ->
                pos = case d.position do
                  {line, col} -> "#{line}:#{col}"
                  line when is_integer(line) -> "#{line}"
                  other -> inspect(other)
                end
                "#{d.severity}: #{d.message} (#{d.file}:#{pos})"
              end)
              IO.puts(diag_text)
              {true, result}
          end
        catch
          kind, reason ->
            # Also try to capture diagnostics from failed compilation
            {false, Exception.format(kind, reason, __STACKTRACE__)}
        end
      end)

    case {success?, io} do
      {true, ""} ->
        inspect(result, @default_inspect_opts)

      {true, io} ->
        "IO:\n\n#{io}\n\nResult:\n\n#{inspect(result, @default_inspect_opts)}"

      {false, ""} ->
        result

      {false, io} ->
        "IO:\n\n#{io}\n\nError:\n\n#{result}"
    end
  end

  # Evaluation environment with IEx helpers available
  defp env do
    import IEx.Helpers, warn: false
    __ENV__
  end

  defp capture_io(fun) do
    {:ok, pid} = StringIO.open("")
    original_gl = Process.group_leader()
    Process.group_leader(self(), pid)

    try do
      result = fun.()
      {_, content} = StringIO.contents(pid)
      {result, content}
    after
      Process.group_leader(self(), original_gl)
      StringIO.close(pid)
    end
  end
end
