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

