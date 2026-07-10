import type { ActionRisk } from "@joi/contracts";

export type PolicyDecision = {
  allowed: boolean;
  requiresApproval: boolean;
  reason: string;
};

export function evaluateActionRisk(risk: ActionRisk): PolicyDecision {
  switch (risk) {
    case "read":
      return { allowed: true, requiresApproval: false, reason: "Read-only action." };
    case "reversible_write":
      return {
        allowed: true,
        requiresApproval: false,
        reason: "Reversible in-product or draft action; record it in the audit log.",
      };
    case "external_write":
      return {
        allowed: true,
        requiresApproval: true,
        reason: "Consequential external write requires an exact user preview and approval.",
      };
    case "destructive":
      return {
        allowed: false,
        requiresApproval: true,
        reason: "Destructive actions are disabled in the MVP.",
      };
    case "financial":
      return {
        allowed: false,
        requiresApproval: true,
        reason: "Financial actions are disabled in the MVP.",
      };
  }
}
