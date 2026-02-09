export type ServerEventType =
  | "server.welcome"
  | "room.state"
  | "room.joined"
  | "room.left"
  | "room.closed"
  | "chat.message"
  | "chat.denied"
  | "error.generic";

export type ClientCommandType = "client.chat.send" | "client.room.leave";

export interface WsEnvelope<T = unknown> {
  type: string;
  payload: T;
  ts?: number;
}

export function serializeEnvelope<T>(type: string, payload: T): string {
  return JSON.stringify({
    type,
    payload,
    ts: Date.now()
  });
}

export function errorPayload(code: string, message?: string): { code: string; message?: string } {
  if (message) {
    return { code, message };
  }
  return { code };
}
