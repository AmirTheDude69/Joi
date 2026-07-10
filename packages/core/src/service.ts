import { randomUUID } from "node:crypto";
import {
  capabilityCatalog,
  CreateAutomationSchema,
  CreateMemorySchema,
  CreateTaskSchema,
  UpdateTaskSchema,
  UpdateAutomationSchema,
  UpdateMemorySchema,
  type ActionPreview,
  type ActionRisk,
  type Approval,
  type CapabilityDescriptor,
  type CapabilityId,
  type Automation,
  type CreateAutomationInput,
  type CreateMemoryInput,
  type CreateTaskInput,
  type JoiMemory,
  type Task,
  type UpdateTaskInput,
  type UpdateAutomationInput,
  type UpdateMemoryInput,
  type UserProfile,
} from "@joi/contracts";
import { MockGoogleConnectors } from "./connectors.js";
import { evaluateActionRisk } from "./policy.js";
import { InMemoryJoiStore } from "./store.js";

function expiresIn(minutes: number): string {
  return new Date(Date.now() + minutes * 60_000).toISOString();
}

export class JoiService {
  constructor(
    readonly store = new InMemoryJoiStore(),
    readonly google = new MockGoogleConnectors(),
  ) {}

  updateProfile(userId: string, patch: Partial<Omit<UserProfile, "userId" | "createdAt">>): UserProfile {
    const profile = this.store.updateProfile(userId, patch);
    this.store.appendAudit({
      userId,
      action: "joi.profile.update",
      risk: "reversible_write",
      status: "completed",
      summary: "Updated Joi profile controls.",
      metadata: { fields: Object.keys(patch) },
    });
    return profile;
  }

  listCapabilities(userId: string): CapabilityDescriptor[] {
    return capabilityCatalog(this.store.getCapabilitySelections(userId));
  }

  setCapability(userId: string, capabilityId: string, enabled: boolean): CapabilityDescriptor {
    const current = this.listCapabilities(userId).find((item) => item.id === capabilityId);
    if (!current) throw new Error(`Unknown capability: ${capabilityId}`);
    if (current.availability !== "implemented_beta" && enabled) {
      throw new Error(`${capabilityId} is a release gate and cannot be enabled in this build.`);
    }
    this.store.setCapabilitySelection(userId, current.id as CapabilityId, enabled);
    this.store.appendAudit({
      userId,
      action: "joi.capabilities.update",
      risk: "reversible_write",
      status: "completed",
      summary: `${enabled ? "Enabled" : "Disabled"} ${capabilityId}.`,
      metadata: { capabilityId, enabled },
    });
    return this.listCapabilities(userId).find((item) => item.id === capabilityId)!;
  }

  listMemories(userId: string): JoiMemory[] {
    return this.store.listMemories(userId);
  }

  createMemory(userId: string, input: CreateMemoryInput): JoiMemory {
    const parsed = CreateMemorySchema.parse(input);
    const memory = this.store.createMemory(userId, parsed);
    this.store.appendAudit({
      userId,
      action: "joi.memory.create",
      risk: "reversible_write",
      status: "completed",
      summary: `Saved a ${memory.category} memory.`,
      metadata: { memoryId: memory.id, sensitivity: memory.sensitivity },
    });
    return memory;
  }

  deleteMemory(userId: string, memoryId: string): boolean {
    const deleted = this.store.deleteMemory(userId, memoryId);
    if (deleted) {
      this.store.appendAudit({
        userId,
        action: "joi.memory.delete",
        risk: "reversible_write",
        status: "completed",
        summary: "Deleted a user-selected memory.",
        metadata: { memoryId },
      });
    }
    return deleted;
  }

  updateMemory(userId: string, memoryId: string, input: UpdateMemoryInput): JoiMemory | undefined {
    const memory = this.store.updateMemory(userId, memoryId, UpdateMemorySchema.parse(input));
    if (memory) {
      this.store.appendAudit({
        userId,
        action: "joi.memory.update",
        risk: "reversible_write",
        status: "completed",
        summary: `Updated a ${memory.category} memory.`,
        metadata: { memoryId, fields: Object.keys(input) },
      });
    }
    return memory;
  }

  listTasks(userId: string): Task[] {
    return this.store.listTasks(userId);
  }

  createTask(userId: string, input: CreateTaskInput): Task {
    const task = this.store.createTask(userId, CreateTaskSchema.parse(input));
    this.store.appendAudit({
      userId,
      action: "joi.tasks.create",
      risk: "reversible_write",
      status: "completed",
      summary: `Created task: ${task.title}`,
      metadata: { taskId: task.id },
    });
    return task;
  }

  updateTask(userId: string, taskId: string, input: UpdateTaskInput): Task | undefined {
    const task = this.store.updateTask(userId, taskId, UpdateTaskSchema.parse(input));
    if (task) {
      this.store.appendAudit({
        userId,
        action: "joi.tasks.update",
        risk: "reversible_write",
        status: "completed",
        summary: `Updated task: ${task.title}`,
        metadata: { taskId, fields: Object.keys(input) },
      });
    }
    return task;
  }

  deleteTask(userId: string, taskId: string): boolean {
    const deleted = this.store.deleteTask(userId, taskId);
    if (deleted) {
      this.store.appendAudit({
        userId,
        action: "joi.tasks.delete",
        risk: "reversible_write",
        status: "completed",
        summary: "Deleted a user-selected task.",
        metadata: { taskId },
      });
    }
    return deleted;
  }

  listAutomations(userId: string): Automation[] {
    return this.store.listAutomations(userId);
  }

  createAutomation(userId: string, input: CreateAutomationInput): Automation {
    const automation = this.store.createAutomation(userId, CreateAutomationSchema.parse(input));
    this.store.appendAudit({
      userId,
      action: "joi.automation.create",
      risk: "reversible_write",
      status: "completed",
      summary: `Created routine: ${automation.name}`,
      metadata: { automationId: automation.id },
    });
    return automation;
  }

  deleteAutomation(userId: string, automationId: string): boolean {
    const deleted = this.store.deleteAutomation(userId, automationId);
    if (deleted) {
      this.store.appendAudit({
        userId,
        action: "joi.automation.delete",
        risk: "reversible_write",
        status: "completed",
        summary: "Deleted a user-selected routine.",
        metadata: { automationId },
      });
    }
    return deleted;
  }

  updateAutomation(userId: string, automationId: string, input: UpdateAutomationInput): Automation | undefined {
    const automation = this.store.updateAutomation(userId, automationId, UpdateAutomationSchema.parse(input));
    if (automation) {
      this.store.appendAudit({
        userId,
        action: "joi.automation.update",
        risk: "reversible_write",
        status: "completed",
        summary: `Updated routine: ${automation.name}`,
        metadata: { automationId, fields: Object.keys(input) },
      });
    }
    return automation;
  }

  requestAction(args: {
    userId: string;
    idempotencyKey: string;
    risk: ActionRisk;
    action: string;
    label: string;
    summary: string;
    payload: Record<string, unknown>;
  }): Approval {
    const existing = this.store.findApprovalByIdempotencyKey(args.userId, args.idempotencyKey);
    if (existing) return existing;

    const decision = evaluateActionRisk(args.risk);
    if (!decision.allowed) {
      this.store.appendAudit({
        userId: args.userId,
        action: args.action,
        risk: args.risk,
        status: "blocked",
        summary: decision.reason,
        metadata: { idempotencyKey: args.idempotencyKey },
      });
      throw new Error(decision.reason);
    }

    const preview: ActionPreview = {
      action: args.action,
      label: args.label,
      summary: args.summary,
      payload: args.payload,
      expiresAt: expiresIn(30),
    };
    const approval: Approval = {
      id: randomUUID(),
      userId: args.userId,
      idempotencyKey: args.idempotencyKey,
      risk: args.risk,
      status: decision.requiresApproval ? "pending" : "approved",
      preview,
      createdAt: new Date().toISOString(),
    };
    this.store.createApproval(approval);
    this.store.appendAudit({
      userId: args.userId,
      action: args.action,
      risk: args.risk,
      status: decision.requiresApproval ? "started" : "completed",
      summary: decision.requiresApproval ? "Waiting for user approval." : args.summary,
      metadata: { approvalId: approval.id, idempotencyKey: args.idempotencyKey },
    });
    return approval;
  }

  async approve(userId: string, approvalId: string): Promise<Approval | undefined> {
    const approval = this.store.listApprovals(userId).find((item) => item.id === approvalId);
    if (!approval || approval.status !== "pending") return approval;
    if (new Date(approval.preview.expiresAt).getTime() < Date.now()) {
      return this.store.updateApproval(userId, approvalId, { status: "expired", decidedAt: new Date().toISOString() });
    }

    try {
      let result: Record<string, unknown>;
      switch (approval.preview.action) {
        case "joi.google.gmail.send": {
          const payload = approval.preview.payload as { to: string[]; subject: string; body: string };
          result = this.google.sendEmail(payload);
          break;
        }
        case "joi.google.calendar.create": {
          const payload = approval.preview.payload as {
            title: string;
            startsAt: string;
            endsAt: string;
            attendees: string[];
            location?: string;
          };
          result = this.google.createCalendarEvent(payload);
          break;
        }
        default:
          result = { acknowledged: true, action: approval.preview.action };
      }
      const updated = this.store.updateApproval(userId, approvalId, {
        status: "executed",
        result,
        decidedAt: new Date().toISOString(),
      });
      this.store.appendAudit({
        userId,
        action: approval.preview.action,
        risk: approval.risk,
        status: "completed",
        summary: approval.preview.summary,
        metadata: { approvalId, result },
      });
      return updated;
    } catch (error) {
      const failed = this.store.updateApproval(userId, approvalId, {
        status: "failed",
        result: { error: error instanceof Error ? error.message : "Unknown action failure" },
        decidedAt: new Date().toISOString(),
      });
      this.store.appendAudit({
        userId,
        action: approval.preview.action,
        risk: approval.risk,
        status: "failed",
        summary: "Approved action failed during execution.",
        metadata: { approvalId },
      });
      return failed;
    }
  }

  reject(userId: string, approvalId: string): Approval | undefined {
    const approval = this.store.listApprovals(userId).find((item) => item.id === approvalId);
    if (!approval || approval.status !== "pending") return approval;
    const rejected = this.store.updateApproval(userId, approvalId, {
      status: "rejected",
      decidedAt: new Date().toISOString(),
    });
    this.store.appendAudit({
      userId,
      action: approval.preview.action,
      risk: approval.risk,
      status: "blocked",
      summary: "User rejected the exact action preview.",
      metadata: { approvalId },
    });
    return rejected;
  }

  requestEmailSend(userId: string, input: { to: string[]; subject: string; body: string; idempotencyKey: string }): Approval {
    return this.requestAction({
      userId,
      idempotencyKey: input.idempotencyKey,
      risk: "external_write",
      action: "joi.google.gmail.send",
      label: "Send email",
      summary: `Send “${input.subject}” to ${input.to.join(", ")}.`,
      payload: { to: input.to, subject: input.subject, body: input.body },
    });
  }

  requestCalendarEvent(userId: string, input: {
    title: string;
    startsAt: string;
    endsAt: string;
    attendees: string[];
    location?: string;
    idempotencyKey: string;
  }): Approval {
    return this.requestAction({
      userId,
      idempotencyKey: input.idempotencyKey,
      risk: "external_write",
      action: "joi.google.calendar.create",
      label: "Create calendar event",
      summary: `Create “${input.title}” from ${input.startsAt} to ${input.endsAt}.`,
      payload: {
        title: input.title,
        startsAt: input.startsAt,
        endsAt: input.endsAt,
        attendees: input.attendees,
        ...(input.location ? { location: input.location } : {}),
      },
    });
  }
}
