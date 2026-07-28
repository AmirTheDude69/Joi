import { z } from "zod";
import { ActionPreviewSchema, ActionRiskSchema } from "./agent.js";

const TimestampFields = {
  createdAt: z.iso.datetime(),
  updatedAt: z.iso.datetime(),
};

export const JoiMemorySchema = z.object({
  id: z.string().uuid(),
  userId: z.string().min(1),
  category: z.enum(["preference", "person", "date", "routine", "project", "goal"]),
  value: z.string().min(1).max(2_000),
  sensitivity: z.enum(["normal", "sensitive"]),
  source: z.enum(["user_explicit", "assistant_proposal", "import"]),
  confidence: z.number().min(0).max(1),
  createdAt: z.iso.datetime(),
  updatedAt: z.iso.datetime(),
  expiresAt: z.iso.datetime().optional(),
});

export type JoiMemory = z.infer<typeof JoiMemorySchema>;

export const CreateMemorySchema = JoiMemorySchema.pick({
  category: true,
  value: true,
  sensitivity: true,
  source: true,
  confidence: true,
  expiresAt: true,
});

export type CreateMemoryInput = z.infer<typeof CreateMemorySchema>;

export const UpdateMemorySchema = JoiMemorySchema.pick({
  category: true,
  value: true,
  sensitivity: true,
  expiresAt: true,
}).partial();

export type UpdateMemoryInput = z.infer<typeof UpdateMemorySchema>;

export const TaskSchema = z.object({
  id: z.string().uuid(),
  userId: z.string().min(1),
  title: z.string().min(1).max(300),
  notes: z.string().max(4_000).default(""),
  status: z.enum(["todo", "doing", "done", "cancelled"]),
  priority: z.enum(["low", "medium", "high"]),
  dueAt: z.iso.datetime().optional(),
  ...TimestampFields,
});

export type Task = z.infer<typeof TaskSchema>;

export const CreateTaskSchema = TaskSchema.pick({
  title: true,
  notes: true,
  priority: true,
  dueAt: true,
});

export type CreateTaskInput = z.infer<typeof CreateTaskSchema>;

export const UpdateTaskSchema = TaskSchema.pick({
  title: true,
  notes: true,
  status: true,
  priority: true,
  dueAt: true,
}).partial();

export type UpdateTaskInput = z.infer<typeof UpdateTaskSchema>;

export const ApprovalSchema = z.object({
  id: z.string().uuid(),
  userId: z.string().min(1),
  idempotencyKey: z.string().min(8),
  risk: ActionRiskSchema,
  status: z.enum(["pending", "approved", "rejected", "expired", "executed", "failed"]),
  preview: ActionPreviewSchema,
  result: z.record(z.string(), z.unknown()).optional(),
  createdAt: z.iso.datetime(),
  decidedAt: z.iso.datetime().optional(),
});

export type Approval = z.infer<typeof ApprovalSchema>;

export const AutomationSchema = z.object({
  id: z.string().uuid(),
  userId: z.string().min(1),
  name: z.string().min(1).max(200),
  kind: z.enum(["morning_brief", "focus_nudge", "session_recap", "weekly_review", "custom"]),
  schedule: z.string().min(1).max(500),
  prompt: z.string().min(1).max(4_000),
  enabled: z.boolean(),
  nextRunAt: z.iso.datetime().optional(),
  lastRunAt: z.iso.datetime().optional(),
  ...TimestampFields,
});

export type Automation = z.infer<typeof AutomationSchema>;

export const CreateAutomationSchema = AutomationSchema.pick({
  name: true,
  kind: true,
  schedule: true,
  prompt: true,
  enabled: true,
  nextRunAt: true,
});

export type CreateAutomationInput = z.infer<typeof CreateAutomationSchema>;

export const UpdateAutomationSchema = AutomationSchema.pick({
  name: true,
  schedule: true,
  prompt: true,
  enabled: true,
  nextRunAt: true,
}).partial();

export type UpdateAutomationInput = z.infer<typeof UpdateAutomationSchema>;

export const AuditEventSchema = z.object({
  id: z.string().uuid(),
  userId: z.string().min(1),
  action: z.string().min(1),
  risk: ActionRiskSchema,
  status: z.enum(["started", "completed", "blocked", "failed"]),
  summary: z.string().min(1),
  metadata: z.record(z.string(), z.unknown()),
  createdAt: z.iso.datetime(),
});

export type AuditEvent = z.infer<typeof AuditEventSchema>;

export const UserProfileSchema = z.object({
  userId: z.string().min(1),
  displayName: z.string().min(1).max(120),
  timezone: z.string().min(1),
  locale: z.string().min(1),
  workingHours: z.object({ start: z.string(), end: z.string() }),
  warmth: z.number().int().min(0).max(100),
  humor: z.number().int().min(0).max(100),
  initiative: z.number().int().min(0).max(100),
  mode: z.enum(["work", "personal", "focus", "quiet"]),
  ...TimestampFields,
});

export type UserProfile = z.infer<typeof UserProfileSchema>;
