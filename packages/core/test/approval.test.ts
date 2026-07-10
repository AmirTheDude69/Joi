import { describe, expect, it } from "vitest";
import { JoiService } from "../src/service.js";

describe("approval execution", () => {
  it("does not send before approval and executes exactly once", async () => {
    const service = new JoiService();
    const input = {
      to: ["maya@example.com"],
      subject: "Hello",
      body: "A safe draft",
      idempotencyKey: "email-demo-12345",
    };
    const first = service.requestEmailSend("alice", input);
    const duplicate = service.requestEmailSend("alice", input);

    expect(first.status).toBe("pending");
    expect(duplicate.id).toBe(first.id);
    expect(service.store.listAudit("alice").some((item) => item.status === "completed")).toBe(false);

    const executed = await service.approve("alice", first.id);
    expect(executed?.status).toBe("executed");
    expect(executed?.result).toMatchObject({ accepted: ["maya@example.com"] });

    const secondApproval = await service.approve("alice", first.id);
    expect(secondApproval?.result).toEqual(executed?.result);
  });

  it("cannot approve another tenant's action", async () => {
    const service = new JoiService();
    const approval = service.requestEmailSend("alice", {
      to: ["maya@example.com"],
      subject: "Hello",
      body: "Private",
      idempotencyKey: "tenant-demo-12345",
    });
    expect(await service.approve("bob", approval.id)).toBeUndefined();
    expect(service.store.listApprovals("alice")[0]?.status).toBe("pending");
  });
});
