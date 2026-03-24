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
      description: `Retrieve application logs from the running Elixir app.

Use this to check for errors, debug issues, or see what the application is doing.
Logs are captured in a circular buffer so old logs may be discarded.`,
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
      description: `Evaluate Elixir code in the context of the running application.

Use this to:
- Test functions and modules
- Inspect application state
- Debug issues
- Run queries or operations

The code runs with full access to your application's modules, dependencies, and runtime state.
IEx helpers like exports/1 are available.`,
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
      description: `Get documentation for an Elixir module or function.

Returns the documentation for the given reference. Works for modules in the
current project and all dependencies.

Examples:
- "GenServer" - module docs
- "String.split" - all arities of function
- "String.split/2" - specific arity
- "c:GenServer.handle_call/3" - callback docs (prefix with c:)`,
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
      description: `Recompile the current Elixir project from within the running BEAM.

Returns compilation output including any errors or warnings. This gives a fast feedback loop without needing to shell out to mix compile.

Note: this recompiles the project code only, not dependencies. Use project_eval with Mix.Task.run("deps.compile", ["--force"]) for deps.`,
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
    {
      name: 'get_system_stats',
      description: `Get BEAM runtime metrics: memory usage, scheduler info, process counts, uptime, IO stats.

Use this to understand the health and resource usage of the running Elixir application.`,
      inputSchema: {
        type: 'object',
        properties: {},
      },
    },
    {
      name: 'list_processes',
      description: `List running BEAM processes with filtering and sorting options.

Use to find processes by name, find processes with large message queues, or sort by memory usage. Returns up to 50 processes by default.`,
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
      description: `Get detailed information about a specific BEAM process: current function, memory, message queue, links, monitors, stacktrace.

Accepts a PID string like "<0.123.0>" or a registered process name.`,
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
      description: `Get the internal state of a GenServer or other OTP process using :sys.get_state.

Works on any process implementing the system message protocol (GenServer, gen_statem, etc). Accepts a PID string or registered name.

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
      description: `Read the process dictionary for a specific process. Complements get_process_state — the process dictionary often contains metadata not visible in state (Logger metadata, custom flags, step context, etc.).

Accepts a PID string like "<0.123.0>" or a registered process name.`,
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
      description: `Force recompile of Elixir dependencies.

Use when a local path dependency has changed and needs recompiling, or to force-rebuild all deps. You MUST specify the args parameter.`,
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
      description: `Get runtime application configuration. Unlike reading config files on disk, this returns what the BEAM actually has loaded — including runtime.exs overrides, env var substitutions, and dynamic Application.put_env changes.

Returns all config for an app, or a specific key.`,
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
      description: `List all ETS tables with metadata: name, size, memory usage, type, protection level, owner.

Sorted by memory usage descending. Use to discover what ETS tables exist before inspecting their contents.`,
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

