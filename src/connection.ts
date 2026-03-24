/**
 * Connection management for BeamScope MCP
 *
 * Handles persistent TCP connections to Elixir server with automatic reconnection.
 */

import * as net from 'net';

// Connection state
let connectionState: 'unknown' | 'connected' | 'disconnected' = 'unknown';
let lastSuccessfulCommand = 0;
const COMMAND_SUCCESS_TTL = 10000;

// Read port from environment — fail loudly if not set
const envPort = process.env.BEAM_SCOPE_MCP_PORT;
if (!envPort) {
  console.error('[BeamScopeMcp] BEAM_SCOPE_MCP_PORT environment variable is required. Set it in your project\'s .mcp.json env config.');
  process.exit(1);
}
let currentPort = parseInt(envPort, 10);

// Persistent connection
let persistentConnection: net.Socket | null = null;
let connectionBuffer = '';

/**
 * Get or create a persistent connection to the Elixir server.
 */
function getPersistentConnection(): Promise<net.Socket> {
  return new Promise((resolve, reject) => {
    if (persistentConnection && !persistentConnection.destroyed) {
      resolve(persistentConnection);
      return;
    }

    persistentConnection = new net.Socket();

    persistentConnection.connect(currentPort, 'localhost', () => {
      connectionState = 'connected';
      lastSuccessfulCommand = Date.now();
      console.error(`[BeamScopeMcp] Connected to Elixir server on port ${currentPort}`);
      resolve(persistentConnection!);
    });

    persistentConnection.on('error', (err) => {
      connectionState = 'disconnected';
      persistentConnection = null;
      reject(err);
    });

    persistentConnection.on('close', () => {
      connectionState = 'disconnected';
      persistentConnection = null;
      console.error('[BeamScopeMcp] Connection closed');
    });
  });
}

/**
 * Send a command through the persistent connection.
 */
async function sendThroughPersistentConnection(command: unknown): Promise<string> {
  const conn = await getPersistentConnection();

  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => {
      reject(new Error('Command timeout after 30000ms'));
    }, 30000);

    const onData = (data: Buffer) => {
      connectionBuffer += data.toString();

      const lines = connectionBuffer.split('\n');

      if (lines.length > 1) {
        const response = lines[0].trim();
        connectionBuffer = lines.slice(1).join('\n');

        clearTimeout(timeout);
        lastSuccessfulCommand = Date.now();
        conn.off('data', onData);

        resolve(response);
      }
    };

    conn.on('data', onData);

    const message = typeof command === 'string' ? command : JSON.stringify(command);
    conn.write(message + '\n');
  });
}

/**
 * Close the persistent connection.
 */
export function closePersistentConnection(): void {
  if (persistentConnection && !persistentConnection.destroyed) {
    persistentConnection.destroy();
    persistentConnection = null;
  }
}

/**
 * Send a command to the Elixir server with retries.
 */
export async function sendToElixir(command: unknown, retries = 3): Promise<string> {
  for (let i = 0; i < retries; i++) {
    try {
      return await sendThroughPersistentConnection(command);
    } catch (error) {
      console.error(`[BeamScopeMcp] Send failed (attempt ${i + 1}/${retries}):`, error);
      if (i === retries - 1) throw error;

      // Clean up and wait before retry
      if (persistentConnection) {
        persistentConnection.destroy();
        persistentConnection = null;
      }
      await new Promise(resolve => setTimeout(resolve, 500 * (i + 1)));
    }
  }
  throw new Error('Failed to send command after retries');
}

/**
 * Check if the TCP server is available.
 */
export async function checkTCPServer(): Promise<boolean> {
  const now = Date.now();

  // If we had a successful command recently, assume still connected
  if (now - lastSuccessfulCommand < COMMAND_SUCCESS_TTL) {
    return true;
  }

  // If we have an active connection, it's connected
  if (persistentConnection && !persistentConnection.destroyed) {
    return true;
  }

  // Do a quick connection test
  return new Promise((resolve) => {
    const client = new net.Socket();
    const timeout = setTimeout(() => {
      client.destroy();
      resolve(false);
    }, 1000);

    client.connect(currentPort, 'localhost', () => {
      clearTimeout(timeout);
      client.destroy();
      resolve(true);
    });

    client.on('error', () => {
      clearTimeout(timeout);
      resolve(false);
    });
  });
}

/**
 * Get the current port.
 */
export function getCurrentPort(): number {
  return currentPort;
}
