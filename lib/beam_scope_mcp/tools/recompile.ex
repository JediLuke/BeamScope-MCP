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

  @doc """
  Hot-reload a single module from its source file.

  Compiles the file and loads the resulting module(s) into the running BEAM
  without recompiling the whole project. Fastest possible feedback loop for
  single-file changes.

  Params:
  - "file" (required) — path to the .ex or .exs file to reload
  """
  def reload_module(%{"file" => file_path}) when is_binary(file_path) do
    if not File.exists?(file_path) do
      {:error, "File not found: #{file_path}"}
    else
      {output, result} = capture_io_and_result(fn ->
        try do
          modules = Code.compile_file(file_path)

          module_names =
            modules
            |> Enum.map(fn {mod, _bytecode} ->
              mod |> Atom.to_string() |> String.replace("Elixir.", "")
            end)

          {:ok, module_names}
        rescue
          e -> {:error, Exception.format(:error, e, __STACKTRACE__)}
        end
      end)

      case result do
        {:ok, module_names} ->
          names = Enum.join(module_names, ", ")
          msg = "Reloaded #{length(module_names)} module(s): #{names}"
          msg = if output != "", do: msg <> "\n\nOutput:\n#{output}", else: msg
          {:ok, msg}

        {:error, error_msg} ->
          {:ok, "Reload failed:\n\n#{error_msg}\n\n#{output}"}
      end
    end
  end

  def reload_module(_params) do
    {:error, "\"file\" parameter is required — the full path to the .ex or .exs file to reload (e.g. \"lib/my_app/my_module.ex\")"}
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
