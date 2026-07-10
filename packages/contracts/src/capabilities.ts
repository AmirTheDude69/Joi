export const capabilityGroups = {
  intelligence: ["INT-01", "INT-02", "INT-03", "INT-04", "INT-05", "INT-06", "INT-07", "INT-08", "INT-09", "INT-10", "INT-11", "INT-12", "INT-13", "INT-14", "INT-15"],
  memory: ["MEM-01", "MEM-02", "MEM-03", "MEM-04", "MEM-05", "MEM-06", "MEM-07", "MEM-08", "MEM-09", "MEM-10", "MEM-11", "MEM-12", "MEM-13", "MEM-14", "MEM-15"],
  productivity: ["PRO-01", "PRO-02", "PRO-03", "PRO-04", "PRO-05", "PRO-06", "PRO-07", "PRO-08", "PRO-09", "PRO-10", "PRO-11", "PRO-12", "PRO-13", "PRO-14", "PRO-15", "PRO-16", "PRO-17", "PRO-18", "PRO-19", "PRO-20"],
  companion: ["COM-01", "COM-02", "COM-03", "COM-04", "COM-05", "COM-06", "COM-07", "COM-08", "COM-09", "COM-10", "COM-11", "COM-12", "COM-13", "COM-14", "COM-15"],
  automation: ["AUT-01", "AUT-02", "AUT-03", "AUT-04", "AUT-05", "AUT-06", "AUT-07", "AUT-08", "AUT-09", "AUT-10", "AUT-11", "AUT-12", "AUT-13", "AUT-14", "AUT-15"],
  avatar: ["AVA-01", "AVA-02", "AVA-03", "AVA-04", "AVA-05", "AVA-06", "AVA-07", "AVA-08", "AVA-09", "AVA-10", "AVA-11", "AVA-12", "AVA-13", "AVA-14", "AVA-15"],
  integrations: ["INTG-01", "INTG-02", "INTG-03", "INTG-04", "INTG-05", "INTG-06", "INTG-07", "INTG-08", "INTG-09", "INTG-10", "INTG-11", "INTG-12", "INTG-13", "INTG-14", "INTG-15", "INTG-16"],
  surfaces: ["SURF-01", "SURF-02", "SURF-03", "SURF-04", "SURF-05", "SURF-06", "SURF-07", "SURF-08", "SURF-09", "SURF-10"],
  business: ["BIZ-01", "BIZ-02", "BIZ-03", "BIZ-04", "BIZ-05", "BIZ-06", "BIZ-07", "BIZ-08", "BIZ-09", "BIZ-10"],
} as const;

export type CapabilityGroup = keyof typeof capabilityGroups;
export type CapabilityId = (typeof capabilityGroups)[CapabilityGroup][number];

export const mvpCapabilityIds = new Set<CapabilityId>([
  "INT-01", "INT-02", "INT-03", "INT-04", "INT-05", "INT-06",
  "MEM-01", "MEM-02", "MEM-03", "MEM-04", "MEM-05", "MEM-06",
  "PRO-01", "PRO-02", "PRO-03", "PRO-04", "PRO-05", "PRO-06", "PRO-07", "PRO-08", "PRO-09", "PRO-10", "PRO-11", "PRO-12",
  "COM-01", "COM-02", "COM-03", "COM-04", "COM-05",
  "AUT-01", "AUT-02", "AUT-03", "AUT-04",
  "AVA-01", "AVA-02", "AVA-03",
  "INTG-01", "INTG-02", "INTG-03",
  "SURF-01", "SURF-02",
  "BIZ-01", "BIZ-02", "BIZ-03", "BIZ-04",
]);

export type CapabilityDescriptor = {
  id: CapabilityId;
  group: CapabilityGroup;
  release: "mvp" | "later";
  enabled: boolean;
};

export function capabilityCatalog(overrides: Partial<Record<CapabilityId, boolean>> = {}): CapabilityDescriptor[] {
  return Object.entries(capabilityGroups).flatMap(([group, ids]) =>
    ids.map((id) => ({
      id,
      group: group as CapabilityGroup,
      release: mvpCapabilityIds.has(id) ? "mvp" as const : "later" as const,
      enabled: overrides[id] ?? mvpCapabilityIds.has(id),
    })),
  );
}
