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

### 1. Add to your Elixir project

```elixir
# mix.exs
def deps do
  [
    {:beam_scope_mcp, path: "../beam_scope_mcp", only: :dev}
  ]
end
```

```bash
mix deps.get
```

### 2. Configure the port (required)

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

### 3. Build the TypeScript bridge

```bash
cd /path/to/beam_scope_mcp
npm install
npm run build
```

### 4. Configure your AI coding agent

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

## Available Tools

### `connect_beam_scope_mcp`
Establish connection to the Elixir app. The port is pre-configured via environment variable — no parameters needed.

### `get_beam_scope_mcp_status`
Check current connection status.

### `get_logs`
Retrieve application logs with optional filtering.
```json
{
  "tail": 50,
  "grep": "error",
  "level": "error"
}
```

### `project_eval`
Evaluate Elixir code in your running application.
```json
{
  "code": "Enum.map([1,2,3], & &1 * 2)",
  "timeout": 30000
}
```

### `get_docs`
Get local documentation for a module or function.
```json
{ "reference": "String.split/2" }
```

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
│       ├── server.ex               # TCP GenServer
│       ├── log_capture.ex          # Logger handler + circular buffer
│       └── tools/
│           ├── logs.ex             # get_logs implementation
│           ├── eval.ex             # project_eval implementation
│           └── docs.ex             # get_docs implementation
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
