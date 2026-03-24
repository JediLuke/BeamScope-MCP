defmodule BeamScopeMcp.Tools.Xref do
  @moduledoc """
  Tools for cross-reference analysis — find callers/dependencies of modules and functions.
  """

  @doc """
  Find all callers of a module or function across the project.

  Params:
  - "reference" (required) — module or Module.function/arity (e.g. "Merlinex.Core.Manager" or "Enum.map/2")
  """
  def xref_callers(%{"reference" => reference}) when is_binary(reference) do
    {output, _result} = capture_io(fn ->
      Mix.Task.reenable("xref")
      Mix.Task.run("xref", ["callers", reference])
    end)

    if output == "" do
      {:ok, "No callers found for #{reference}"}
    else
      {:ok, "Callers of #{reference}:\n\n#{output}"}
    end
  rescue
    e ->
      {:error, "xref callers failed: #{Exception.message(e)}"}
  end

  def xref_callers(_params) do
    {:error, "\"reference\" parameter is required (e.g. \"Merlinex.Core.Manager\" or \"Enum.map/2\")"}
  end

  defp capture_io(fun) do
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
