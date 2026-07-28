import "dotenv/config";
import cors from "cors";
import express from "express";
import {
  CreateAutomationSchema,
  CreateMemorySchema,
  CreateTaskSchema,
  StartRunSchema,
  UpdateTaskSchema,
  UpdateAutomationSchema,
  UpdateMemorySchema,
} from "@joi/contracts";
import { JoiService, runDemoAgent } from "@joi/core";
import { requireUser, userIdFrom } from "./auth.js";
import { handleMcpRequest } from "./mcp.js";
import { runOpenAIAgent } from "./openai-agent.js";
import { RunBroker } from "./run-broker.js";

const app = express();
const service = new JoiService();
const runs = new RunBroker();
const port = Number(process.env.PORT ?? 8787);

app.disable("x-powered-by");
app.use(cors({ origin: process.env.JOI_WEB_ORIGIN ?? "http://localhost:3000" }));
app.use(express.json({ limit: "2mb" }));

app.get("/health", (_request, response) => {
  response.json({
    ok: true,
    service: "joi-agent",
    mode: process.env.OPENAI_API_KEY ? "openai" : "demo",
    launchGates: {
      likenessRelease: process.env.JOI_LIKENESS_RELEASE_APPROVED === "true",
      trademarkClearance: process.env.JOI_TRADEMARK_CLEARANCE_APPROVED === "true",
      productionAuth: process.env.JOI_ALLOW_DEMO_MODE === "false",
    },
  });
});

app.use(["/v1", "/mcp", "/oauth"], requireUser);

app.post("/v1/runs", (request, response) => {
  const userId = userIdFrom(request);
  const input = StartRunSchema.parse(request.body);
  const run = runs.create(userId, input.threadId);
  response.status(202).json(run);

  queueMicrotask(async () => {
    const emit = (event: Parameters<typeof runs.emit>[2]) => runs.emit(userId, run.runId, event);
    emit({ type: "state.changed", state: "listening" });
    try {
      if (process.env.OPENAI_API_KEY) {
        await runOpenAIAgent(service, userId, input.message, emit);
      } else {
        await runDemoAgent(service, userId, input.message, emit);
      }
      emit({ type: "run.completed", runId: run.runId });
    } catch (error) {
      emit({ type: "state.changed", state: "failure" });
      emit({
        type: "run.failed",
        runId: run.runId,
        safeMessage: error instanceof Error ? error.message : "Joi could not complete that run.",
      });
    }
  });
});

app.get("/v1/runs/:runId/events", (request, response) => {
  const userId = userIdFrom(request);
  response.status(200);
  response.setHeader("Content-Type", "text/event-stream");
  response.setHeader("Cache-Control", "no-cache, no-transform");
  response.setHeader("Connection", "keep-alive");
  response.flushHeaders();

  try {
    const unsubscribe = runs.subscribe(userId, request.params.runId, (event) => {
      response.write(`event: ${event.type}\n`);
      response.write(`data: ${JSON.stringify(event)}\n\n`);
      if (event.type === "run.completed" || event.type === "run.failed") response.end();
    });
    request.on("close", unsubscribe);
    if (runs.isComplete(userId, request.params.runId)) response.end();
  } catch (error) {
    response.write(`event: run.failed\ndata: ${JSON.stringify({ error: "Run not found" })}\n\n`);
    response.end();
  }
});

app.get("/v1/profile", (request, response) => response.json(service.store.getProfile(userIdFrom(request))));
app.patch("/v1/profile", (request, response) => response.json(service.updateProfile(userIdFrom(request), request.body)));

app.get("/v1/memories", (request, response) => response.json(service.listMemories(userIdFrom(request))));
app.post("/v1/memories", (request, response) => response.status(201).json(service.createMemory(userIdFrom(request), CreateMemorySchema.parse(request.body))));
app.patch("/v1/memories/:id", (request, response) => {
  const memory = service.updateMemory(userIdFrom(request), request.params.id, UpdateMemorySchema.parse(request.body));
  response.status(memory ? 200 : 404).json(memory ?? { error: "Memory not found" });
});
app.delete("/v1/memories/:id", (request, response) => response.status(service.deleteMemory(userIdFrom(request), request.params.id) ? 204 : 404).end());

app.get("/v1/tasks", (request, response) => response.json(service.listTasks(userIdFrom(request))));
app.post("/v1/tasks", (request, response) => response.status(201).json(service.createTask(userIdFrom(request), CreateTaskSchema.parse(request.body))));
app.patch("/v1/tasks/:id", (request, response) => {
  const task = service.updateTask(userIdFrom(request), request.params.id, UpdateTaskSchema.parse(request.body));
  response.status(task ? 200 : 404).json(task ?? { error: "Task not found" });
});
app.delete("/v1/tasks/:id", (request, response) => response.status(service.deleteTask(userIdFrom(request), request.params.id) ? 204 : 404).end());

app.get("/v1/automations", (request, response) => response.json(service.listAutomations(userIdFrom(request))));
app.post("/v1/automations", (request, response) => response.status(201).json(service.createAutomation(userIdFrom(request), CreateAutomationSchema.parse(request.body))));
app.patch("/v1/automations/:id", (request, response) => {
  const automation = service.updateAutomation(userIdFrom(request), request.params.id, UpdateAutomationSchema.parse(request.body));
  response.status(automation ? 200 : 404).json(automation ?? { error: "Automation not found" });
});
app.delete("/v1/automations/:id", (request, response) => response.status(service.deleteAutomation(userIdFrom(request), request.params.id) ? 204 : 404).end());

app.get("/v1/approvals", (request, response) => response.json(service.store.listApprovals(userIdFrom(request))));
app.post("/v1/approvals/:id/approve", async (request, response) => {
  const approval = await service.approve(userIdFrom(request), request.params.id);
  response.status(approval ? 200 : 404).json(approval ?? { error: "Approval not found" });
});
app.post("/v1/approvals/:id/reject", (request, response) => {
  const approval = service.reject(userIdFrom(request), request.params.id);
  response.status(approval ? 200 : 404).json(approval ?? { error: "Approval not found" });
});

app.get("/v1/audit", (request, response) => response.json(service.store.listAudit(userIdFrom(request))));
app.get("/v1/connectors", (_request, response) => response.json(service.google.status()));
app.get("/v1/capabilities", (request, response) => response.json(service.listCapabilities(userIdFrom(request))));
app.patch("/v1/capabilities/:id", (request, response) => {
  if (typeof request.body?.enabled !== "boolean") throw new Error("enabled must be a boolean");
  response.json(service.setCapability(userIdFrom(request), request.params.id, request.body.enabled));
});
app.get("/v1/account/export", (request, response) => {
  const userId = userIdFrom(request);
  response.json({
    profile: service.store.getProfile(userId),
    memories: service.listMemories(userId),
    tasks: service.listTasks(userId),
    automations: service.listAutomations(userId),
    capabilities: service.listCapabilities(userId),
    approvals: service.store.listApprovals(userId),
    audit: service.store.listAudit(userId),
  });
});
app.delete("/v1/account", (request, response) => {
  service.store.deleteUserData(userIdFrom(request));
  response.status(204).end();
});

app.get("/oauth/google/start", (_request, response) => {
  response.status(501).json({
    error: "Google OAuth is a launch gate. Configure GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, token encryption, and a production identity provider.",
    code: "google_oauth_not_configured",
  });
});
app.get("/oauth/google/callback", (_request, response) => response.status(501).json({ error: "Google OAuth callback is not enabled in demo mode." }));

app.post("/mcp", async (request, response) => {
  try {
    await handleMcpRequest(service, request, response);
  } catch (error) {
    if (!response.headersSent) {
      response.status(500).json({
        jsonrpc: "2.0",
        id: null,
        error: { code: -32603, message: error instanceof Error ? error.message : "MCP request failed" },
      });
    }
  }
});
app.get("/mcp", (_request, response) => response.status(405).set("Allow", "POST").send("Method Not Allowed"));
app.delete("/mcp", (_request, response) => response.status(405).set("Allow", "POST").send("Method Not Allowed"));

app.use((error: unknown, _request: express.Request, response: express.Response, _next: express.NextFunction) => {
  const message = error instanceof Error ? error.message : "Invalid request";
  response.status(400).json({ error: message, code: "invalid_request" });
});

app.listen(port, () => {
  console.log(`Joi agent listening on http://localhost:${port}`);
});
