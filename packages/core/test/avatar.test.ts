import { describe, expect, it } from "vitest";
import { animationForAgentState, lookFrameForDegrees } from "../src/avatar.js";

describe("avatar mapping", () => {
  it("maps operational states to the intended Joi rows", () => {
    expect(animationForAgentState("working")).toBe("working");
    expect(animationForAgentState("waiting_for_user")).toBe("waiting");
    expect(animationForAgentState("success")).toBe("jumping");
    expect(animationForAgentState("failure")).toBe("failed");
  });

  it("maps all four cardinals into the two look rows", () => {
    expect(lookFrameForDegrees(0)).toMatchObject({ row: 9, column: 0 });
    expect(lookFrameForDegrees(90)).toMatchObject({ row: 9, column: 4 });
    expect(lookFrameForDegrees(180)).toMatchObject({ row: 10, column: 0 });
    expect(lookFrameForDegrees(270)).toMatchObject({ row: 10, column: 4 });
  });
});
