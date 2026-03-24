# BeamScope MCP Roadmap

## Implemented

### Phase 1: Observer-Like Introspection Tools ✅

- **`get_system_stats`** — Memory, schedulers, process counts, uptime, IO stats via `:erlang.memory/0`, `:erlang.system_info/1`, `:erlang.statistics/1`
- **`list_processes`** — Filterable/sortable process listing (by name, memory, message queue size)
- **`get_process_info`** — Detailed info for a specific process (function, memory, links, monitors, stacktrace)
- **`get_process_state`** — `:sys.get_state/1` for GenServers and OTP processes
- **`get_process_dictionary`** — Read process dictionary metadata (Logger metadata, custom flags, etc.)

### Phase 2: Compilation & Config Tools ✅

- **`recompile`** — Recompile project from within the BEAM via `IEx.Helpers.recompile/0`
- **`recompile_deps`** — Force recompile dependencies via `Mix.Task.run("deps.compile", args)`. Args required (no defaults).
- **`get_app_config`** — Runtime application config (what the BEAM actually has loaded, not what's on disk). App name required.

### Phase 3: Advanced Introspection (partial) ✅

- **`get_supervision_tree`** — Recursive walk of OTP supervision tree. App name required (no guessing).
- **`list_ets_tables`** — All ETS tables with size, memory, type, protection, owner
- **`inspect_ets_table`** — Read ETS table contents with row limit and truncation notice

### Tracing ✅

- **`trace_calls`** — Trace function calls on a module via `:dbg`. Writes to file in `/tmp/beam_scope_traces/` — agent reads results with normal file tools. Auto-stops at call/time limit. max_calls and max_seconds required (capped at 200/30).
- **`stop_trace`** — Abort a running trace early. Not normally needed — traces auto-clean-up.

### Core Tools (from initial release) ✅

- **`connect_beam_scope_mcp`** — Establish TCP connection (port from env var, no defaults)
- **`get_beam_scope_mcp_status`** — Connection status check
- **`get_logs`** — Application logs with tail/grep/level filtering
- **`project_eval`** — Evaluate Elixir code in the running app with timeout
- **`get_docs`** — Local documentation for modules/functions via `Code.fetch_docs/1`

### Hot Code Loading ✅

- **`reload_module`** — Hot-reload a single module from its source file via `Code.compile_file/1`. Fastest feedback loop — change one file, reload just that module, test immediately. No full recompile needed.

**Total: 19 tools implemented**

---

## Not Yet Implemented

### Phase 2 remaining

#### `stop_app` / `start_app`

Stop and start the host application. Separate tools rather than a single `restart_app` — gives agents more control.

- `stop_app` — `Application.stop(:my_app)`
- `start_app` — `Application.ensure_all_started(:my_app)`

**Important for tool descriptions:** These tools incur delay while the app stops/starts (potentially several seconds depending on supervision tree complexity). The tool description must warn the LLM about this so it knows to expect a pause and doesn't assume the connection is broken.

Also: stopping the app will likely kill the TCP connection. The TypeScript bridge will auto-reconnect, but the agent needs to know it may need to call `connect_beam_scope_mcp` again after a restart.

### Phase 3 remaining

#### `get_message_queue` (maybe)

Read the message queue for a specific process. Uses `Process.info(pid, :messages)`.

**Warning:** Message queues can be enormous — must limit/truncate output. Might not justify a dedicated tool since `get_process_info` already returns `:message_queue_len` (so the agent knows *if* there's a backlog) and `project_eval` can do `Process.info(pid, :messages)` for one-off inspection. Keep as a candidate but don't prioritise.

### Phase 4: Code Intelligence

These may overlap with what coding agents already do via file reading and static analysis, but having them available from the running BEAM gives access to compiled metadata that isn't easily derived from source files alone.

#### `get_module_info`

Return metadata about a compiled module. Uses `Module.info/1` or `:erlang.module_info/1` — exports, attributes, compile options, source file path, etc.

#### `get_type_info`

Surface Dialyzer or type information for modules/functions. Especially relevant as newer Elixir versions (1.17+) are adding more type-based features — gradual typing, type inference, compile-time type warnings.

Implementation TBD — may need to read `.beam` debug info chunks or integrate with Dialyzer PLT files.

#### `xref_callers`

Find all callers of a given function across the project. Uses `Mix.Tasks.Xref` — equivalent to `mix xref callers Module.function/arity`.

Useful for impact analysis: "what breaks if I change this function?"

#### Dialyzer integration (musing)

Run Dialyzer analysis from within the BEAM and surface type warnings/errors. Could wrap `Mix.Task.run("dialyzer")` or interact with PLT files directly. Potentially very useful for LLMs to catch type errors, but Dialyzer is slow and can be noisy. Might work better as a "run and write results to file" pattern like trace_calls.

#### Credo integration (musing)

Run Credo analysis and return style/consistency warnings. Similar consideration — could wrap `Mix.Task.run("credo")` and return results. Arguably less useful than Dialyzer since LLMs already have good instincts about code style, and Credo's opinions don't always align with what the user wants.

Both of these fall under the general principle: any tool that improves code intelligence and leverages the running BEAM has an argument for living in BeamScope. Whether they're worth dedicated tools vs just using `project_eval` to run the mix tasks is an open question.

---

## Considered and Rejected

### IEx.pry / Breakpoints

IEx.pry and breakpoints are **blocking and interactive by nature** — they halt the target process and wait for terminal input. This is fundamentally incompatible with MCP:

- The process halts, waiting for user input that never comes (the LLM has no terminal)
- Eventually times out or hangs indefinitely
- If an agent called `project_eval` with code containing `IEx.pry`, it would deadlock

The right alternative is the non-blocking tools above: `get_process_state`, `get_process_dictionary`, and `trace_calls` provide the same debugging visibility without halting anything.

---

## Design Principles

### No Default Ports — Fail Loudly

Every port must be explicitly configured. No guessing, no fallbacks. If the port isn't set, the app crashes with a clear error message.

### No Default Identifiers — Require Specificity

Tools that operate on apps, processes, or tables require the caller to specify exactly what they want. No "default to the host app" or "guess the first supervisor". If the agent doesn't know what to ask for, the error message tells it how to find out.

### Safety & Guardrails

- **Timeouts everywhere** — `project_eval` already has one. Any tool that executes code or waits for results needs a timeout.
- **Memory limits** — `project_eval` could potentially allocate unbounded memory. Consider capping inspect output size.
- **Auto-stop for tracing** — `trace_calls` must always auto-stop after n calls or n seconds. No open-ended traces.
- **Disconnection warnings** — `stop_app`/`start_app` will kill the TCP connection. Tool descriptions must warn the LLM to expect a pause and reconnect.
- **Row/size limits on large data** — `inspect_ets_table`, `get_message_queue`, `list_processes` can all return enormous results. Sensible limits with options to narrow down: filters, match patterns, limit/offset.
- **Truncation with notice** — when output is truncated, always tell the LLM it was truncated and how much was omitted, so it knows to refine its query rather than assume it has the full picture.

---

## Additional Ideas & Notes

### Hot code loading ✅ (implemented as `reload_module`)

Moved to implemented. Uses `Code.compile_file/1` to compile and load a single module.

### Ideas considered but deprioritised

- **Port discovery tool** — The tool descriptions already guide the LLM to look in the Elixir config files. A discovery tool would just be doing what the instructions already say.
- **Config diffing** (runtime vs files on disk) — Theoretically useful but config drift rarely happens in practice.
- **Registry/PubSub inspection** — `Registry.select/2` etc. Could be useful for some apps, but too framework-specific for core BeamScope. Can always be done via `project_eval`.

### Architectural note

As the tool count grows, `server.ex`'s dispatch function will get long. Consider a tool registry pattern where each tool module registers itself, rather than a growing case statement. Not urgent at 16 tools, worth thinking about at 20+.
