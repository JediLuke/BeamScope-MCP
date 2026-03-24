defmodule BeamScopeMcp.Tools.Docs do
  @moduledoc """
  Tools for retrieving documentation.
  """

  @doc """
  Get documentation for a module or function.

  Expected params:
  - "reference" (required) - Module, Module.function, or Module.function/arity
  """
  def get_docs(params) do
    case params do
      %{"reference" => ref} ->
        {ref, lookup} =
          case ref do
            "c:" <> rest -> {rest, [:callback]}
            _ -> {ref, [:function, :macro]}
          end

        case parse_reference(ref) do
          {:ok, mod, fun, arity} ->
            case Code.ensure_loaded(mod) do
              {:module, _} ->
                find_docs_for_mfa(mod, fun, arity, lookup)

              {:error, reason} ->
                {:error, "Could not load module #{inspect(mod)}: #{reason}"}
            end

          :error ->
            {:error, "Failed to parse reference: #{inspect(ref)}"}
        end

      _ ->
        {:error, "Missing required parameter: reference"}
    end
  end

  # Parse a reference string like "String.split/2" or "GenServer"
  defp parse_reference(string) when is_binary(string) do
    case Code.string_to_quoted(string) do
      {:ok, ast} -> parse_reference_ast(ast)
      {:error, _} -> :error
    end
  end

  defp parse_reference_ast({:/, _, [call, arity]}) when arity in 0..255 do
    parse_call(call, arity)
  end

  defp parse_reference_ast(call) do
    parse_call(call, :*)
  end

  defp parse_call({{:., _, [mod, fun]}, _, _}, arity) do
    parse_module(mod, fun, arity)
  end

  defp parse_call(mod, :*) do
    parse_module(mod, nil, :*)
  end

  defp parse_call(_mod, _arity), do: :error

  defp parse_module(mod, fun, arity) when is_atom(mod) do
    {:ok, mod, fun, arity}
  end

  defp parse_module({:__aliases__, _, [head | _] = parts}, fun, arity) when is_atom(head) do
    {:ok, Module.concat(parts), fun, arity}
  end

  defp parse_module(_mod, _fun, _arity), do: :error

  # Find documentation for a module (no function specified)
  defp find_docs_for_mfa(mod, nil, :*, _lookup) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _ann, _, "text/markdown", %{"en" => content}, _, _} ->
        {:ok, "# #{inspect(mod)}\n\n#{content}"}

      {:docs_v1, _, _, _, _, _, _} ->
        {:error, "Documentation not found for #{inspect(mod)}"}

      _ ->
        {:error, "No documentation available for #{inspect(mod)}"}
    end
  end

  # Find documentation for a specific function
  defp find_docs_for_mfa(mod, fun, arity, lookup) do
    docs = get_function_docs(mod, lookup)
    filtered = filter_function_docs(docs, fun, arity)

    case filtered do
      [] ->
        {:error, "Documentation not found for #{inspect(mod)}.#{fun}/#{arity}"}

      docs ->
        formatted =
          docs
          |> Enum.map(fn {{type, fun, arity}, _ann, signature, doc, metadata} ->
            format_function_docs(type, mod, fun, arity, signature, doc, metadata)
          end)
          |> Enum.join("\n\n")

        {:ok, formatted}
    end
  end

  defp get_function_docs(mod, kinds) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, "text/markdown", _, _, docs} ->
        for {{kind, _, _}, _, _, _, _} = doc <- docs, kind in kinds, do: doc

      {:error, _} ->
        []
    end
  end

  defp filter_function_docs(docs, fun, arity) when is_integer(arity) do
    doc =
      Enum.find(docs, &match?({{_, ^fun, ^arity}, _, _, _, _}, &1)) ||
        find_doc_defaults(docs, fun, arity)

    case doc do
      {_, _, _, %{"en" => _}, _} -> [doc]
      _ -> []
    end
  end

  defp filter_function_docs(docs, fun, :*) do
    Enum.filter(docs, fn
      {{_, ^fun, _}, _, _, %{"en" => _}, _} -> true
      _ -> false
    end)
  end

  defp find_doc_defaults(docs, function, min) do
    Enum.find(docs, fn
      {{_, ^function, arity}, _, _, _, %{defaults: defaults}} when arity > min ->
        arity <= min + defaults

      _ ->
        false
    end)
  end

  defp format_function_docs(type, mod, fun, arity, signature, %{"en" => content}, _metadata) do
    prefix = if type == :callback, do: "c:", else: ""

    """
    # #{prefix}#{inspect(mod)}.#{fun}/#{arity}

    ```elixir
    #{Enum.join(signature, "\n")}
    ```

    #{content}\
    """
  end
end
