import { randomUUID } from "node:crypto";
import type { JoiRunEvent, MemoryProposal } from "@joi/contracts";
import type { JoiService } from "./service.js";

export type EventEmitter = (event: JoiRunEvent) => void;

function emitWords(text: string, emit: EventEmitter): void {
  for (const chunk of text.match(/\S+\s*/g) ?? [text]) {
    emit({ type: "message.delta", text: chunk });
  }
}

export async function runDemoAgent(
  service: JoiService,
  userId: string,
  message: string,
  emit: EventEmitter,
): Promise<void> {
  const normalized = message.trim();
  const lower = normalized.toLowerCase();
  emit({ type: "state.changed", state: "working" });

  const rememberMatch = normalized.match(/^remember(?: that)?\s+(.+)/i);
  if (rememberMatch?.[1]) {
    const proposal: MemoryProposal = {
      category: "preference",
      value: rememberMatch[1].trim(),
      sensitivity: "normal",
      reason: "You explicitly asked Joi to remember this.",
    };
    service.createMemory(userId, {
      category: proposal.category,
      value: proposal.value,
      sensitivity: proposal.sensitivity,
      source: "user_explicit",
      confidence: 1,
    });
    emit({ type: "memory.proposed", memory: proposal });
    emitWords("I saved that in your editable memory list. You can remove it whenever you like.", emit);
    emit({ type: "state.changed", state: "success" });
    return;
  }

  const taskMatch = normalized.match(/^(?:add|create) (?:a )?task(?: to)?\s+(.+)/i);
  if (taskMatch?.[1]) {
    const task = service.createTask(userId, {
      title: taskMatch[1].trim(),
      notes: "Created by Joi from chat.",
      priority: "medium",
    });
    emitWords(`Done — I added “${task.title}” to your task list.`, emit);
    emit({ type: "state.changed", state: "success" });
    return;
  }

  if (lower.includes("send") && lower.includes("email")) {
    const approval = service.requestEmailSend(userId, {
      to: ["maya@example.com"],
      subject: "Latest Joi launch checklist",
      body: "Hi Maya,\n\nHere is the latest Joi launch checklist for tomorrow's review.\n\nBest,",
      idempotencyKey: `chat-${randomUUID()}`,
    });
    emit({ type: "approval.required", approvalId: approval.id, preview: approval.preview });
    emitWords("I drafted the email and placed the exact recipient and content in your approval inbox. I won’t send it until you approve.", emit);
    emit({ type: "state.changed", state: "waiting_for_user" });
    return;
  }

  if (lower.includes("inbox") || lower.includes("email")) {
    emit({ type: "tool.started", tool: "joi.google.gmail.search", risk: "read" });
    const messages = service.google.searchGmail("");
    emit({ type: "tool.completed", tool: "joi.google.gmail.search", summary: `Found ${messages.length} demo messages.` });
    const unread = messages.filter((item) => item.unread);
    emitWords(
      `You have ${unread.length} unread demo message${unread.length === 1 ? "" : "s"}. The most actionable one asks for the latest launch checklist before tomorrow’s project review.`,
      emit,
    );
    emit({ type: "state.changed", state: "reviewing" });
    return;
  }

  if (lower.includes("calendar") || lower.includes("schedule") || lower.includes("day")) {
    emit({ type: "tool.started", tool: "joi.google.calendar.list", risk: "read" });
    const events = service.google.listCalendar();
    emit({ type: "tool.completed", tool: "joi.google.calendar.list", summary: `Found ${events.length} demo events.` });
    emitWords(
      `Your demo calendar has ${events.length} upcoming items. Protect the focus block, and prepare the launch checklist before the project review.`,
      emit,
    );
    emit({ type: "state.changed", state: "reviewing" });
    return;
  }

  emitWords(
    "I’m Joi, an AI daily companion—not a human or an imitation of one. This runnable demo can manage tasks and memories, summarize the mock inbox and calendar, and prepare external actions for your approval. Add an OpenAI API key to enable the full agent manager and specialists.",
    emit,
  );
  emit({ type: "state.changed", state: "idle" });
}
