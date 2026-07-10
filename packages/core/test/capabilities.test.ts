import { describe, expect, it } from "vitest";
import { capabilityCatalog, mvpCapabilityIds } from "@joi/contracts";
import { JoiService } from "../src/service.js";

describe("capability flags", () => {
  it("enables the frozen MVP and keeps later capabilities off", () => {
    const catalog = capabilityCatalog();
    expect(catalog).toHaveLength(131);
    expect(catalog.filter((item) => item.enabled).map((item) => item.id).sort())
      .toEqual([...mvpCapabilityIds].sort());
    expect(catalog.find((item) => item.id === "AVA-05")?.enabled).toBe(false);
    expect(catalog.find((item) => item.id === "SURF-01")?.enabled).toBe(true);
  });

  it("lets users disable MVP capabilities but keeps later releases gated", () => {
    const service = new JoiService();
    expect(service.setCapability("alice", "PRO-01", false).enabled).toBe(false);
    expect(service.listCapabilities("alice").find((item) => item.id === "PRO-01")?.enabled).toBe(false);
    expect(service.listCapabilities("bob").find((item) => item.id === "PRO-01")?.enabled).toBe(true);
    expect(() => service.setCapability("alice", "AVA-05", true)).toThrow("later-phase release gate");
  });
});
