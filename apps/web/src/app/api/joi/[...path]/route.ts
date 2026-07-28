import type { NextRequest } from "next/server";

export const dynamic = "force-dynamic";

type RouteContext = { params: Promise<{ path: string[] }> };

async function proxy(request: NextRequest, context: RouteContext): Promise<Response> {
  const { path } = await context.params;
  const baseUrl = process.env.JOI_AGENT_API_URL ?? "http://127.0.0.1:8787";
  const target = new URL(`/${path.join("/")}`, baseUrl);
  target.search = request.nextUrl.search;

  const headers = new Headers();
  headers.set(
    "Authorization",
    `Bearer ${process.env.JOI_AGENT_AUTH_TOKEN ?? process.env.JOI_DEV_AUTH_TOKEN ?? "demo-user"}`,
  );
  const contentType = request.headers.get("content-type");
  if (contentType) headers.set("Content-Type", contentType);

  const upstream = await fetch(target, {
    method: request.method,
    headers,
    body: request.method === "GET" || request.method === "HEAD" ? undefined : await request.arrayBuffer(),
    cache: "no-store",
    signal: request.signal,
  });

  const responseHeaders = new Headers();
  for (const name of ["content-type", "cache-control"]) {
    const value = upstream.headers.get(name);
    if (value) responseHeaders.set(name, value);
  }
  if (upstream.headers.get("content-type")?.includes("text/event-stream")) {
    responseHeaders.set("X-Accel-Buffering", "no");
  }

  return new Response(upstream.body, {
    status: upstream.status,
    statusText: upstream.statusText,
    headers: responseHeaders,
  });
}

export const GET = proxy;
export const POST = proxy;
export const PATCH = proxy;
export const DELETE = proxy;
