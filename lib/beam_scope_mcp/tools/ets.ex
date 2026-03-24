defmodule BeamScopeMcp.Tools.Ets do
  @moduledoc """
  Tools for inspecting ETS tables.
  """

  @doc """
  List all ETS tables with metadata.
  """
  def list_ets_tables(_params) do
    tables =
      :ets.all()
      |> Enum.map(fn tab ->
        info = :ets.info(tab)
        if info do
          %{
            name: Keyword.get(info, :name),
            id: inspect(tab),
            size: Keyword.get(info, :size, 0),
            memory_words: Keyword.get(info, :memory, 0),
            type: Keyword.get(info, :type),
            protection: Keyword.get(info, :protection),
            owner: Keyword.get(info, :owner) |> inspect()
          }
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.memory_words, :desc)

    header = "#{length(tables)} ETS tables (sorted by memory)\n\n"

    rows =
      tables
      |> Enum.map(fn t ->
        mem_bytes = t.memory_words * :erlang.system_info(:wordsize)
        mem_str = format_bytes(mem_bytes)
        "#{t.name} (#{t.id})\n  size: #{t.size} rows | memory: #{mem_str} | type: #{t.type} | protection: #{t.protection} | owner: #{t.owner}"
      end)
      |> Enum.join("\n\n")

    {:ok, header <> rows}
  end

  @doc """
  Inspect contents of an ETS table.

  Params:
  - "table" (required) — table name as string (e.g. "my_table")
  - "limit" (optional) — max rows to return (default: 20)
  """
  def inspect_ets_table(params) do
    limit = Map.get(params, "limit", 20)

    case params do
      %{"table" => table_name} when is_binary(table_name) ->
        tab = String.to_atom(table_name)

        case safe_ets_info(tab) do
          nil ->
            {:error, "ETS table :#{table_name} not found. Use list_ets_tables to see available tables."}

          info ->
            total_size = Keyword.get(info, :size, 0)

            rows =
              try do
                :ets.tab2list(tab)
                |> Enum.take(limit)
                |> Enum.map(fn row -> inspect(row, pretty: true, limit: 30) end)
              catch
                :error, :badarg -> ["(access denied — table may be private)"]
              end

            shown = length(rows)
            header = "Table :#{table_name} — #{shown} of #{total_size} rows\n\n"
            body = Enum.join(rows, "\n\n")

            truncated =
              if shown < total_size,
                do: "\n\n(truncated — #{total_size - shown} more rows. Use limit parameter to see more.)",
                else: ""

            {:ok, header <> body <> truncated}
        end

      _ ->
        {:error, "\"table\" parameter is required (e.g. \"my_cache\")"}
    end
  end

  defp safe_ets_info(tab) do
    try do
      :ets.info(tab)
    catch
      :error, :badarg -> nil
    end
  end

  defp format_bytes(bytes) when bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 2)} MB"
  defp format_bytes(bytes) when bytes >= 1024,
    do: "#{Float.round(bytes / 1024, 2)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"
end
