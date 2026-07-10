import { describe, expect, it } from "vitest";
import { InMemoryJoiStore } from "../src/store.js";
import { JoiService } from "../src/service.js";

describe("tenant-scoped store", () => {
  it("does not expose memories across users", () => {
    const store = new InMemoryJoiStore();
    store.createMemory("alice", {
      category: "preference",
      value: "Likes concise answers",
      sensitivity: "normal",
      source: "user_explicit",
      confidence: 1,
    });
    expect(store.listMemories("alice")).toHaveLength(1);
    expect(store.listMemories("bob")).toEqual([]);
  });

  it("rejects cross-tenant deletion", () => {
    const store = new InMemoryJoiStore();
    const task = store.createTask("alice", {
      title: "Private task",
      notes: "",
      priority: "medium",
    });
    expect(store.deleteTask("bob", task.id)).toBe(false);
    expect(store.listTasks("alice")).toHaveLength(1);
  });

  it("audits reversible mutations without exposing another tenant's log", () => {
    const service = new JoiService();
    const task = service.createTask("alice", { title: "Audit me", notes: "", priority: "low" });
    service.updateTask("alice", task.id, { status: "done" });
    service.deleteTask("alice", task.id);
    const automation = service.createAutomation("alice", {
      name: "Weekly review",
      kind: "weekly_review",
      schedule: "0 16 * * 5",
      prompt: "Review the week.",
      enabled: true,
    });
    service.updateAutomation("alice", automation.id, { enabled: false });
    service.deleteAutomation("alice", automation.id);
    const memory = service.createMemory("alice", {
      category: "preference",
      value: "Warm summaries",
      sensitivity: "normal",
      source: "user_explicit",
      confidence: 1,
    });
    service.updateMemory("alice", memory.id, { value: "Concise summaries" });
    expect(service.store.listAudit("alice").map((item) => item.action)).toEqual(expect.arrayContaining([
      "joi.tasks.create",
      "joi.tasks.update",
      "joi.tasks.delete",
      "joi.automation.create",
      "joi.automation.update",
      "joi.automation.delete",
      "joi.memory.update",
    ]));
    expect(service.store.listAudit("bob")).toEqual([]);
  });
});
