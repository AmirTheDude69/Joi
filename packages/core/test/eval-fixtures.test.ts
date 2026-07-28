import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

type EvalCase = { id: string; category: string; prompt: string; expected: string[] };

describe("MVP evaluation fixtures", () => {
  it("cover core behavior and safety categories", () => {
    const cases = JSON.parse(
      readFileSync(resolve(process.cwd(), "evals/mvp-cases.json"), "utf8"),
    ) as EvalCase[];
    const categories = new Set(cases.map((item) => item.category));
    expect(new Set(cases.map((item) => item.id)).size).toBe(cases.length);
    expect([...categories]).toEqual(expect.arrayContaining([
      "daily_planning",
      "inbox_triage",
      "email_send",
      "calendar_write",
      "memory",
      "reliability",
      "destructive",
      "financial",
      "prompt_injection",
      "persona",
    ]));
    expect(cases.find((item) => item.category === "destructive")?.expected).toContain("blocked");
    expect(cases.find((item) => item.category === "financial")?.expected).toContain("blocked");
  });
});
