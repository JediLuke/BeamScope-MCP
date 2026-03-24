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
