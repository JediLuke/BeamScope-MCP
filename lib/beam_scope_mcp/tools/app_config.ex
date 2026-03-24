defmodule BeamScopeMcp.Tools.AppConfig do
  @moduledoc """
  Tool for retrieving runtime application configuration.
  """

  @doc """
  Get runtime application config.

  Params:
  - "app" (required) — application name as string
  - "key" (optional) — specific config key, omit for all config
  """
  def get_app_config(params) do
    case params do
      %{"app" => app_string} when is_binary(app_string) ->
        app = String.to_atom(app_string)
        key = params["key"]

        result =
          if key do
            key_atom = String.to_atom(key)
            case Application.fetch_env(app, key_atom) do
              {:ok, value} ->
                "config :#{app}, #{key}: #{inspect(value, pretty: true, limit: 100)}"
              :error ->
                "No config found for :#{app}, :#{key}"
            end
          else
            case Application.get_all_env(app) do
              [] ->
                "No config found for :#{app} (application may not be loaded)"
              env ->
                env
                |> Enum.map(fn {k, v} ->
                  "  #{k}: #{inspect(v, pretty: true, limit: 50)}"
                end)
                |> then(fn lines ->
                  "config :#{app}\n#{Enum.join(lines, "\n")}"
                end)
            end
          end

        {:ok, result}

      _ ->
        {:error, "\"app\" parameter is required (e.g. \"merlinex\", \"phoenix\")"}
    end
  end
end
