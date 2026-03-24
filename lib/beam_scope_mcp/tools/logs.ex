defmodule BeamScopeMcp.Tools.Logs do
  @moduledoc """
  Tool for retrieving application logs.
  """

  @doc """
  Get logs from the circular buffer.

  Expected params:
  - "tail" (required) - number of log entries to return
  - "grep" (optional) - regex pattern to filter logs
  - "level" (optional) - filter by log level
  """
  def get_logs(params) do
    case params do
      %{"tail" => n} when is_integer(n) ->
        opts =
          [grep: Map.get(params, "grep"), level: Map.get(params, "level")]
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)

        logs = BeamScopeMcp.LogCapture.get_logs(n, opts)
        {:ok, Enum.join(logs, "")}

      _ ->
        {:error, "Missing required parameter: tail (integer)"}
    end
  end
end
