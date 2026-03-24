defmodule BeamScopeMcp.Tools.SystemStats do
  @moduledoc """
  Tool for retrieving BEAM runtime metrics and memory usage.
  """

  @doc """
  Get system stats including memory, schedulers, process counts, and runtime info.
  """
  def get_system_stats(_params) do
    memory = :erlang.memory()
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    {reductions, _} = :erlang.statistics(:reductions)
    {{:input, input_bytes}, {:output, output_bytes}} = :erlang.statistics(:io)

    stats = %{
      memory: %{
        total: format_bytes(memory[:total]),
        processes: format_bytes(memory[:processes]),
        atoms: format_bytes(memory[:atom]),
        binary: format_bytes(memory[:binary]),
        ets: format_bytes(memory[:ets]),
        code: format_bytes(memory[:code]),
        system: format_bytes(memory[:system])
      },
      system: %{
        otp_release: List.to_string(:erlang.system_info(:otp_release)),
        elixir_version: System.version(),
        schedulers: :erlang.system_info(:schedulers),
        schedulers_online: :erlang.system_info(:schedulers_online),
        process_count: :erlang.system_info(:process_count),
        process_limit: :erlang.system_info(:process_limit),
        port_count: :erlang.system_info(:port_count),
        atom_count: :erlang.system_info(:atom_count),
        atom_limit: :erlang.system_info(:atom_limit)
      },
      runtime: %{
        uptime: format_uptime(uptime_ms),
        reductions: reductions,
        io_input: format_bytes(input_bytes),
        io_output: format_bytes(output_bytes)
      }
    }

    {:ok, format_stats(stats)}
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 2)} GB"
  defp format_bytes(bytes) when bytes >= 1_048_576,
    do: "#{Float.round(bytes / 1_048_576, 2)} MB"
  defp format_bytes(bytes) when bytes >= 1024,
    do: "#{Float.round(bytes / 1024, 2)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"

  defp format_uptime(ms) do
    seconds = div(ms, 1000)
    minutes = div(seconds, 60)
    hours = div(minutes, 60)
    days = div(hours, 24)

    cond do
      days > 0 -> "#{days}d #{rem(hours, 24)}h #{rem(minutes, 60)}m"
      hours > 0 -> "#{hours}h #{rem(minutes, 60)}m #{rem(seconds, 60)}s"
      minutes > 0 -> "#{minutes}m #{rem(seconds, 60)}s"
      true -> "#{seconds}s"
    end
  end

  defp format_stats(stats) do
    """
    ## Memory
    Total: #{stats.memory.total}
    Processes: #{stats.memory.processes}
    Atoms: #{stats.memory.atoms}
    Binary: #{stats.memory.binary}
    ETS: #{stats.memory.ets}
    Code: #{stats.memory.code}
    System: #{stats.memory.system}

    ## System
    OTP: #{stats.system.otp_release} | Elixir: #{stats.system.elixir_version}
    Schedulers: #{stats.system.schedulers_online}/#{stats.system.schedulers}
    Processes: #{stats.system.process_count}/#{stats.system.process_limit}
    Ports: #{stats.system.port_count}
    Atoms: #{stats.system.atom_count}/#{stats.system.atom_limit}

    ## Runtime
    Uptime: #{stats.runtime.uptime}
    Reductions: #{stats.runtime.reductions}
    IO In: #{stats.runtime.io_input} | Out: #{stats.runtime.io_output}
    """
  end
end
