import { z } from "zod";

export const joiAgentStates = [
  "idle",
  "listening",
  "waiting_for_user",
  "working",
  "reviewing",
  "success",
  "failure",
  "looking",
] as const;

export const JoiAgentStateSchema = z.enum(joiAgentStates);
export type JoiAgentState = z.infer<typeof JoiAgentStateSchema>;

export const actionRisks = [
  "read",
  "reversible_write",
  "external_write",
  "destructive",
  "financial",
] as const;

export const ActionRiskSchema = z.enum(actionRisks);
export type ActionRisk = z.infer<typeof ActionRiskSchema>;

export const ActionPreviewSchema = z.object({
  action: z.string().min(1),
  label: z.string().min(1),
  summary: z.string().min(1),
  payload: z.record(z.string(), z.unknown()),
  expiresAt: z.iso.datetime(),
});

export type ActionPreview = z.infer<typeof ActionPreviewSchema>;

export const MemoryProposalSchema = z.object({
  category: z.enum(["preference", "person", "date", "routine", "project", "goal"]),
  value: z.string().min(1).max(2_000),
  sensitivity: z.enum(["normal", "sensitive"]),
  reason: z.string().min(1).max(500),
});

export type MemoryProposal = z.infer<typeof MemoryProposalSchema>;

export const JoiRunEventSchema = z.discriminatedUnion("type", [
  z.object({ type: z.literal("message.delta"), text: z.string() }),
  z.object({ type: z.literal("state.changed"), state: JoiAgentStateSchema }),
  z.object({
    type: z.literal("tool.started"),
    tool: z.string(),
    risk: ActionRiskSchema,
  }),
  z.object({
    type: z.literal("tool.completed"),
    tool: z.string(),
    summary: z.string(),
  }),
  z.object({
    type: z.literal("approval.required"),
    approvalId: z.string().uuid(),
    preview: ActionPreviewSchema,
  }),
  z.object({
    type: z.literal("memory.proposed"),
    memory: MemoryProposalSchema,
  }),
  z.object({ type: z.literal("run.completed"), runId: z.string().uuid() }),
  z.object({
    type: z.literal("run.failed"),
    runId: z.string().uuid(),
    safeMessage: z.string(),
  }),
]);

export type JoiRunEvent = z.infer<typeof JoiRunEventSchema>;

export const StartRunSchema = z.object({
  message: z.string().min(1).max(20_000),
  threadId: z.string().uuid().optional(),
  mode: z.enum(["work", "personal", "focus", "quiet"]).default("personal"),
});

export type StartRunInput = z.infer<typeof StartRunSchema>;

export const StartRunResponseSchema = z.object({
  runId: z.string().uuid(),
  threadId: z.string().uuid(),
});

export type StartRunResponse = z.infer<typeof StartRunResponseSchema>;

export type AvatarFrame = {
  row: number;
  column: number;
  state: JoiAgentState | "greeting" | "moving_left" | "moving_right";
};
