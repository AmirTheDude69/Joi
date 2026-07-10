import { randomUUID } from "node:crypto";
import type {
  Approval,
  AuditEvent,
  Automation,
  CreateAutomationInput,
  CreateMemoryInput,
  CreateTaskInput,
  JoiMemory,
  Task,
  UpdateTaskInput,
  UpdateAutomationInput,
  UpdateMemoryInput,
  UserProfile,
} from "@joi/contracts";
import type { CapabilityId } from "@joi/contracts";

function now(): string {
  return new Date().toISOString();
}

function byNewest<T extends { createdAt: string }>(a: T, b: T): number {
  return b.createdAt.localeCompare(a.createdAt);
}

export class InMemoryJoiStore {
  private readonly profiles = new Map<string, UserProfile>();
  private readonly memories = new Map<string, JoiMemory>();
  private readonly tasks = new Map<string, Task>();
  private readonly approvals = new Map<string, Approval>();
  private readonly automations = new Map<string, Automation>();
  private readonly auditEvents = new Map<string, AuditEvent>();
  private readonly capabilitySelections = new Map<string, Map<CapabilityId, boolean>>();

  getProfile(userId: string): UserProfile {
    const existing = this.profiles.get(userId);
    if (existing) return existing;
    const timestamp = now();
    const profile: UserProfile = {
      userId,
      displayName: "Friend",
      timezone: "UTC",
      locale: "en-US",
      workingHours: { start: "09:00", end: "17:00" },
      warmth: 78,
      humor: 58,
      initiative: 64,
      mode: "personal",
      createdAt: timestamp,
      updatedAt: timestamp,
    };
    this.profiles.set(userId, profile);
    return profile;
  }

  updateProfile(userId: string, patch: Partial<Omit<UserProfile, "userId" | "createdAt">>): UserProfile {
    const current = this.getProfile(userId);
    const updated = { ...current, ...patch, userId, updatedAt: now() };
    this.profiles.set(userId, updated);
    return updated;
  }

  listMemories(userId: string): JoiMemory[] {
    return [...this.memories.values()].filter((item) => item.userId === userId).sort(byNewest);
  }

  createMemory(userId: string, input: CreateMemoryInput): JoiMemory {
    const timestamp = now();
    const memory: JoiMemory = {
      id: randomUUID(),
      userId,
      category: input.category,
      value: input.value,
      sensitivity: input.sensitivity,
      source: input.source,
      confidence: input.confidence,
      createdAt: timestamp,
      updatedAt: timestamp,
      ...(input.expiresAt ? { expiresAt: input.expiresAt } : {}),
    };
    this.memories.set(memory.id, memory);
    return memory;
  }

  deleteMemory(userId: string, memoryId: string): boolean {
    const memory = this.memories.get(memoryId);
    if (!memory || memory.userId !== userId) return false;
    return this.memories.delete(memoryId);
  }

  updateMemory(userId: string, memoryId: string, input: UpdateMemoryInput): JoiMemory | undefined {
    const current = this.memories.get(memoryId);
    if (!current || current.userId !== userId) return undefined;
    const updated: JoiMemory = {
      ...current,
      ...(input.category !== undefined ? { category: input.category } : {}),
      ...(input.value !== undefined ? { value: input.value } : {}),
      ...(input.sensitivity !== undefined ? { sensitivity: input.sensitivity } : {}),
      ...(input.expiresAt !== undefined ? { expiresAt: input.expiresAt } : {}),
      updatedAt: now(),
    };
    this.memories.set(memoryId, updated);
    return updated;
  }

  listTasks(userId: string): Task[] {
    return [...this.tasks.values()].filter((item) => item.userId === userId).sort(byNewest);
  }

  createTask(userId: string, input: CreateTaskInput): Task {
    const timestamp = now();
    const task: Task = {
      id: randomUUID(),
      userId,
      title: input.title,
      notes: input.notes,
      priority: input.priority,
      status: "todo",
      createdAt: timestamp,
      updatedAt: timestamp,
      ...(input.dueAt ? { dueAt: input.dueAt } : {}),
    };
    this.tasks.set(task.id, task);
    return task;
  }

  updateTask(userId: string, taskId: string, input: UpdateTaskInput): Task | undefined {
    const current = this.tasks.get(taskId);
    if (!current || current.userId !== userId) return undefined;
    const updated: Task = {
      ...current,
      id: current.id,
      userId,
      updatedAt: now(),
      ...(input.title !== undefined ? { title: input.title } : {}),
      ...(input.notes !== undefined ? { notes: input.notes } : {}),
      ...(input.status !== undefined ? { status: input.status } : {}),
      ...(input.priority !== undefined ? { priority: input.priority } : {}),
      ...(input.dueAt !== undefined ? { dueAt: input.dueAt } : {}),
    };
    this.tasks.set(taskId, updated);
    return updated;
  }

  deleteTask(userId: string, taskId: string): boolean {
    const task = this.tasks.get(taskId);
    if (!task || task.userId !== userId) return false;
    return this.tasks.delete(taskId);
  }

  listApprovals(userId: string): Approval[] {
    return [...this.approvals.values()].filter((item) => item.userId === userId).sort(byNewest);
  }

  findApprovalByIdempotencyKey(userId: string, key: string): Approval | undefined {
    return [...this.approvals.values()].find(
      (item) => item.userId === userId && item.idempotencyKey === key,
    );
  }

  createApproval(approval: Approval): Approval {
    this.approvals.set(approval.id, approval);
    return approval;
  }

  updateApproval(userId: string, approvalId: string, patch: Partial<Approval>): Approval | undefined {
    const current = this.approvals.get(approvalId);
    if (!current || current.userId !== userId) return undefined;
    const updated = { ...current, ...patch, id: current.id, userId };
    this.approvals.set(approvalId, updated);
    return updated;
  }

  listAutomations(userId: string): Automation[] {
    return [...this.automations.values()].filter((item) => item.userId === userId).sort(byNewest);
  }

  createAutomation(userId: string, input: CreateAutomationInput): Automation {
    const timestamp = now();
    const automation: Automation = {
      id: randomUUID(),
      userId,
      name: input.name,
      kind: input.kind,
      schedule: input.schedule,
      prompt: input.prompt,
      enabled: input.enabled,
      createdAt: timestamp,
      updatedAt: timestamp,
      ...(input.nextRunAt ? { nextRunAt: input.nextRunAt } : {}),
    };
    this.automations.set(automation.id, automation);
    return automation;
  }

  deleteAutomation(userId: string, automationId: string): boolean {
    const automation = this.automations.get(automationId);
    if (!automation || automation.userId !== userId) return false;
    return this.automations.delete(automationId);
  }

  updateAutomation(userId: string, automationId: string, input: UpdateAutomationInput): Automation | undefined {
    const current = this.automations.get(automationId);
    if (!current || current.userId !== userId) return undefined;
    const updated: Automation = {
      ...current,
      ...(input.name !== undefined ? { name: input.name } : {}),
      ...(input.schedule !== undefined ? { schedule: input.schedule } : {}),
      ...(input.prompt !== undefined ? { prompt: input.prompt } : {}),
      ...(input.enabled !== undefined ? { enabled: input.enabled } : {}),
      ...(input.nextRunAt !== undefined ? { nextRunAt: input.nextRunAt } : {}),
      updatedAt: now(),
    };
    this.automations.set(automationId, updated);
    return updated;
  }

  appendAudit(event: Omit<AuditEvent, "id" | "createdAt">): AuditEvent {
    const saved: AuditEvent = { ...event, id: randomUUID(), createdAt: now() };
    this.auditEvents.set(saved.id, saved);
    return saved;
  }

  listAudit(userId: string): AuditEvent[] {
    return [...this.auditEvents.values()].filter((item) => item.userId === userId).sort(byNewest);
  }

  getCapabilitySelections(userId: string): Partial<Record<CapabilityId, boolean>> {
    return Object.fromEntries(this.capabilitySelections.get(userId) ?? []) as Partial<Record<CapabilityId, boolean>>;
  }

  setCapabilitySelection(userId: string, capabilityId: CapabilityId, enabled: boolean): void {
    const selections = this.capabilitySelections.get(userId) ?? new Map<CapabilityId, boolean>();
    selections.set(capabilityId, enabled);
    this.capabilitySelections.set(userId, selections);
  }

  deleteUserData(userId: string): void {
    this.profiles.delete(userId);
    this.capabilitySelections.delete(userId);
    for (const collection of [
      this.memories,
      this.tasks,
      this.approvals,
      this.automations,
      this.auditEvents,
    ]) {
      for (const [id, item] of collection) {
        if (item.userId === userId) collection.delete(id);
      }
    }
  }
}
