import { describe, expect, it } from "vitest";
import { evaluateActionRisk } from "../src/policy.js";

describe("action policy", () => {
  it("allows reads without approval", () => {
    expect(evaluateActionRisk("read")).toEqual({
      allowed: true,
      requiresApproval: false,
      reason: "Read-only action.",
    });
  });

  it("requires approval for consequential external writes", () => {
    expect(evaluateActionRisk("external_write")).toMatchObject({
      allowed: true,
      requiresApproval: true,
    });
  });

  it.each(["destructive", "financial"] as const)("blocks %s actions in the MVP", (risk) => {
    expect(evaluateActionRisk(risk)).toMatchObject({ allowed: false, requiresApproval: true });
  });
});
