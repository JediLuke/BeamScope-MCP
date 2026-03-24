# BeamScope MCP

A robust MCP (Model Context Protocol) server for Elixir applications. BeamScope gives AI coding agents access to your running BEAM application through a resilient TCP architecture that survives app restarts.

## Why BeamScope?

BeamScope was built to solve a fundamental problem with HTTP-based MCP servers like TideWave: **when your Elixir app restarts, the connection dies and doesn't reconnect**.

This is particularly painful during development when you're:
- Running `mix compile` after making changes
- Restarting your app to pick up config changes
- Experiencing crashes that trigger supervisor restarts

BeamScope uses a **standalone TCP architecture** where a TypeScript bridge maintains the connection to your AI agent and automatically reconnects when the Elixir app comes back up.

```
Traditional HTTP-based MCP (TideWave):
┌─────────────┐      HTTP       ┌──────────────────────┐
│  AI Agent   │ ──────────────► │  Phoenix Endpoint    │  ← Dies when app restarts
└─────────────┘                 │  (Plug-based MCP)    │
                                └──────────────────────┘

BeamScope Architecture:
┌─────────────┐     stdio      ┌───────────────────┐     TCP      ┌─────────────────┐
│  AI Agent   │ ─────────────► │  TypeScript       │ ──────────►  │  Elixir         │
│             │                │  Bridge           │  reconnects  │  GenServer      │
└─────────────┘                │  (stays running)  │  on restart  │  (BeamScope)    │
                               └───────────────────┘              └─────────────────┘
```

## Design Philosophy

### Generic Elixir/BEAM, Not Framework-Specific

BeamScope works with **any Elixir application**, not just Phoenix. The tools are useful across the entire Elixir ecosystem:

- **`project_eval`** — Evaluate code in your running application
- **`get_logs`** — Retrieve application logs with filtering
- **`get_docs`** — Access local documentation for modules and functions

We intentionally excluded framework-specific tools (Ecto, Ash, Phoenix) to keep BeamScope portable and focused on what every BEAM app has in common.

### No Default Ports — Fail Loudly

BeamScope has **no default port anywhere in the stack**. If the port isn't configured, the app crashes at startup with a clear error message telling you exactly what to add to your config.

This prevents the maddening situation where your Elixir app is listening on one port and the MCP bridge is trying to connect on another. Every port must be explicitly configured in both places.

## Installation

BeamScope MCP has two components: an Elixir library (TCP server + tools) and a TypeScript bridge (MCP protocol). Both run locally — **clone the repo first**, then reference it as a path dependency.

### 1. Clone the repo

```bash
cd ~/your/projects  # or wherever you keep local deps
git clone https://github.com/JediLuke/BeamScope-MCP.git beam_scope_mcp
```

### 2. Add to your Elixir project

Reference the cloned repo as a path dependency:

```elixir
# mix.exs
def deps do
  [
    {:beam_scope_mcp, path: "../beam_scope_mcp", only: :dev}
  ]
end
```

Adjust the path to wherever you cloned it relative to your project.

```bash
mix deps.get
```

### 3. Configure the port (required)

```elixir
# config/config.exs (or config/dev.exs)
config :beam_scope_mcp,
  port: 9995,
  app_name: "MyApp"
```

Optionally allow env var override:

```elixir
# config/runtime.exs
if port = System.get_env("BEAM_SCOPE_MCP_PORT") do
  config :beam_scope_mcp, port: String.to_integer(port)
end
```

### 4. Build the TypeScript bridge

```bash
cd /path/to/beam_scope_mcp
npm install
npm run build
```

### 5. Configure your AI coding agent

Add BeamScope to your project's `.mcp.json`:

```json
{
  "mcpServers": {
    "beam-scope-mcp": {
      "type": "stdio",
      "command": "node",
      "args": ["/absolute/path/to/beam_scope_mcp/dist/index.js"],
      "env": { "BEAM_SCOPE_MCP_PORT": "9995" }
    }
  }
}
```

**Important:** The `BEAM_SCOPE_MCP_PORT` env var must match the port in your Elixir config. If it's missing, the TypeScript bridge will exit immediately with an error.

## Available Tools (20)

### Connection

| Tool | Description |
|------|-------------|
| `connect_beam_scope_mcp` | Establish TCP connection. Port pre-configured via env var. |
| `get_beam_scope_mcp_status` | Check current connection status. |

### Core

| Tool | Description |
|------|-------------|
| `get_logs` | Application logs with tail/grep/level filtering. |
| `project_eval` | Evaluate Elixir code in the running app with timeout. |
| `get_docs` | Local documentation for modules/functions via `Code.fetch_docs/1`. |

### Compilation

| Tool | Description |
|------|-------------|
| `recompile` | Recompile the project from within the BEAM. Returns errors/warnings. |
| `reload_module` | Hot-reload a single module from its source file. Fastest feedback loop. |
| `recompile_deps` | Force recompile dependencies. Args required (e.g. `["--force"]`). |

### System & Process Introspection

| Tool | Description |
|------|-------------|
| `get_system_stats` | Memory, schedulers, process counts, uptime, IO stats. |
| `list_processes` | Filterable/sortable process listing (by name, memory, queue size). |
| `get_process_info` | Detailed info: function, memory, links, monitors, stacktrace. |
| `get_process_state` | Internal state of GenServers via `:sys.get_state/1`. |
| `get_process_dictionary` | Process dictionary metadata (Logger metadata, flags, etc.). |

### Application & OTP

| Tool | Description |
|------|-------------|
| `get_app_config` | Runtime application config (what the BEAM has loaded, not files on disk). |
| `get_supervision_tree` | Recursive OTP supervision tree walk. App name required. |

### ETS

| Tool | Description |
|------|-------------|
| `list_ets_tables` | All ETS tables with size, memory, type, protection, owner. |
| `inspect_ets_table` | Read ETS table contents with row limits and truncation. |

### Code Intelligence

| Tool | Description |
|------|-------------|
| `xref_callers` | Find all callers of a module or function via `mix xref`. Impact analysis before refactoring. |

### Tracing

| Tool | Description |
|------|-------------|
| `trace_calls` | Trace function calls on a module. Writes to file in `/tmp/beam_scope_traces/` — read results with your file reading tools. Auto-stops at call/time limit. |
| `stop_trace` | Emergency stop for any running trace. Safe to call even if no trace is running. |

## Running Multiple Applications

Each application uses a different port:

```elixir
# App 1: config/config.exs
config :beam_scope_mcp, port: 9995

# App 2: config/config.exs
config :beam_scope_mcp, port: 9994
```

Each app's `.mcp.json` passes the matching port via `BEAM_SCOPE_MCP_PORT`.

## Architecture

```
beam_scope_mcp/
├── lib/
│   ├── beam_scope_mcp.ex           # Public API
│   └── beam_scope_mcp/
│       ├── application.ex          # OTP Application (fail-loudly port config)
│       ├── server.ex               # TCP GenServer + command dispatch
│       ├── log_capture.ex          # Logger handler + circular buffer
│       └── tools/
│           ├── logs.ex             # get_logs
│           ├── eval.ex             # project_eval
│           ├── docs.ex             # get_docs
│           ├── recompile.ex        # recompile, reload_module, recompile_deps
│           ├── system_stats.ex     # get_system_stats
│           ├── processes.ex        # list_processes, get_process_info/state/dictionary
│           ├── app_config.ex       # get_app_config
│           ├── supervision_tree.ex # get_supervision_tree
│           ├── ets.ex              # list_ets_tables, inspect_ets_table
│           ├── xref.ex             # xref_callers
│           └── trace.ex            # trace_calls, stop_trace (writes to /tmp/beam_scope_traces/)
├── src/
│   ├── index.ts                    # MCP server entry point
│   ├── connection.ts               # TCP connection (requires BEAM_SCOPE_MCP_PORT env var)
│   └── tools.ts                    # Tool definitions and handlers
└── dist/                           # Compiled TypeScript (gitignored)
```

## Migrating from TideWave

See [MIGRATION_FROM_TIDEWAVE.md](./MIGRATION_FROM_TIDEWAVE.md) for a step-by-step guide.

## License

MIT
