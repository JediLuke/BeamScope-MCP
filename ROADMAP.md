# BeamScope MCP Roadmap

## Phase 1: Observer-Like Introspection Tools

These tools leverage the BEAM's exceptional introspection capabilities and would be valuable for any Elixir application.

### `get_system_stats`

Runtime metrics and memory usage. Calls into:
- `:erlang.memory/0` — per-type memory breakdown (total, processes, atoms, binary, ets, etc.)
- `:erlang.system_info/1` — schedulers, process count, port count, atom count
- `:erlang.statistics/1` — uptime, reductions, IO, garbage collection stats

Goal: return a useful snapshot of the BEAM's state so we can understand system health at a glance.

### `list_processes`

List running processes with filtering options. Filter by:
- Registered name
- Module (current function's module)
- Message queue size (e.g. find processes with large mailboxes)

Uses:
- `Process.list/0`
- `Process.info(pid, [:registered_name, :current_function, :message_queue_len, :memory, :status])`

### `get_process_info`

Detailed information about a specific process.

Uses `Process.info(pid)` with useful keys:
- `:registered_name`
- `:current_function`
- `:initial_call`
- `:message_queue_len`
- `:memory`
- `:status`
- `:links`
- `:monitors`
- `:trap_exit`
- `:reductions`

### `get_process_state`

Get the internal state of any GenServer/process.

Uses `:sys.get_state/1` — works on any process that implements the system message protocol (GenServer, gen_statem, etc.).

Accepts a PID or registered name.

---

## Phase 2: Compilation Tools

Fast feedback loop for AI agents — recompile without leaving the BEAM.

### `recompile`

Recompile the current project from within the running app.

Implementation options:
- `IEx.Helpers.recompile/0`
- `Mix.Task.run("compile")` directly

Must report compilation errors and warnings back to the LLM. This gives agents a tight edit-compile-check loop without needing to shell out to `mix compile`.

### `recompile_deps`

Force recompile of dependencies.

Uses `Mix.Task.run("deps.compile", args)` where args can include:
- `["--force"]` — recompile all deps
- `["jason", "--force"]` — recompile a single dependency

### `stop_app` / `start_app`

Stop and start the host application. Separate tools rather than a single `restart_app` — gives agents more control.

- `stop_app` — `Application.stop(:my_app)`
- `start_app` — `Application.ensure_all_started(:my_app)`

**Important for tool descriptions:** These tools incur delay while the app stops/starts (potentially several seconds depending on supervision tree complexity). The tool description must warn the LLM about this so it knows to expect a pause and doesn't assume the connection is broken.

Also: stopping the app will likely kill the TCP connection. The TypeScript bridge will auto-reconnect, but the agent needs to know it may need to call `connect_beam_scope_mcp` again after a restart.

### `get_app_config`

Retrieve runtime application config. Unlike reading config files on disk, this returns what the BEAM actually has loaded — including runtime.exs overrides, env var substitutions, and any dynamic `Application.put_env` changes.

Uses `Application.get_all_env(:app)` or `Application.get_env(:app, :key)`.

Accepts:
- `app` (required) — the application name
- `key` (optional) — specific config key, omit for all config

---

## Phase 3: Advanced Introspection

### `list_ets_tables`

List all ETS tables with metadata.

Uses `:ets.all/0` to get table IDs, then `:ets.info/1` for each to return name, size, memory, type, owner, protection level, etc.

### `get_process_dictionary`

Read the process dictionary for a specific process. Complements `get_process_state` (which uses `:sys.get_state`) — the process dictionary often contains metadata that state doesn't show (Logger metadata, custom flags, step context, etc.).

Uses `Process.info(pid, :dictionary)`.

### `inspect_ets_table`

Read contents of an ETS table. For small tables use `:ets.tab2list/1`. For large tables support match patterns via `:ets.match/2` or `:ets.match_object/2` to avoid dumping the entire table.

Accepts:
- `table` (required) — table name or ID
- `match_pattern` (optional) — Erlang match spec to filter results
- `limit` (optional) — max rows to return

### `get_supervision_tree`

Recursively walk the supervision tree from an application's top supervisor. Shows the full hierarchy of supervisors and workers with their PIDs, restart strategies, and status.

Likely uses `Supervisor.which_children/1` recursively — for each child that is itself a supervisor, descend and fetch its children too. Could also pull `Supervisor.count_children/1` for summary stats at each level.

Accepts:
- `app` (optional) — application name, defaults to the host app
- `depth` (optional) — max recursion depth

### `trace_calls`

Lightweight function call tracing using `:dbg` (modern OTP) or `:recon_trace`.

Available `:dbg` functions: `:dbg.tracer/0`, `:dbg.p/2`, `:dbg.tp/2` — use these to trace calls to specific modules/functions, capture arguments and return values, and optionally measure timing.

Accepts:
- `module` (required) — module to trace
- `function` (optional) — specific function, omit for all functions in module
- `max_calls` (optional) — stop after n calls (safety limit)
- `max_seconds` (optional) — auto-stop after n seconds (safety limit)

**Design considerations:**
- Must be time-limited — auto-stop after n seconds or m calls, whichever comes first
- Output captured and returned as a batch, not streamed
- Be careful with high-traffic functions — a busy GenServer could generate thousands of trace events per second
- Always clean up traces on completion (`:dbg.stop_clear/0`)
- Consider a default cap (e.g. 100 calls, 10 seconds) to prevent accidental overload

### `get_message_queue` (maybe)

Read the message queue for a specific process. Uses `Process.info(pid, :messages)`.

**Warning:** Message queues can be enormous — must limit/truncate output. Might not justify a dedicated tool since `get_process_info` already returns `:message_queue_len` (so the agent knows *if* there's a backlog) and `project_eval` can do `Process.info(pid, :messages)` for one-off inspection. Keep as a candidate but don't prioritise.

---

## Considered and Rejected

### IEx.pry / Breakpoints

IEx.pry and breakpoints are **blocking and interactive by nature** — they halt the target process and wait for terminal input. This is fundamentally incompatible with MCP:

- The process halts, waiting for user input that never comes (the LLM has no terminal)
- Eventually times out or hangs indefinitely
- If an agent called `project_eval` with code containing `IEx.pry`, it would deadlock

The right alternative is the non-blocking tools above: `get_process_state`, `get_process_dictionary`, and `trace_calls` provide the same debugging visibility without halting anything.

---

## Phase 4: Code Intelligence

These may overlap with what coding agents already do via file reading and static analysis, but having them available from the running BEAM gives access to compiled metadata that isn't easily derived from source files alone.

### `get_module_info`

Return metadata about a compiled module. Uses `Module.info/1` or `:erlang.module_info/1` — exports, attributes, compile options, source file path, etc.

### `get_type_info`

Surface Dialyzer or type information for modules/functions. Especially relevant as newer Elixir versions (1.17+) are adding more type-based features — gradual typing, type inference, compile-time type warnings.

Implementation TBD — may need to read `.beam` debug info chunks or integrate with Dialyzer PLT files.

### `xref_callers`

Find all callers of a given function across the project. Uses `Mix.Tasks.Xref` — equivalent to `mix xref callers Module.function/arity`.

Useful for impact analysis: "what breaks if I change this function?"

---

## Safety & Guardrails

Some tools can return massive data or have side effects. General principles:

- **Timeouts everywhere** — `project_eval` already has one. Any tool that executes code or waits for results needs a timeout.
- **Memory limits** — `project_eval` could potentially allocate unbounded memory. Consider capping inspect output size.
- **Auto-stop for tracing** — `trace_calls` must always auto-stop after n calls or n seconds. No open-ended traces.
- **Disconnection warnings** — `stop_app`/`start_app` will kill the TCP connection. Tool descriptions must warn the LLM to expect a pause and reconnect.
- **Row/size limits on large data** — `inspect_ets_table`, `get_message_queue`, `list_processes` can all return enormous results. Default to sensible limits (e.g. 100 rows) and give the LLM options to narrow down: filters, match patterns, limit/offset.
- **Truncation with notice** — when output is truncated, always tell the LLM it was truncated and how much was omitted, so it knows to refine its query rather than assume it has the full picture.

---

## Additional Ideas & Notes

### Hot code loading (candidate for Phase 2)

Reload a single compiled module without recompiling the whole project. `Code.compile_file/1` + `Code.load_file/1`. Faster than full recompile for single-file iteration.

### Ideas considered but deprioritised

- **Port discovery tool** — Cool idea, but the tool descriptions already guide the LLM to look in the Elixir config files. Once you know the port you're there, and a discovery tool would just be doing what the instructions already say.
- **Config diffing** (runtime vs files on disk) — Theoretically useful but config drift rarely happens in practice. Not worth a dedicated tool.
- **Registry/PubSub inspection** — `Registry.select/2` etc. Could be useful for some apps, but too framework-specific for core BeamScope. Can always be done via `project_eval`.

### Architectural note

As the tool count grows, `server.ex`'s dispatch function will get long. Consider a tool registry pattern where each tool module registers itself, rather than a growing case statement. Not urgent at 5 tools, worth thinking about at 20+.
