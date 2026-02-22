export type ServerEventType =
  | "server.welcome"
  | "room.state"
  | "room.joined"
  | "room.left"
  | "room.closed"
  | "chat.message"
  | "chat.denied"
  | "match.turnOrder"
  | "match.phaseChanged"
  | "match.placement.revealStart"
  | "match.cards.dealt"
  | "match.cards.locked"
  | "match.turn.cardCue"
  | "match.turn.cardApplied"
  | "match.turn.start"
  | "match.turn.shotAccepted"
  | "match.turn.snapshotRequested"
  | "match.turn.snapshotApplied"
  | "match.result"
  | "error.generic";

export type ClientCommandType =
  | "client.chat.send"
  | "client.room.leave"
  | "client.room.ready"
  | "client.match.start"
  | "client.match.placement.submit"
  | "client.match.cards.pick"
  | "client.match.turn.cardUse"
  | "client.match.rematch.vote"
  | "client.match.surrender"
  | "client.match.turn.shot"
  | "client.match.turn.snapshot";

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
