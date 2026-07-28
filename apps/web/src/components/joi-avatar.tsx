"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { JoiAgentState } from "@joi/contracts";

type Animation = {
  row: number;
  frames: number;
  durations: readonly number[];
};

const animations = {
  idle: { row: 0, frames: 6, durations: [280, 110, 110, 140, 140, 320] },
  waving: { row: 3, frames: 4, durations: [140, 140, 140, 280] },
  jumping: { row: 4, frames: 5, durations: [140, 140, 140, 140, 280] },
  failed: { row: 5, frames: 8, durations: [140, 140, 140, 140, 140, 140, 140, 240] },
  waiting: { row: 6, frames: 6, durations: [150, 150, 150, 150, 150, 260] },
  working: { row: 7, frames: 6, durations: [120, 120, 120, 120, 120, 220] },
  review: { row: 8, frames: 6, durations: [150, 150, 150, 150, 150, 280] },
} as const satisfies Record<string, Animation>;

function animationForState(state: JoiAgentState, celebrationFinished: boolean): Animation {
  switch (state) {
    case "listening":
    case "waiting_for_user":
      return animations.waiting;
    case "working":
      return animations.working;
    case "reviewing":
      return animations.review;
    case "success":
      return celebrationFinished ? animations.waving : animations.jumping;
    case "failure":
      return animations.failed;
    case "idle":
    case "looking":
      return animations.idle;
  }
}

function lookCell(element: HTMLDivElement, clientX: number, clientY: number): { row: number; frame: number } {
  const bounds = element.getBoundingClientRect();
  const dx = clientX - (bounds.left + bounds.width / 2);
  const dy = clientY - (bounds.top + bounds.height / 2);
  const degrees = ((Math.atan2(dx, -dy) * 180) / Math.PI + 360) % 360;
  const index = Math.round(degrees / 22.5) % 16;
  return { row: index < 8 ? 9 : 10, frame: index % 8 };
}

function AnimatedJoiAvatar({
  state,
  reducedMotion = false,
}: {
  state: JoiAgentState;
  reducedMotion?: boolean;
}) {
  const [frame, setFrame] = useState(0);
  const [celebrationFinished, setCelebrationFinished] = useState(false);
  const [look, setLook] = useState<{ row: number; frame: number } | null>(null);
  const [systemReducedMotion, setSystemReducedMotion] = useState(false);
  const spriteRef = useRef<HTMLDivElement>(null);
  const animation = useMemo(
    () => animationForState(state, celebrationFinished),
    [state, celebrationFinished],
  );
  const shouldReduceMotion = reducedMotion || systemReducedMotion;

  useEffect(() => {
    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setSystemReducedMotion(media.matches);
    update();
    media.addEventListener("change", update);
    return () => media.removeEventListener("change", update);
  }, []);

  useEffect(() => {
    if (state !== "success" || shouldReduceMotion) return;
    const timeout = window.setTimeout(() => setCelebrationFinished(true), 980);
    return () => window.clearTimeout(timeout);
  }, [state, shouldReduceMotion]);

  useEffect(() => {
    if (shouldReduceMotion || look) return;
    let cancelled = false;
    let timeout: number | undefined;
    const advance = (current: number) => {
      timeout = window.setTimeout(() => {
        if (cancelled) return;
        const next = (current + 1) % animation.frames;
        setFrame(next);
        advance(next);
      }, animation.durations[current] ?? 160);
    };
    advance(0);
    return () => {
      cancelled = true;
      if (timeout !== undefined) window.clearTimeout(timeout);
    };
  }, [animation, look, shouldReduceMotion]);

  const displayed = look ?? { row: animation.row, frame: frame % animation.frames };

  return (
    <div className="relative grid place-items-center" aria-live="polite">
      <div className="avatar-glow" aria-hidden="true" />
      <div
        ref={spriteRef}
        role="img"
        aria-label={`Joi is ${state.replaceAll("_", " ")}`}
        className="joi-sprite relative z-10 cursor-crosshair"
        style={{
          backgroundPosition: `${-displayed.frame * 192}px ${-displayed.row * 208}px`,
        }}
        onPointerMove={(event) => {
          if (state !== "idle" || shouldReduceMotion || !spriteRef.current) return;
          setLook(lookCell(spriteRef.current, event.clientX, event.clientY));
        }}
        onPointerLeave={() => setLook(null)}
      />
      <span className="mt-1 rounded-full border border-white/70 bg-white/75 px-3 py-1 text-[11px] font-medium tracking-wide text-stone-600 shadow-sm backdrop-blur">
        {state.replaceAll("_", " ")}
      </span>
    </div>
  );
}

export function JoiAvatar(props: { state: JoiAgentState; reducedMotion?: boolean }) {
  return <AnimatedJoiAvatar key={`${props.state}-${props.reducedMotion === true}`} {...props} />;
}
