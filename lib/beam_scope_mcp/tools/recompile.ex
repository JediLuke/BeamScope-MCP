defmodule BeamScopeMcp.Tools.Recompile do
  @moduledoc """
  Tool for recompiling the project from within the running BEAM.
  """

  @doc """
  Recompile the project. Returns compilation result including any errors or warnings.
  """
  def recompile(_params) do
    {output, result} = capture_io_and_result(fn ->
      IEx.Helpers.recompile()
    end)

    case result do
      :ok ->
        msg = if output == "", do: "Compilation successful (no changes)", else: output
        {:ok, msg}

      :noop ->
        {:ok, "Nothing to compile (no changes detected)"}

      {:error, _} ->
        {:ok, "Compilation failed:\n\n#{output}"}
    end
  rescue
    e ->
      {:error, "Recompile failed: #{Exception.message(e)}"}
  end

  @doc """
  Recompile dependencies.

  Params:
  - "args" (optional) — list of args, e.g. ["--force"] or ["jason", "--force"]
  """
  def recompile_deps(%{"args" => args}) when is_list(args) and length(args) > 0 do
    {output, _result} = capture_io_and_result(fn ->
      Mix.Task.reenable("deps.compile")
      Mix.Task.run("deps.compile", args)
    end)

    msg = if output == "", do: "Dependencies recompiled successfully", else: output
    {:ok, msg}
  rescue
    e ->
      {:error, "Recompile deps failed: #{Exception.message(e)}"}
  end

  def recompile_deps(_params) do
    {:error, "\"args\" parameter is required. Examples: [\"--force\"] for all deps, [\"jason\", \"--force\"] for a single dep."}
  end

  defp capture_io_and_result(fun) do
    {:ok, pid} = StringIO.open("")
    original_gl = Process.group_leader()
    Process.group_leader(self(), pid)

    try do
      result = fun.()
      {_, content} = StringIO.contents(pid)
      {content, result}
    after
      Process.group_leader(self(), original_gl)
      StringIO.close(pid)
    end
  end
end
