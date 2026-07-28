import type { NextFunction, Request, Response } from "express";

declare global {
  namespace Express {
    interface Request {
      joiUserId?: string;
    }
  }
}

export function requireUser(request: Request, response: Response, next: NextFunction): void {
  const allowDemo = process.env.JOI_ALLOW_DEMO_MODE !== "false";
  const expected = process.env.JOI_DEV_AUTH_TOKEN ?? "demo-user";
  const authorization = request.header("authorization") ?? "";
  const token = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";

  if (!allowDemo) {
    response.status(503).json({
      error: "Production identity provider is not configured.",
      code: "auth_launch_gate",
    });
    return;
  }

  if (token !== expected) {
    response.status(401).json({ error: "Unauthorized", code: "invalid_bearer_token" });
    return;
  }

  request.joiUserId = "demo-user";
  next();
}

export function userIdFrom(request: Request): string {
  if (!request.joiUserId) throw new Error("Authenticated user is missing.");
  return request.joiUserId;
}
