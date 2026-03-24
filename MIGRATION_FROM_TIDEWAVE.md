# Migrating from TideWave to BeamScope MCP

## Overview

BeamScope MCP is a drop-in replacement for TideWave that provides better reliability through persistent TCP connections. Unlike TideWave (which uses HTTP transport through Phoenix), BeamScope uses a standalone TCP server that survives app restarts — the TypeScript bridge automatically reconnects when your Elixir app comes back up.

## Why Switch?

| Issue with TideWave | BeamScope Solution |
|---------------------|-------------------|
| Connection dies when app restarts | TCP bridge auto-reconnects |
| Requires Phoenix (Bandit/Plug) | Works with any Elixir app |
| HTTP transport through your web stack | Standalone TCP server on dedicated port |
| Default ports silently conflict | No defaults — fail loudly if misconfigured |

## Migration Steps

### 1. Update Dependencies

**Remove TideWave and Bandit from `mix.exs`:**

```elixir
# Remove these:
{:tidewave, "~> 0.1", only: :dev},
{:bandit, "~> 1.0", only: :dev},
```

**Add BeamScope:**

```elixir
# Add this:
{:beam_scope_mcp, path: "../beam_scope_mcp", only: :dev}
```

Then run:
```bash
mix deps.clean tidewave bandit
mix deps.get
```

### 2. Remove TideWave Startup Code

If you were manually starting TideWave with Bandit in your application module, remove it:

```elixir
# Remove this from your application's children:
{Bandit, plug: Tidewave, port: 4114}
```

BeamScope starts automatically via its OTP application — no manual setup needed.

### 3. Remove TideWave Plug from Endpoint

If you had TideWave as a plug in your Phoenix endpoint, remove it:

```elixir
# Remove this block from your endpoint:
if Mix.env() == :dev do
  plug Tidewave
end
```

### 4. Configure BeamScope Port (Required)

BeamScope has **no default port**. You must configure it explicitly:

```elixir
# config/config.exs (or config/dev.exs)
config :beam_scope_mcp,
  port: 9995,
  app_name: "MyApp"
```

Optionally support env var override:

```elixir
# config/runtime.exs
if port = System.get_env("BEAM_SCOPE_MCP_PORT") do
  config :beam_scope_mcp, port: String.to_integer(port)
end
```

### 5. Update MCP Client Configuration

**Before (TideWave):**
```json
{
  "mcpServers": {
    "tidewave": {
      "type": "http",
      "url": "http://localhost:4000/tidewave/mcp"
    }
  }
}
```

**After (BeamScope):**
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

### 6. Build the TypeScript Bridge

```bash
cd /path/to/beam_scope_mcp
npm install
npm run build
```

### 7. Remove TideWave Config

Clean up any remaining TideWave configuration:

```elixir
# Delete from config files:
config :tidewave, ...
config :your_app, :tidewave_port, ...
```

```bash
# Remove any TIDEWAVE_PORT references from runtime.exs
# Remove tidewave from .claude/settings.local.json if present
```

## Tool Mapping

| TideWave Tool | BeamScope Tool | Notes |
|---------------|----------------|-------|
| `get_logs` | `get_logs` | Same API |
| `project_eval` | `project_eval` | Same API |
| `get_docs` | `get_docs` | Same API (local docs only) |
| `search_package_docs` | — | Removed (hits external hexdocs.pm) |
| `get_source_location` | — | Not needed (agents have file system access) |
| `get_package_location` | — | Not needed (agents have file system access) |
| `execute_sql_query` | — | Ecto-specific, out of scope |
| N/A | `connect_beam_scope_mcp` | New — verify connection |
| N/A | `get_beam_scope_mcp_status` | New — check connection status |

## Verifying the Migration

### 1. Start your Elixir app:
```bash
iex -S mix
```

You should see:
```
BeamScopeMcp MCP server started on port 9995
```

### 2. Restart your AI coding agent (Claude Code, Cursor, etc.)

The new MCP server will be picked up on restart.

### 3. Test the connection:

Use `connect_beam_scope_mcp`, then try `project_eval` with:
```elixir
1 + 1
```

## Architecture Comparison

**TideWave:**
```
AI Agent → HTTP POST → Phoenix Endpoint → Tidewave Plug → Tools
                       (dies with app)
```

**BeamScope:**
```
AI Agent → stdio → TypeScript Bridge → TCP → Elixir GenServer → Tools
                   (stays running)         (reconnects automatically)
```
