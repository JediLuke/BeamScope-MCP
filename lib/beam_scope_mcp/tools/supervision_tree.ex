defmodule BeamScopeMcp.Tools.SupervisionTree do
  @moduledoc """
  Tool for inspecting the OTP supervision tree.
  """

  @doc """
  Get the supervision tree for an application.

  Params:
  - "app" (optional) — application name, defaults to the host app (first non-system app found)
  - "depth" (optional) — max recursion depth (default: 10)
  """
  def get_supervision_tree(params) do
    depth = Map.get(params, "depth", 10)

    case params do
      %{"app" => app} when is_binary(app) ->
        case resolve_supervisor(app) do
          {:ok, sup_pid, app_name} ->
            tree = walk_tree(sup_pid, 0, depth)
            header = "Supervision tree for :#{app_name} (#{inspect(sup_pid)})\n\n"
            {:ok, header <> format_tree(tree, 0)}

          {:error, reason} ->
            {:error, reason}
        end

      _ ->
        {:error, "\"app\" parameter is required (e.g. \"merlinex\", \"phoenix\"). Use get_app_config or project_eval with Application.started_applications() to find app names."}
    end
  end

  defp resolve_supervisor(app_string) when is_binary(app_string) do
    app = String.to_atom(app_string)

    case Process.whereis(:"#{app |> to_string() |> Macro.camelize()}.Supervisor") do
      nil ->
        # Try common patterns
        candidates = [
          :"Elixir.#{app |> to_string() |> Macro.camelize()}.Supervisor",
          :"#{app}_sup",
          app
        ]

        case Enum.find_value(candidates, fn name ->
          case Process.whereis(name) do
            nil -> nil
            pid -> {:ok, pid}
          end
        end) do
          {:ok, pid} -> {:ok, pid, app}
          nil -> {:error, "Could not find supervisor for :#{app}. Try providing a registered supervisor name."}
        end

      pid ->
        {:ok, pid, app}
    end
  end

  defp walk_tree(pid, current_depth, max_depth) when current_depth >= max_depth do
    %{pid: pid, name: process_name(pid), type: :max_depth_reached, children: []}
  end

  defp walk_tree(pid, current_depth, max_depth) do
    name = process_name(pid)

    case catch_which_children(pid) do
      {:ok, children} ->
        child_nodes =
          children
          |> Enum.map(fn {id, child_pid, type, _modules} ->
            if is_pid(child_pid) and type == :supervisor do
              walk_tree(child_pid, current_depth + 1, max_depth)
              |> Map.put(:id, id)
            else
              %{
                pid: child_pid,
                id: id,
                name: if(is_pid(child_pid), do: process_name(child_pid), else: :undefined),
                type: type,
                children: []
              }
            end
          end)

        counts = catch_count_children(pid)

        %{
          pid: pid,
          name: name,
          type: :supervisor,
          counts: counts,
          children: child_nodes
        }

      :not_supervisor ->
        %{pid: pid, name: name, type: :worker, children: []}
    end
  end

  defp catch_which_children(pid) do
    try do
      {:ok, Supervisor.which_children(pid)}
    catch
      :exit, _ -> :not_supervisor
    end
  end

  defp catch_count_children(pid) do
    try do
      Supervisor.count_children(pid)
    catch
      :exit, _ -> []
    end
  end

  defp process_name(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, []} -> nil
      {:registered_name, name} -> name
      nil -> nil
    end
  end

  defp process_name(_), do: nil

  defp format_tree(node, indent) do
    prefix = String.duplicate("  ", indent)
    pid_str = if is_pid(node.pid), do: inspect(node.pid), else: ":undefined"
    name_str = if node.name, do: " (#{node.name})", else: ""
    id_str = if node[:id], do: " [#{node[:id]}]", else: ""
    type_str = "#{node.type}"

    counts_str = case node[:counts] do
      counts when is_list(counts) and length(counts) > 0 ->
        workers = Keyword.get(counts, :workers, 0)
        supervisors = Keyword.get(counts, :supervisors, 0)
        " — #{workers} workers, #{supervisors} supervisors"
      _ -> ""
    end

    line = "#{prefix}#{type_str}: #{pid_str}#{name_str}#{id_str}#{counts_str}\n"

    children_str =
      node.children
      |> Enum.map(&format_tree(&1, indent + 1))
      |> Enum.join("")

    line <> children_str
  end
end
