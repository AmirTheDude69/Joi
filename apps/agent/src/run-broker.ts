import { randomUUID } from "node:crypto";
import type { JoiRunEvent } from "@joi/contracts";

type Listener = (event: JoiRunEvent) => void;

type RunRecord = {
  runId: string;
  threadId: string;
  userId: string;
  events: JoiRunEvent[];
  listeners: Set<Listener>;
  complete: boolean;
};

export class RunBroker {
  private readonly runs = new Map<string, RunRecord>();

  create(userId: string, threadId?: string): { runId: string; threadId: string } {
    const runId = randomUUID();
    const resolvedThreadId = threadId ?? randomUUID();
    this.runs.set(runId, {
      runId,
      threadId: resolvedThreadId,
      userId,
      events: [],
      listeners: new Set(),
      complete: false,
    });
    return { runId, threadId: resolvedThreadId };
  }

  emit(userId: string, runId: string, event: JoiRunEvent): void {
    const record = this.requireOwned(userId, runId);
    record.events.push(event);
    for (const listener of record.listeners) listener(event);
    if (event.type === "run.completed" || event.type === "run.failed") record.complete = true;
  }

  subscribe(userId: string, runId: string, listener: Listener): () => void {
    const record = this.requireOwned(userId, runId);
    for (const event of record.events) listener(event);
    record.listeners.add(listener);
    return () => record.listeners.delete(listener);
  }

  isComplete(userId: string, runId: string): boolean {
    return this.requireOwned(userId, runId).complete;
  }

  private requireOwned(userId: string, runId: string): RunRecord {
    const record = this.runs.get(runId);
    if (!record || record.userId !== userId) throw new Error("Run not found.");
    return record;
  }
}
