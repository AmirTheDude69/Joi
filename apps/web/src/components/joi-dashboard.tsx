"use client";

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import type {
  Approval,
  Automation,
  CapabilityDescriptor,
  ConnectorStatus,
  JoiAgentState,
  JoiMemory,
  JoiRunEvent,
  StartRunResponse,
  Task,
  UserProfile,
} from "@joi/contracts";
import {
  BellRing,
  Bot,
  CalendarDays,
  Check,
  CheckCircle2,
  ChevronRight,
  Clock3,
  Database,
  FileText,
  Heart,
  Inbox,
  ListTodo,
  LoaderCircle,
  LockKeyhole,
  MemoryStick,
  MessageCircle,
  Plus,
  Pencil,
  RefreshCw,
  Send,
  Settings2,
  ShieldCheck,
  Sparkles,
  Trash2,
  X,
} from "lucide-react";
import { JoiAvatar } from "@/components/joi-avatar";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import { Switch } from "@/components/ui/switch";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";

const API = "/api/joi/v1";

type ChatMessage = { id: string; role: "assistant" | "user"; text: string };
type TabName = "chat" | "tasks" | "memory" | "approvals" | "automations" | "settings";

const quickPrompts = [
  { icon: CalendarDays, label: "Plan my day", prompt: "Plan my day around my calendar and priorities." },
  { icon: Inbox, label: "Brief my inbox", prompt: "Brief my inbox and identify the most actionable message." },
  { icon: ListTodo, label: "Capture a task", prompt: "Create a task to finish the Joi launch checklist." },
  { icon: Send, label: "Draft a send", prompt: "Send an email with the latest Joi launch checklist." },
];

const automationTemplates = [
  { name: "Weekday morning brief", kind: "morning_brief", schedule: "0 8 * * 1-5", prompt: "Prepare my agenda, priorities, conflicts, and important unread mail." },
  { name: "Focus-start nudge", kind: "focus_nudge", schedule: "0 9 * * 1-5", prompt: "Ask me to choose one focus outcome and start a 50-minute session." },
  { name: "End-of-session recap", kind: "session_recap", schedule: "0 17 * * 1-5", prompt: "Summarize completed work and capture the next action." },
  { name: "Weekly review", kind: "weekly_review", schedule: "0 16 * * 5", prompt: "Review wins, loose ends, and next week's priorities." },
] as const;

async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...init,
    headers: { "Content-Type": "application/json", ...init?.headers },
    cache: "no-store",
  });
  if (!response.ok) {
    const data = (await response.json().catch(() => ({}))) as { error?: string };
    throw new Error(data.error ?? `Request failed (${response.status})`);
  }
  if (response.status === 204) return undefined as T;
  return response.json() as Promise<T>;
}

function formatDate(value?: string): string {
  if (!value) return "Not scheduled";
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

function messageId(): string {
  return typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random()}`;
}

function EmptyState({ icon: Icon, title, copy }: { icon: typeof Sparkles; title: string; copy: string }) {
  return (
    <div className="grid min-h-48 place-items-center rounded-2xl border border-dashed border-stone-200 bg-white/45 p-8 text-center">
      <div>
        <Icon className="mx-auto mb-3 size-6 text-orange-700" />
        <p className="font-medium text-stone-800">{title}</p>
        <p className="mt-1 max-w-sm text-sm text-stone-500">{copy}</p>
      </div>
    </div>
  );
}

export function JoiDashboard() {
  const [activeTab, setActiveTab] = useState<TabName>("chat");
  const [agentState, setAgentState] = useState<JoiAgentState>("idle");
  const [messages, setMessages] = useState<ChatMessage[]>([
    {
      id: "welcome",
      role: "assistant",
      text: "Hi, I’m Joi — your AI daily companion. I can help plan, remember, and prepare actions, but anything consequential waits for your approval.",
    },
  ]);
  const [draft, setDraft] = useState("");
  const [threadId, setThreadId] = useState<string>();
  const [busy, setBusy] = useState(false);
  const [toolStatus, setToolStatus] = useState<string>();
  const [error, setError] = useState<string>();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [memories, setMemories] = useState<JoiMemory[]>([]);
  const [approvals, setApprovals] = useState<Approval[]>([]);
  const [automations, setAutomations] = useState<Automation[]>([]);
  const [connectors, setConnectors] = useState<ConnectorStatus[]>([]);
  const [capabilities, setCapabilities] = useState<CapabilityDescriptor[]>([]);
  const [profile, setProfile] = useState<UserProfile>();
  const [newTask, setNewTask] = useState("");
  const [newMemory, setNewMemory] = useState("");
  const [editingMemoryId, setEditingMemoryId] = useState<string>();
  const [editingMemoryValue, setEditingMemoryValue] = useState("");
  const [reducedMotion, setReducedMotion] = useState(false);
  const [connected, setConnected] = useState(true);
  const messagesEnd = useRef<HTMLDivElement>(null);

  const refresh = useCallback(async () => {
    const results = await Promise.allSettled([
      api<Task[]>("/tasks"),
      api<JoiMemory[]>("/memories"),
      api<Approval[]>("/approvals"),
      api<Automation[]>("/automations"),
      api<ConnectorStatus[]>("/connectors"),
      api<UserProfile>("/profile"),
      api<CapabilityDescriptor[]>("/capabilities"),
    ]);
    const [taskResult, memoryResult, approvalResult, automationResult, connectorResult, profileResult, capabilityResult] = results;
    if (taskResult.status === "fulfilled") setTasks(taskResult.value);
    if (memoryResult.status === "fulfilled") setMemories(memoryResult.value);
    if (approvalResult.status === "fulfilled") setApprovals(approvalResult.value);
    if (automationResult.status === "fulfilled") setAutomations(automationResult.value);
    if (connectorResult.status === "fulfilled") setConnectors(connectorResult.value);
    if (profileResult.status === "fulfilled") setProfile(profileResult.value);
    if (capabilityResult.status === "fulfilled") setCapabilities(capabilityResult.value);
    setConnected(results.some((result) => result.status === "fulfilled"));
  }, []);

  useEffect(() => {
    const timeout = window.setTimeout(() => void refresh(), 0);
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => undefined);
    }
    return () => window.clearTimeout(timeout);
  }, [refresh]);

  useEffect(() => {
    messagesEnd.current?.scrollIntoView({ behavior: reducedMotion ? "auto" : "smooth" });
  }, [messages, reducedMotion]);

  const pendingApprovals = useMemo(
    () => approvals.filter((approval) => approval.status === "pending"),
    [approvals],
  );

  const handleEvent = useCallback((event: JoiRunEvent, assistantId: string) => {
    switch (event.type) {
      case "message.delta":
        setMessages((current) =>
          current.map((message) =>
            message.id === assistantId ? { ...message, text: message.text + event.text } : message,
          ),
        );
        break;
      case "state.changed":
        setAgentState(event.state);
        break;
      case "tool.started":
        setToolStatus(`Using ${event.tool} · ${event.risk.replaceAll("_", " ")}`);
        break;
      case "tool.completed":
        setToolStatus(event.summary);
        break;
      case "approval.required":
        setActiveTab("approvals");
        void refresh();
        break;
      case "memory.proposed":
        void refresh();
        break;
      case "run.failed":
        setError(event.safeMessage);
        setAgentState("failure");
        break;
      case "run.completed":
        setBusy(false);
        setToolStatus(undefined);
        void refresh();
        window.setTimeout(() => setAgentState("idle"), 2400);
        break;
    }
  }, [refresh]);

  const streamRun = useCallback(async (runId: string, assistantId: string) => {
    const response = await fetch(`${API}/runs/${runId}/events`, { cache: "no-store" });
    if (!response.ok || !response.body) throw new Error("Could not open Joi's event stream.");
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    while (true) {
      const { done, value } = await reader.read();
      buffer += decoder.decode(value ?? new Uint8Array(), { stream: !done });
      const blocks = buffer.split(/\n\n/);
      buffer = blocks.pop() ?? "";
      for (const block of blocks) {
        const data = block
          .split("\n")
          .filter((line) => line.startsWith("data:"))
          .map((line) => line.slice(5).trim())
          .join("\n");
        if (!data) continue;
        handleEvent(JSON.parse(data) as JoiRunEvent, assistantId);
      }
      if (done) break;
    }
  }, [handleEvent]);

  const submitMessage = useCallback(async (text: string) => {
    const message = text.trim();
    if (!message || busy) return;
    setError(undefined);
    setBusy(true);
    setAgentState("listening");
    const userMessage: ChatMessage = { id: messageId(), role: "user", text: message };
    const assistantMessage: ChatMessage = { id: messageId(), role: "assistant", text: "" };
    setMessages((current) => [...current, userMessage, assistantMessage]);
    setDraft("");
    try {
      const run = await api<StartRunResponse>("/runs", {
        method: "POST",
        body: JSON.stringify({ message, ...(threadId ? { threadId } : {}), mode: profile?.mode ?? "personal" }),
      });
      setThreadId(run.threadId);
      await streamRun(run.runId, assistantMessage.id);
    } catch (caught) {
      const safeMessage = caught instanceof Error ? caught.message : "Joi is unavailable.";
      setError(safeMessage);
      setAgentState("failure");
      setBusy(false);
      setMessages((current) =>
        current.map((item) =>
          item.id === assistantMessage.id && !item.text ? { ...item, text: "I couldn’t finish that run. Please try again." } : item,
        ),
      );
    }
  }, [busy, profile, streamRun, threadId]);

  async function addTask(event: FormEvent) {
    event.preventDefault();
    if (!newTask.trim()) return;
    await api<Task>("/tasks", {
      method: "POST",
      body: JSON.stringify({ title: newTask.trim(), notes: "", priority: "medium" }),
    });
    setNewTask("");
    await refresh();
  }

  async function addMemory(event: FormEvent) {
    event.preventDefault();
    if (!newMemory.trim()) return;
    await api<JoiMemory>("/memories", {
      method: "POST",
      body: JSON.stringify({
        category: "preference",
        value: newMemory.trim(),
        sensitivity: "normal",
        source: "user_explicit",
        confidence: 1,
      }),
    });
    setNewMemory("");
    await refresh();
  }

  async function saveMemory(memoryId: string) {
    if (!editingMemoryValue.trim()) return;
    await api<JoiMemory>(`/memories/${memoryId}`, {
      method: "PATCH",
      body: JSON.stringify({ value: editingMemoryValue.trim() }),
    });
    setEditingMemoryId(undefined);
    setEditingMemoryValue("");
    await refresh();
  }

  async function decideApproval(approvalId: string, decision: "approve" | "reject") {
    setAgentState(decision === "approve" ? "working" : "reviewing");
    await api<Approval>(`/approvals/${approvalId}/${decision}`, { method: "POST" });
    await refresh();
    setAgentState(decision === "approve" ? "success" : "idle");
  }

  async function addAutomation(template: (typeof automationTemplates)[number]) {
    await api<Automation>("/automations", {
      method: "POST",
      body: JSON.stringify({ ...template, enabled: true }),
    });
    await refresh();
  }

  async function setCapability(capabilityId: string, enabled: boolean) {
    await api<CapabilityDescriptor>(`/capabilities/${capabilityId}`, {
      method: "PATCH",
      body: JSON.stringify({ enabled }),
    });
    await refresh();
  }

  return (
    <main className="min-h-screen px-3 py-4 sm:px-6 lg:px-8">
      <div className="mx-auto max-w-[1440px]">
        <header className="mb-4 flex items-center justify-between rounded-2xl border border-white/80 bg-white/70 px-4 py-3 shadow-sm backdrop-blur-xl sm:px-6">
          <div className="flex items-center gap-3">
            <div className="grid size-10 place-items-center rounded-xl bg-stone-900 text-sm font-semibold text-white shadow-sm">J</div>
            <div>
              <h1 className="font-heading text-lg font-semibold tracking-tight">Joi</h1>
              <p className="text-xs text-stone-500">AI daily companion · approval first</p>
            </div>
          </div>
          <div className="flex items-center gap-2">
            <Badge variant="secondary" className="hidden sm:inline-flex">Private beta</Badge>
            <div className={`size-2 rounded-full ${connected ? "bg-emerald-500" : "bg-red-500"}`} aria-label={connected ? "Agent connected" : "Agent disconnected"} />
            <Button variant="ghost" size="icon" onClick={() => void refresh()} aria-label="Refresh Joi data">
              <RefreshCw />
            </Button>
          </div>
        </header>

        {!connected && (
          <div className="mb-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
            The agent service is offline. Start it with <code>pnpm dev:agent</code>; the interface will reconnect when refreshed.
          </div>
        )}
        {error && (
          <div className="mb-4 flex items-center justify-between rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-800">
            <span>{error}</span><Button variant="ghost" size="icon-sm" onClick={() => setError(undefined)}><X /></Button>
          </div>
        )}

        <div className="grid gap-4 lg:grid-cols-[260px_minmax(0,1fr)_300px]">
          <aside className="order-2 lg:order-1">
            <Card className="sticky top-4 border-0 bg-white/72 shadow-sm ring-stone-200/80 backdrop-blur-xl">
              <CardContent className="grid place-items-center pt-2">
                <JoiAvatar state={agentState} reducedMotion={reducedMotion} />
              </CardContent>
              <Separator />
              <CardContent className="space-y-2">
                <p className="text-xs font-semibold uppercase tracking-[0.16em] text-stone-400">Try asking</p>
                {quickPrompts.map(({ icon: Icon, label, prompt }) => (
                  <button
                    key={label}
                    type="button"
                    className="flex w-full items-center gap-2 rounded-xl px-3 py-2 text-left text-sm text-stone-700 transition hover:bg-orange-50 hover:text-orange-950"
                    onClick={() => { setActiveTab("chat"); void submitMessage(prompt); }}
                  >
                    <Icon className="size-4 text-orange-700" /><span className="flex-1">{label}</span><ChevronRight className="size-3.5 text-stone-300" />
                  </button>
                ))}
              </CardContent>
              <CardContent>
                <div className="rounded-xl border border-orange-100 bg-orange-50/70 p-3 text-xs leading-relaxed text-orange-950">
                  <span className="font-semibold">Disclosure:</span> Joi is an AI inspired companion, not a human or your real partner.
                </div>
              </CardContent>
            </Card>
          </aside>

          <section className="order-1 min-w-0 lg:order-2">
            <Tabs value={activeTab} onValueChange={(value) => setActiveTab(value as TabName)} className="gap-3">
              <TabsList className="h-auto w-full justify-start overflow-x-auto rounded-xl bg-white/70 p-1 shadow-sm ring-1 ring-stone-200/80 backdrop-blur">
                <TabsTrigger value="chat"><MessageCircle />Chat</TabsTrigger>
                <TabsTrigger value="tasks"><ListTodo />Tasks</TabsTrigger>
                <TabsTrigger value="memory"><MemoryStick />Memory</TabsTrigger>
                <TabsTrigger value="approvals" className="relative"><ShieldCheck />Approvals{pendingApprovals.length > 0 && <span className="ml-1 grid size-4 place-items-center rounded-full bg-orange-700 text-[10px] text-white">{pendingApprovals.length}</span>}</TabsTrigger>
                <TabsTrigger value="automations"><Clock3 />Routines</TabsTrigger>
                <TabsTrigger value="settings"><Settings2 />Settings</TabsTrigger>
              </TabsList>

              <TabsContent value="chat">
                <Card className="h-[680px] border-0 bg-white/78 shadow-sm ring-stone-200/80 backdrop-blur-xl">
                  <CardHeader className="border-b border-stone-100">
                    <CardTitle>Conversation</CardTitle>
                    <CardDescription>Tools are visible. External actions pause for approval.</CardDescription>
                    <CardAction>{toolStatus && <Badge variant="secondary"><LoaderCircle className={busy ? "animate-spin" : ""} />{toolStatus}</Badge>}</CardAction>
                  </CardHeader>
                  <CardContent className="flex min-h-0 flex-1 flex-col gap-3">
                    <ScrollArea className="min-h-0 flex-1 pr-3">
                      <div className="space-y-4 py-1">
                        {messages.map((message) => (
                          <div key={message.id} className={`flex ${message.role === "user" ? "justify-end" : "justify-start"}`}>
                            <div className={`max-w-[84%] rounded-2xl px-4 py-3 text-sm leading-relaxed ${message.role === "user" ? "rounded-br-md bg-stone-900 text-white" : "rounded-bl-md border border-orange-100 bg-orange-50/70 text-stone-800"}`}>
                              {message.text || <span className="inline-flex items-center gap-2 text-stone-400"><LoaderCircle className="size-3.5 animate-spin" />Thinking</span>}
                            </div>
                          </div>
                        ))}
                        <div ref={messagesEnd} />
                      </div>
                    </ScrollArea>
                    <form
                      className="rounded-2xl border border-stone-200 bg-white p-2 shadow-sm focus-within:border-orange-300 focus-within:ring-2 focus-within:ring-orange-100"
                      onSubmit={(event) => { event.preventDefault(); void submitMessage(draft); }}
                    >
                      <Textarea
                        value={draft}
                        onChange={(event) => setDraft(event.target.value)}
                        onKeyDown={(event) => {
                          if (event.key === "Enter" && !event.shiftKey) {
                            event.preventDefault();
                            void submitMessage(draft);
                          }
                        }}
                        placeholder="Ask Joi to plan, research, remember, or prepare an action…"
                        className="min-h-20 resize-none border-0 bg-transparent shadow-none focus-visible:ring-0"
                      />
                      <div className="flex items-center justify-between px-1 pb-1">
                        <span className="text-[11px] text-stone-400">Enter to send · Shift + Enter for a new line</span>
                        <Button type="submit" disabled={busy || !draft.trim()} className="rounded-xl bg-orange-700 hover:bg-orange-800"><Send />Send</Button>
                      </div>
                    </form>
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="tasks">
                <Card className="min-h-[620px] border-0 bg-white/78 shadow-sm ring-stone-200/80 backdrop-blur-xl">
                  <CardHeader><CardTitle>Your tasks</CardTitle><CardDescription>Capture, prioritize, and complete work without leaving Joi.</CardDescription></CardHeader>
                  <CardContent className="space-y-4">
                    <form onSubmit={(event) => void addTask(event)} className="flex gap-2"><Input value={newTask} onChange={(event) => setNewTask(event.target.value)} placeholder="Add a task…" /><Button type="submit"><Plus />Add</Button></form>
                    {tasks.length === 0 ? <EmptyState icon={ListTodo} title="No tasks yet" copy="Ask Joi to create one, or capture it here." /> : (
                      <div className="space-y-2">{tasks.map((task) => (
                        <div key={task.id} className="flex items-center gap-3 rounded-xl border border-stone-100 bg-white p-3">
                          <Button variant="ghost" size="icon-sm" aria-label={`Mark ${task.title} done`} onClick={async () => { await api(`/tasks/${task.id}`, { method: "PATCH", body: JSON.stringify({ status: task.status === "done" ? "todo" : "done" }) }); await refresh(); }}>
                            {task.status === "done" ? <CheckCircle2 className="text-emerald-600" /> : <div className="size-4 rounded-full border border-stone-300" />}
                          </Button>
                          <div className="min-w-0 flex-1"><p className={`truncate font-medium ${task.status === "done" ? "text-stone-400 line-through" : "text-stone-800"}`}>{task.title}</p><p className="text-xs capitalize text-stone-400">{task.priority} priority · {task.status}</p></div>
                          <Button variant="ghost" size="icon-sm" aria-label={`Delete ${task.title}`} onClick={async () => { await api(`/tasks/${task.id}`, { method: "DELETE" }); await refresh(); }}><Trash2 /></Button>
                        </div>
                      ))}</div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="memory">
                <Card className="min-h-[620px] border-0 bg-white/78 shadow-sm ring-stone-200/80 backdrop-blur-xl">
                  <CardHeader><CardTitle>Memory you control</CardTitle><CardDescription>Joi only stores explicit memories or asks before saving a proposal.</CardDescription></CardHeader>
                  <CardContent className="space-y-4">
                    <form onSubmit={(event) => void addMemory(event)} className="flex gap-2"><Input value={newMemory} onChange={(event) => setNewMemory(event.target.value)} placeholder="Remember that I prefer…" /><Button type="submit"><Plus />Remember</Button></form>
                    {memories.length === 0 ? <EmptyState icon={MemoryStick} title="Nothing remembered yet" copy="Explicit memories are editable and deletable. Mail, files, and calendar content are never silently promoted to memory." /> : (
                      <div className="grid gap-3 sm:grid-cols-2">{memories.map((memory) => (
                        <div key={memory.id} className="rounded-xl border border-stone-100 bg-white p-4">
                          <div className="mb-2 flex items-center justify-between"><Badge variant="secondary" className="capitalize">{memory.category}</Badge><div className="flex"><Button variant="ghost" size="icon-sm" aria-label="Edit memory" onClick={() => { setEditingMemoryId(memory.id); setEditingMemoryValue(memory.value); }}><Pencil /></Button><Button variant="ghost" size="icon-sm" aria-label="Delete memory" onClick={async () => { await api(`/memories/${memory.id}`, { method: "DELETE" }); await refresh(); }}><Trash2 /></Button></div></div>
                          {editingMemoryId === memory.id ? <div className="space-y-2"><Input value={editingMemoryValue} onChange={(event) => setEditingMemoryValue(event.target.value)} aria-label="Edit memory value" /><div className="flex justify-end gap-2"><Button variant="ghost" size="sm" onClick={() => setEditingMemoryId(undefined)}>Cancel</Button><Button size="sm" onClick={() => void saveMemory(memory.id)}>Save</Button></div></div> : <p className="text-sm leading-relaxed text-stone-700">{memory.value}</p>}<p className="mt-3 text-[11px] text-stone-400">{memory.source.replaceAll("_", " ")} · {memory.sensitivity}</p>
                        </div>
                      ))}</div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="approvals">
                <Card className="min-h-[620px] border-0 bg-white/78 shadow-sm ring-stone-200/80 backdrop-blur-xl">
                  <CardHeader><CardTitle>Approval inbox</CardTitle><CardDescription>Inspect exact recipients, dates, content, and side effects before anything leaves Joi.</CardDescription></CardHeader>
                  <CardContent>
                    {approvals.length === 0 ? <EmptyState icon={ShieldCheck} title="No approval requests" copy="External writes appear here. Destructive and financial actions are blocked in this release." /> : (
                      <div className="space-y-3">{approvals.map((approval) => (
                        <div key={approval.id} className="rounded-2xl border border-stone-200 bg-white p-4 shadow-sm">
                          <div className="flex flex-wrap items-start justify-between gap-2"><div><div className="flex items-center gap-2"><p className="font-semibold text-stone-900">{approval.preview.label}</p><Badge variant={approval.status === "pending" ? "default" : "secondary"} className="capitalize">{approval.status}</Badge></div><p className="mt-1 text-sm text-stone-600">{approval.preview.summary}</p></div><span className="text-xs text-stone-400">Expires {formatDate(approval.preview.expiresAt)}</span></div>
                          <pre className="mt-3 max-h-52 overflow-auto whitespace-pre-wrap rounded-xl bg-stone-950 p-3 text-xs leading-relaxed text-stone-100">{JSON.stringify(approval.preview.payload, null, 2)}</pre>
                          {approval.status === "pending" && <div className="mt-3 flex justify-end gap-2"><Button variant="outline" onClick={() => void decideApproval(approval.id, "reject")}><X />Reject</Button><Button className="bg-emerald-700 hover:bg-emerald-800" onClick={() => void decideApproval(approval.id, "approve")}><Check />Approve exact action</Button></div>}
                        </div>
                      ))}</div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="automations">
                <Card className="min-h-[620px] border-0 bg-white/78 shadow-sm ring-stone-200/80 backdrop-blur-xl">
                  <CardHeader><CardTitle>Proactive routines</CardTitle><CardDescription>Templates are stored now; connect a durable worker before enabling production delivery.</CardDescription></CardHeader>
                  <CardContent className="space-y-5">
                    <div className="grid gap-3 sm:grid-cols-2">{automationTemplates.map((template) => {
                      const installed = automations.some((automation) => automation.name === template.name);
                      return <button key={template.name} type="button" disabled={installed} onClick={() => void addAutomation(template)} className="rounded-xl border border-stone-200 bg-white p-4 text-left transition hover:border-orange-300 hover:bg-orange-50 disabled:cursor-default disabled:opacity-60"><div className="flex items-center justify-between"><Clock3 className="size-4 text-orange-700" />{installed ? <Badge variant="secondary">Added</Badge> : <Plus className="size-4" />}</div><p className="mt-3 font-medium text-stone-800">{template.name}</p><p className="mt-1 text-xs leading-relaxed text-stone-500">{template.prompt}</p><code className="mt-2 block text-[11px] text-stone-400">{template.schedule}</code></button>;
                    })}</div>
                    {automations.length > 0 && <div className="space-y-2"><p className="text-xs font-semibold uppercase tracking-[0.16em] text-stone-400">Configured</p>{automations.map((automation) => <div key={automation.id} className="flex items-center gap-3 rounded-xl border border-stone-100 bg-white p-3"><BellRing className="size-4 text-orange-700" /><div className="flex-1"><p className="font-medium text-stone-800">{automation.name}</p><p className="text-xs text-stone-400">{automation.schedule}</p></div><Switch checked={automation.enabled} aria-label={`${automation.enabled ? "Pause" : "Enable"} ${automation.name}`} onCheckedChange={async (enabled) => { await api(`/automations/${automation.id}`, { method: "PATCH", body: JSON.stringify({ enabled }) }); await refresh(); }} /><Badge variant="secondary">{automation.enabled ? "Enabled" : "Paused"}</Badge><Button variant="ghost" size="icon-sm" onClick={async () => { await api(`/automations/${automation.id}`, { method: "DELETE" }); await refresh(); }}><Trash2 /></Button></div>)}</div>}
                  </CardContent>
                </Card>
              </TabsContent>

              <TabsContent value="settings">
                <Card className="min-h-[620px] border-0 bg-white/78 shadow-sm ring-stone-200/80 backdrop-blur-xl">
                  <CardHeader><CardTitle>Controls and privacy</CardTitle><CardDescription>Production identity, OAuth, billing, and legal approvals remain explicit release gates.</CardDescription></CardHeader>
                  <CardContent className="space-y-6">
                    <div><p className="mb-3 text-xs font-semibold uppercase tracking-[0.16em] text-stone-400">Connectors</p><div className="grid gap-3 sm:grid-cols-3">{connectors.map((connector) => <div key={connector.id} className="rounded-xl border border-stone-200 bg-white p-4"><div className="flex items-center justify-between"><Database className="size-4 text-orange-700" /><Badge variant="secondary" className="capitalize">{connector.status}</Badge></div><p className="mt-3 font-medium">{connector.label}</p><p className="mt-1 text-xs text-stone-400">Minimum scopes · mock data only</p></div>)}</div></div>
                    <Separator />
                    <div>
                      <div className="mb-3 flex items-end justify-between gap-3"><div><p className="text-xs font-semibold uppercase tracking-[0.16em] text-stone-400">MVP capability selection</p><p className="mt-1 text-xs text-stone-500">Implemented beta features are selectable. Planned MVP release gates stay locked until they are real.</p></div><Badge variant="secondary">{capabilities.filter((item) => item.release === "mvp" && item.enabled).length} enabled</Badge></div>
                      <div className="grid max-h-72 gap-2 overflow-y-auto rounded-xl border border-stone-200 bg-white p-3 sm:grid-cols-2">
                        {capabilities.filter((item) => item.release === "mvp").map((capability) => (
                          <label key={capability.id} className="flex cursor-pointer items-center justify-between gap-3 rounded-lg px-2 py-2 hover:bg-orange-50">
                            <span><span className="font-mono text-xs font-medium text-stone-800">{capability.id}</span><span className="ml-2 text-[11px] capitalize text-stone-400">{capability.group}</span>{capability.availability === "release_gate" && <Badge variant="secondary" className="ml-2">Gated</Badge>}</span>
                            <Switch checked={capability.enabled} disabled={capability.availability !== "implemented_beta"} onCheckedChange={(enabled) => void setCapability(capability.id, enabled)} aria-label={`Toggle ${capability.id}`} />
                          </label>
                        ))}
                      </div>
                    </div>
                    <Separator />
                    <div className="flex items-center justify-between rounded-xl border border-stone-200 bg-white p-4"><div><p className="font-medium">Reduced motion</p><p className="text-xs text-stone-500">Show a stable pose and disable animated scrolling.</p></div><Switch checked={reducedMotion} onCheckedChange={setReducedMotion} /></div>
                    <div className="grid gap-3 sm:grid-cols-2"><div className="rounded-xl border border-stone-200 bg-white p-4"><LockKeyhole className="size-4 text-orange-700" /><p className="mt-3 font-medium">Data controls</p><p className="mt-1 text-xs leading-relaxed text-stone-500">Export and deletion endpoints cover profile, tasks, memory, approvals, automations, and audit history in this prototype.</p></div><div className="rounded-xl border border-stone-200 bg-white p-4"><FileText className="size-4 text-orange-700" /><p className="mt-3 font-medium">Release gates</p><p className="mt-1 text-xs leading-relaxed text-stone-500">Likeness release, trademark clearance, production auth, encrypted connector tokens, and legal review must be complete before public launch.</p></div></div>
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </section>

          <aside className="order-3 space-y-4">
            <Card className="border-0 bg-stone-900 text-stone-50 shadow-lg ring-0">
              <CardHeader><CardTitle className="flex items-center gap-2"><Sparkles className="text-orange-300" />Today with Joi</CardTitle><CardDescription className="text-stone-400">One calm place for your day.</CardDescription></CardHeader>
              <CardContent className="space-y-3">
                <div className="rounded-xl bg-white/7 p-3"><p className="text-xs text-stone-400">Open tasks</p><p className="mt-1 text-2xl font-semibold">{tasks.filter((task) => task.status !== "done").length}</p></div>
                <div className="grid grid-cols-2 gap-3"><div className="rounded-xl bg-white/7 p-3"><p className="text-xs text-stone-400">Memories</p><p className="mt-1 text-xl font-semibold">{memories.length}</p></div><div className="rounded-xl bg-white/7 p-3"><p className="text-xs text-stone-400">Approvals</p><p className="mt-1 text-xl font-semibold">{pendingApprovals.length}</p></div></div>
              </CardContent>
            </Card>
            <Card className="border-0 bg-white/72 shadow-sm ring-stone-200/80 backdrop-blur-xl">
              <CardHeader><CardTitle className="flex items-center gap-2"><ShieldCheck className="size-4 text-emerald-700" />Safety posture</CardTitle></CardHeader>
              <CardContent className="space-y-3 text-sm text-stone-600">
                <p className="flex gap-2"><Check className="mt-0.5 size-4 shrink-0 text-emerald-700" />Reads run automatically and remain visible.</p>
                <p className="flex gap-2"><Check className="mt-0.5 size-4 shrink-0 text-emerald-700" />External writes require exact approval.</p>
                <p className="flex gap-2"><Check className="mt-0.5 size-4 shrink-0 text-emerald-700" />Destructive and financial tools are unavailable.</p>
              </CardContent>
            </Card>
            <Card className="border-0 bg-gradient-to-br from-orange-100 to-rose-100 shadow-sm ring-orange-200/70">
              <CardContent className="pt-1"><Heart className="size-5 text-rose-700" /><p className="mt-3 font-medium text-stone-900">Warm, never manipulative</p><p className="mt-1 text-xs leading-relaxed text-stone-600">Joi can encourage and celebrate, but never claims consciousness, exclusivity, jealousy, or emotional dependence.</p></CardContent>
            </Card>
          </aside>
        </div>
        <footer className="py-6 text-center text-xs text-stone-400"><Bot className="mr-1 inline size-3.5" />Joi is AI. Verify important information and approve external actions carefully.</footer>
      </div>
    </main>
  );
}
