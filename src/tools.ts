/**
 * Tool definitions and handlers for BeamScope MCP
 */

import { sendToElixir, checkTCPServer, getCurrentPort } from './connection.js';

// Tool response type matching MCP SDK CallToolResult
interface ToolResponse {
  content: Array<{ type: 'text'; text: string }>;
  isError?: boolean;
  [key: string]: unknown;
}

/**
 * Get all tool definitions for MCP.
 */
export function getToolDefinitions() {
  return [
    {
      name: 'connect_beam_scope_mcp',
      description: `Connect to the BeamScope MCP server running in your Elixir application. The TCP port is pre-configured via BEAM_SCOPE_MCP_PORT env var. Do NOT guess the port. If connection fails, look up the correct port in the Elixir config: check config/runtime.exs, config/dev.exs, or config/config.exs in the current project for \`config :beam_scope_mcp, port: <number>\`. Then check .mcp.json to ensure the BEAM_SCOPE_MCP_PORT env var matches. This must be called before using other BeamScope tools (get_logs, project_eval, etc.).`,
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
    {
      name: 'get_beam_scope_mcp_status',
      description: 'Check if connected to an Elixir app and get server details. The port is configured via BEAM_SCOPE_MCP_PORT env var — if not set, check your .mcp.json env config.',
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
    {
      name: 'get_logs',
      description: `Your primary debugging tool. Retrieve application logs from the running Elixir app — errors, warnings, crash reports, and application output. This is the ONLY source of log data; no other tool provides it.

WHEN TO USE: First step when diagnosing any problem. Check logs before drawing conclusions from other tools.
NOT FOR: System resource usage (use get_system_stats). Process-level details (use get_process_info).

Use grep to filter (e.g. "error", "warning", "timeout") and level to filter by severity. Logs are in a circular buffer so old entries may be discarded.`,
      inputSchema: {
        type: 'object',
        required: ['tail'],
        properties: {
          tail: {
            type: 'integer',
            description: 'Number of log entries to return from the end',
          },
          grep: {
            type: 'string',
            description: 'Filter logs with regex pattern (case insensitive). E.g., "error" to find error messages',
          },
          level: {
            type: 'string',
            enum: ['emergency', 'alert', 'critical', 'error', 'warning', 'notice', 'info', 'debug'],
            description: 'Filter by log level',
          },
        },
      },
    },
    {
      name: 'project_eval',
      description: `Evaluate Elixir code in the context of the running application. This is the general-purpose escape hatch — use it when no specific tool exists for what you need.

PREFER specific tools over project_eval when they exist:
- Need logs? Use get_logs, not project_eval with Logger
- Need process info? Use get_process_info/get_process_state, not project_eval with Process.info
- Need to recompile? Use recompile or reload_module
- Need ETS data? Use list_ets_tables/inspect_ets_table
- Need docs? Use get_docs
- Need callers? Use xref_callers

Use project_eval for one-off operations that don't have a dedicated tool.
The code runs with full access to your application's modules, dependencies, and runtime state.`,
      inputSchema: {
        type: 'object',
        required: ['code'],
        properties: {
          code: {
            type: 'string',
            description: 'Elixir code to evaluate',
          },
          timeout: {
            type: 'integer',
            description: 'Max execution time in milliseconds (default: 30000)',
          },
        },
      },
    },
    {
      name: 'get_docs',
      description: `Get @moduledoc/@doc documentation for an Elixir module or function. Reads from compiled .beam files (local, no network).

WHEN TO USE: You need to understand what a function does, its parameters, or how to use a module.
NOT FOR: Finding what calls a function (use xref_callers). Evaluating code (use project_eval).

Examples: "GenServer", "String.split", "String.split/2", "c:GenServer.handle_call/3" (prefix c: for callbacks).`,
      inputSchema: {
        type: 'object',
        required: ['reference'],
        properties: {
          reference: {
            type: 'string',
            description: 'Module name, Module.function, or Module.function/arity',
          },
        },
      },
    },
    {
      name: 'recompile',
      description: `Recompile the entire project from within the running BEAM. Returns errors/warnings.

WHEN TO USE: After changing multiple files, or when you're not sure what changed. This is equivalent to mix compile.
NOT FOR: Single file changes (use reload_module instead — much faster). Dependencies (use recompile_deps instead).`,
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
    {
      name: 'reload_module',
      description: `Hot-reload a single module from its source file. Fastest possible feedback loop — change one file, reload it, test immediately.

WHEN TO USE: After changing a single .ex file. No full recompile needed.
NOT FOR: Multiple file changes (use recompile). Dependencies (use recompile_deps).`,
      inputSchema: {
        type: 'object',
        required: ['file'],
        properties: {
          file: {
            type: 'string',
            description: 'Full path to the .ex or .exs file to reload (e.g. "/home/luke/workbench/flx/merlinex/lib/my_module.ex")',
          },
        },
      },
    },
    {
      name: 'get_system_stats',
      description: `Get BEAM runtime health: memory usage, scheduler count, process/port/atom counts, uptime, IO throughput.

WHEN TO USE: You want a system-level health snapshot — is memory growing? How many processes are running? How long has the app been up?
NOT FOR: Application configuration (use get_app_config). Individual process details (use get_process_info). Checking for errors (use get_logs — system stats don't show errors).`,
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
    {
      name: 'list_processes',
      description: `List running BEAM processes — find them by name, sort by memory or queue size. Returns summary info for each process.

WHEN TO USE: You need to discover what processes exist, find a specific process by name, or identify processes using the most memory/having the largest queues.
NEXT STEP: Once you have a PID or name, use get_process_info, get_process_state, or get_process_dictionary for details.`,
      inputSchema: {
        type: 'object',
        properties: {
          limit: {
            type: 'integer',
            description: 'Max processes to return (default: 50)',
          },
          sort_by: {
            type: 'string',
            enum: ['memory', 'message_queue_len', 'reductions'],
            description: 'Sort processes by this field (descending)',
          },
          min_message_queue: {
            type: 'integer',
            description: 'Only show processes with at least this many messages in their queue',
          },
          name_filter: {
            type: 'string',
            description: 'Filter by registered name (case-insensitive substring match)',
          },
        },
      },
    },
    {
      name: 'get_process_info',
      description: `Get metadata ABOUT a process: what function it's running, memory usage, message queue length, links, monitors, stacktrace.

WHEN TO USE: You want to know what a process IS and what it's DOING — its identity and vital signs.
NOT FOR: The data the process is holding (use get_process_state). Metadata in the process dictionary (use get_process_dictionary).
Use list_processes first to find PIDs/names if you don't know them.`,
      inputSchema: {
        type: 'object',
        required: ['pid'],
        properties: {
          pid: {
            type: 'string',
            description: 'PID string (e.g. "<0.123.0>") or registered name (e.g. "MyApp.Worker")',
          },
        },
      },
    },
    {
      name: 'get_process_state',
      description: `Get the DATA a GenServer is holding — its internal state (the value in the GenServer's loop).

WHEN TO USE: You want to see the actual data/state inside a process — what it's storing, its current values.
NOT FOR: Process metadata like memory/links/stacktrace (use get_process_info). Process dictionary entries (use get_process_dictionary).
Note: may timeout if the process is busy or doesn't support :sys messages.`,
      inputSchema: {
        type: 'object',
        required: ['pid'],
        properties: {
          pid: {
            type: 'string',
            description: 'PID string (e.g. "<0.123.0>") or registered name (e.g. "MyApp.Worker")',
          },
          timeout: {
            type: 'integer',
            description: 'Timeout in milliseconds (default: 5000)',
          },
        },
      },
    },
    {
      name: 'get_process_dictionary',
      description: `Read the process dictionary — hidden metadata stored outside the main state. Contains OTP internals like $ancestors, $initial_call, plus any custom entries (Logger metadata, step context, flags).

WHEN TO USE: You need metadata that isn't in the GenServer state — OTP ancestry, custom flags, or debugging context.
NOT FOR: The process's main data (use get_process_state). Process vitals like memory/stacktrace (use get_process_info).`,
      inputSchema: {
        type: 'object',
        required: ['pid'],
        properties: {
          pid: {
            type: 'string',
            description: 'PID string (e.g. "<0.123.0>") or registered name',
          },
        },
      },
    },
    {
      name: 'recompile_deps',
      description: `Force recompile Elixir dependencies (not the project itself).

WHEN TO USE: When a local path dependency's source has changed, or to force-rebuild a specific dep. You MUST specify the args parameter.
NOT FOR: Project code (use recompile or reload_module).`,
      inputSchema: {
        type: 'object',
        required: ['args'],
        properties: {
          args: {
            type: 'array',
            items: { type: 'string' },
            description: 'Args passed to mix deps.compile (required). E.g. ["--force"] for all deps, or ["jason", "--force"] for a single dep.',
          },
        },
      },
    },
    {
      name: 'get_app_config',
      description: `Get runtime application configuration — what the BEAM actually has loaded (not what's in the config files on disk). Includes runtime.exs overrides, env var substitutions, and dynamic Application.put_env changes.

WHEN TO USE: You need to check config values (ports, feature flags, module settings) as the running app sees them.
NOT FOR: System health metrics (use get_system_stats). Process-level inspection (use get_process_info/state).`,
      inputSchema: {
        type: 'object',
        required: ['app'],
        properties: {
          app: {
            type: 'string',
            description: 'Application name (e.g. "merlinex", "phoenix", "beam_scope_mcp")',
          },
          key: {
            type: 'string',
            description: 'Specific config key (optional — omit for all config)',
          },
        },
      },
    },
    {
      name: 'get_supervision_tree',
      description: `Get the OTP supervision tree for an application. Recursively walks supervisors showing the full hierarchy of processes with PIDs, types, and child counts.

You MUST specify the app name. Use get_app_config or project_eval with Application.started_applications() to find app names if unsure.`,
      inputSchema: {
        type: 'object',
        required: ['app'],
        properties: {
          app: {
            type: 'string',
            description: 'Application name (required — e.g. "merlinex", "phoenix")',
          },
          depth: {
            type: 'integer',
            description: 'Max recursion depth (default: 10)',
          },
        },
      },
    },
    {
      name: 'list_ets_tables',
      description: `List all ETS tables with metadata: name, row count, memory, type, protection, owner. Sorted by memory descending.

WHEN TO USE: Discover what ETS tables exist, find tables using the most memory.
NEXT STEP: Use inspect_ets_table with the table name to read its contents.`,
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
    {
      name: 'inspect_ets_table',
      description: `Read the contents of an ETS table. Returns rows from the table, limited to avoid massive output.

Use list_ets_tables first to find table names, then inspect specific tables.`,
      inputSchema: {
        type: 'object',
        required: ['table'],
        properties: {
          table: {
            type: 'string',
            description: 'ETS table name (e.g. "my_cache"). Use list_ets_tables to find names.',
          },
          limit: {
            type: 'integer',
            description: 'Max rows to return (default: 20)',
          },
        },
      },
    },
    {
      name: 'xref_callers',
      description: `Find all callers of a module or function across the project — "what depends on this?"

WHEN TO USE: Impact analysis before refactoring. "What breaks if I change this function?" "Who calls this module?"
NOT FOR: Understanding what a function does (use get_docs). Seeing runtime call flow (use trace_calls).`,
      inputSchema: {
        type: 'object',
        required: ['reference'],
        properties: {
          reference: {
            type: 'string',
            description: 'Module or Module.function/arity (e.g. "Merlinex.Core.Manager" or "Enum.map/2")',
          },
        },
      },
    },
    {
      name: 'trace_calls',
      description: `Start tracing function calls on a module. This tool does NOT return the trace results directly — it writes them to a file and returns the file path.

WORKFLOW:
1. Call this tool → you get back a file path (e.g. /tmp/beam_scope_traces/MyModule_20260323_221503.log)
2. Wait a few seconds for the trace to collect events
3. Read the file using your normal file reading tools (Read tool) to see the trace results
4. The trace auto-stops when it hits max_calls or max_seconds — you do NOT need to call stop_trace

WHY A FILE: Traces collect events over time and can be large. Writing to a file lets you read just the parts you need (head, tail, grep for patterns).

The file contains timestamped entries like:
  [22:15:03.001] #1 #PID<0.599.0> MyModule.my_function("arg1", 42)

All parameters except function are REQUIRED. max_calls capped at 200, max_seconds capped at 30.`,
      inputSchema: {
        type: 'object',
        required: ['module', 'max_calls', 'max_seconds'],
        properties: {
          module: {
            type: 'string',
            description: 'Module to trace (e.g. "Merlinex.Core.Manager"). Required.',
          },
          function: {
            type: 'string',
            description: 'Specific function name (optional — omit to trace all functions in the module)',
          },
          max_calls: {
            type: 'integer',
            description: 'Stop after this many calls (required, max 200)',
          },
          max_seconds: {
            type: 'integer',
            description: 'Stop after this many seconds (required, max 30)',
          },
        },
      },
    },
    {
      name: 'stop_trace',
      description: 'Abort a running trace early. You do not normally need to call this — traces auto-stop when they hit their max_calls or max_seconds limit and clean up after themselves. This is only useful if you want to cancel a trace before it finishes on its own. Safe to call even if no trace is running.',
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
  ];
}

/**
 * Handle a tool call.
 */
export async function handleToolCall(name: string, args: Record<string, unknown>): Promise<ToolResponse> {
  switch (name) {
    case 'connect_beam_scope_mcp':
      return await handleConnect();
    case 'get_beam_scope_mcp_status':
      return await handleStatus();
    case 'get_logs':
      return await handleGetLogs(args);
    case 'project_eval':
      return await handleProjectEval(args);
    case 'get_docs':
      return await handleGetDocs(args);
    case 'recompile':
      return await handleForward('recompile', args);
    case 'reload_module':
      return await handleForward('reload_module', args);
    case 'get_system_stats':
      return await handleForward('get_system_stats', args);
    case 'list_processes':
      return await handleForward('list_processes', args);
    case 'get_process_info':
      return await handleForward('get_process_info', args);
    case 'get_process_state':
      return await handleForward('get_process_state', args);
    case 'get_process_dictionary':
      return await handleForward('get_process_dictionary', args);
    case 'recompile_deps':
      return await handleForward('recompile_deps', args);
    case 'get_app_config':
      return await handleForward('get_app_config', args);
    case 'get_supervision_tree':
      return await handleForward('get_supervision_tree', args);
    case 'list_ets_tables':
      return await handleForward('list_ets_tables', args);
    case 'inspect_ets_table':
      return await handleForward('inspect_ets_table', args);
    case 'xref_callers':
      return await handleForward('xref_callers', args);
    case 'trace_calls':
      return await handleForward('trace_calls', args);
    case 'stop_trace':
      return await handleForward('stop_trace', args);
    default:
      return {
        content: [{ type: 'text', text: `Unknown tool: ${name}` }],
        isError: true,
      };
  }
}

async function handleConnect(): Promise<ToolResponse> {
  try {
    const port = getCurrentPort();
    const isRunning = await checkTCPServer();

    if (!isRunning) {
      return {
        content: [{
          type: 'text',
          text: `No BeamScope server found on port ${port}.

Make sure:
1. Your Elixir app is running (iex -S mix or iex -S mix phx.server)
2. BeamScope is added as a dependency in mix.exs
3. The port in the Elixir config matches: config :beam_scope_mcp, port: ${port}
4. Check config/runtime.exs, config/dev.exs, or config/config.exs for the port setting`,
        }],
        isError: true,
      };
    }

    const response = await sendToElixir('hello');
    const data = JSON.parse(response);

    return {
      content: [{
        type: 'text',
        text: `Connected to Elixir application on port ${port}!

Server info:
${JSON.stringify(data, null, 2)}`,
      }],
    };
  } catch (error) {
    return {
      content: [{
        type: 'text',
        text: `Error connecting: ${error instanceof Error ? error.message : 'Unknown error'}`,
      }],
      isError: true,
    };
  }
}

async function handleStatus(): Promise<ToolResponse> {
  try {
    const port = getCurrentPort();
    const isRunning = await checkTCPServer();

    if (!isRunning) {
      return {
        content: [{
          type: 'text',
          text: `BeamScope Status:
- Connection: Disconnected
- TCP Port: ${port}

The Elixir app is not responding. Make sure it's running.`,
        }],
      };
    }

    const response = await sendToElixir({ action: 'status' });
    const data = JSON.parse(response);

    return {
      content: [{
        type: 'text',
        text: `BeamScope Status:
- Connection: Active
- TCP Port: ${port}

Server: ${JSON.stringify(data, null, 2)}`,
      }],
    };
  } catch (error) {
    return {
      content: [{
        type: 'text',
        text: `Status check failed: ${error instanceof Error ? error.message : 'Unknown error'}`,
      }],
      isError: true,
    };
  }
}

async function requireConnection(): Promise<ToolResponse | null> {
  const isRunning = await checkTCPServer();
  if (!isRunning) {
    const port = getCurrentPort();
    return {
      content: [{
        type: 'text',
        text: `Cannot execute: Elixir app is not responding on port ${port}.

Make sure your Elixir app is running (iex -S mix or iex -S mix phx.server).
Check that the port matches: look in config/runtime.exs, config/dev.exs, or config/config.exs for \`config :beam_scope_mcp, port: <number>\`.`,
      }],
      isError: true,
    };
  }
  return null;
}

async function handleGetLogs(args: Record<string, unknown>): Promise<ToolResponse> {
  try {
    const notConnected = await requireConnection();
    if (notConnected) return notConnected;

    const { tail, grep, level } = args as { tail: number; grep?: string; level?: string };

    if (!tail || typeof tail !== 'number') {
      return {
        content: [{
          type: 'text',
          text: 'Error: "tail" parameter is required and must be a number',
        }],
        isError: true,
      };
    }

    const command: Record<string, unknown> = { action: 'get_logs', tail };
    if (grep) command.grep = grep;
    if (level) command.level = level;

    const response = await sendToElixir(command);
    const data = JSON.parse(response);

    if (data.error) {
      return {
        content: [{ type: 'text', text: `Error: ${data.error}` }],
        isError: true,
      };
    }

    const logs = data.result || '';
    if (!logs || logs.trim() === '') {
      return {
        content: [{ type: 'text', text: 'No logs found matching criteria.' }],
      };
    }

    return {
      content: [{ type: 'text', text: logs }],
    };
  } catch (error) {
    return {
      content: [{
        type: 'text',
        text: `Error getting logs: ${error instanceof Error ? error.message : 'Unknown error'}`,
      }],
      isError: true,
    };
  }
}

async function handleProjectEval(args: Record<string, unknown>): Promise<ToolResponse> {
  try {
    const notConnected = await requireConnection();
    if (notConnected) return notConnected;

    const { code, timeout } = args as { code: string; timeout?: number };

    if (!code || typeof code !== 'string') {
      return {
        content: [{
          type: 'text',
          text: 'Error: "code" parameter is required and must be a string',
        }],
        isError: true,
      };
    }

    const command: Record<string, unknown> = { action: 'project_eval', code };
    if (timeout) command.timeout = timeout;

    const response = await sendToElixir(command);
    const data = JSON.parse(response);

    if (data.error) {
      return {
        content: [{ type: 'text', text: `Error: ${data.error}` }],
        isError: true,
      };
    }

    return {
      content: [{ type: 'text', text: data.result }],
    };
  } catch (error) {
    return {
      content: [{
        type: 'text',
        text: `Error evaluating code: ${error instanceof Error ? error.message : 'Unknown error'}`,
      }],
      isError: true,
    };
  }
}

async function handleForward(action: string, args: Record<string, unknown>): Promise<ToolResponse> {
  try {
    const notConnected = await requireConnection();
    if (notConnected) return notConnected;

    const command = { action, ...args };
    const response = await sendToElixir(command);
    const data = JSON.parse(response);

    if (data.error) {
      return {
        content: [{ type: 'text', text: `Error: ${data.error}` }],
        isError: true,
      };
    }

    return {
      content: [{ type: 'text', text: data.result || JSON.stringify(data, null, 2) }],
    };
  } catch (error) {
    return {
      content: [{
        type: 'text',
        text: `Error: ${error instanceof Error ? error.message : 'Unknown error'}`,
      }],
      isError: true,
    };
  }
}

async function handleGetDocs(args: Record<string, unknown>): Promise<ToolResponse> {
  try {
    const notConnected = await requireConnection();
    if (notConnected) return notConnected;

    const { reference } = args as { reference: string };

    if (!reference || typeof reference !== 'string') {
      return {
        content: [{
          type: 'text',
          text: 'Error: "reference" parameter is required',
        }],
        isError: true,
      };
    }

    const response = await sendToElixir({ action: 'get_docs', reference });
    const data = JSON.parse(response);

    if (data.error) {
      return {
        content: [{ type: 'text', text: `Error: ${data.error}` }],
        isError: true,
      };
    }

    return {
      content: [{ type: 'text', text: data.result }],
    };
  } catch (error) {
    return {
      content: [{
        type: 'text',
        text: `Error getting docs: ${error instanceof Error ? error.message : 'Unknown error'}`,
      }],
      isError: true,
    };
  }
}

