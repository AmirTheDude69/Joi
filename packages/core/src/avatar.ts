import type { AvatarFrame, JoiAgentState } from "@joi/contracts";

export const animationRows = {
  idle: { row: 0, frames: 6, durations: [280, 110, 110, 140, 140, 320] },
  "running-right": { row: 1, frames: 8, durations: [120, 120, 120, 120, 120, 120, 120, 220] },
  "running-left": { row: 2, frames: 8, durations: [120, 120, 120, 120, 120, 120, 120, 220] },
  waving: { row: 3, frames: 4, durations: [140, 140, 140, 280] },
  jumping: { row: 4, frames: 5, durations: [140, 140, 140, 140, 280] },
  failed: { row: 5, frames: 8, durations: [140, 140, 140, 140, 140, 140, 140, 240] },
  waiting: { row: 6, frames: 6, durations: [150, 150, 150, 150, 150, 260] },
  working: { row: 7, frames: 6, durations: [120, 120, 120, 120, 120, 220] },
  review: { row: 8, frames: 6, durations: [150, 150, 150, 150, 150, 280] },
} as const;

export type AnimationName = keyof typeof animationRows;

export function animationForAgentState(state: JoiAgentState): AnimationName {
  switch (state) {
    case "idle":
      return "idle";
    case "listening":
    case "waiting_for_user":
      return "waiting";
    case "working":
      return "working";
    case "reviewing":
      return "review";
    case "success":
      return "jumping";
    case "failure":
      return "failed";
    case "looking":
      return "idle";
  }
}

export function lookFrameForDegrees(degrees: number): AvatarFrame {
  const normalized = ((degrees % 360) + 360) % 360;
  const index = Math.round(normalized / 22.5) % 16;
  return {
    row: index < 8 ? 9 : 10,
    column: index % 8,
    state: "looking",
  };
}
