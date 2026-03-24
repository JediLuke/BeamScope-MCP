#!/usr/bin/env node

/**
 * BeamScopeMcp Server - Main entry point
 *
 * A robust MCP server for Elixir applications with automatic reconnection.
 *
 * Architecture:
 * MCP Client (Claude/Cursor) -> This TypeScript Server (stdio) -> TCP -> Elixir Server -> Your App
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from '@modelcontextprotocol/sdk/types.js';
import { getToolDefinitions, handleToolCall } from './tools.js';
import { closePersistentConnection } from './connection.js';

// Create the MCP server
const server = new Server(
  {
    name: 'beam-scope-mcp',
    version: '0.1.0',
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// List available tools
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: getToolDefinitions(),
  };
});

// Handle tool calls
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;
  return await handleToolCall(name, args as Record<string, unknown>);
});

// Main entry point
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);

  // Graceful shutdown
  process.on('SIGTERM', () => {
    closePersistentConnection();
    process.exit(0);
  });

  process.on('SIGINT', () => {
    closePersistentConnection();
    process.exit(0);
  });

  console.error('[BeamScopeMcp] Server started - waiting for Elixir application');
}

main().catch((error) => {
  console.error('[BeamScopeMcp] Fatal error:', error);
  process.exit(1);
});
