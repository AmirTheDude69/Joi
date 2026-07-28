import { randomUUID } from "node:crypto";
import type { CalendarEvent, ConnectorStatus, DriveFile, GmailMessage } from "@joi/contracts";

function relativeIso(hoursFromNow: number): string {
  return new Date(Date.now() + hoursFromNow * 60 * 60 * 1_000).toISOString();
}

export class MockGoogleConnectors {
  private readonly messages: GmailMessage[] = [
    {
      id: "msg-demo-1",
      threadId: "thread-demo-1",
      from: "maya@example.com",
      to: ["you@example.com"],
      subject: "Tomorrow's project review",
      snippet: "Could you send the latest launch checklist before our review?",
      receivedAt: relativeIso(-3),
      unread: true,
    },
    {
      id: "msg-demo-2",
      threadId: "thread-demo-2",
      from: "newsletter@example.com",
      to: ["you@example.com"],
      subject: "Your weekly design digest",
      snippet: "Five practical ideas for calmer product interfaces.",
      receivedAt: relativeIso(-20),
      unread: false,
    },
  ];

  private readonly events: CalendarEvent[] = [
    {
      id: "event-demo-1",
      title: "Project review",
      startsAt: relativeIso(20),
      endsAt: relativeIso(21),
      attendees: ["maya@example.com"],
      location: "Video call",
    },
    {
      id: "event-demo-2",
      title: "Focus block",
      startsAt: relativeIso(24),
      endsAt: relativeIso(26),
      attendees: [],
    },
  ];

  private readonly files: DriveFile[] = [
    {
      id: "file-demo-1",
      name: "Joi launch checklist",
      mimeType: "application/vnd.google-apps.document",
      modifiedAt: relativeIso(-6),
      excerpt: "Private beta, approval safeguards, OAuth scope review, and support readiness.",
    },
    {
      id: "file-demo-2",
      name: "Weekly priorities",
      mimeType: "application/vnd.google-apps.document",
      modifiedAt: relativeIso(-12),
      excerpt: "Finish agent API, validate plugin, and test the PWA on mobile.",
    },
  ];

  status(): ConnectorStatus[] {
    const synced = new Date().toISOString();
    return [
      { id: "gmail", label: "Gmail", status: "demo", scopes: ["gmail.readonly", "gmail.compose"], lastSyncedAt: synced },
      { id: "google_calendar", label: "Google Calendar", status: "demo", scopes: ["calendar.readonly", "calendar.events"], lastSyncedAt: synced },
      { id: "google_drive", label: "Google Drive", status: "demo", scopes: ["drive.readonly"], lastSyncedAt: synced },
    ];
  }

  searchGmail(query = ""): GmailMessage[] {
    const needle = query.trim().toLowerCase();
    if (!needle) return [...this.messages];
    return this.messages.filter((item) =>
      [item.from, item.subject, item.snippet].some((value) => value.toLowerCase().includes(needle)),
    );
  }

  listCalendar(): CalendarEvent[] {
    return [...this.events].sort((a, b) => a.startsAt.localeCompare(b.startsAt));
  }

  createCalendarEvent(input: Omit<CalendarEvent, "id">): CalendarEvent {
    const event = { ...input, id: `event-${randomUUID()}` };
    this.events.push(event);
    return event;
  }

  searchDrive(query = ""): DriveFile[] {
    const needle = query.trim().toLowerCase();
    if (!needle) return [...this.files];
    return this.files.filter((item) =>
      [item.name, item.excerpt].some((value) => value.toLowerCase().includes(needle)),
    );
  }

  sendEmail(input: { to: string[]; subject: string; body: string }): { messageId: string; accepted: string[] } {
    return { messageId: `sent-${randomUUID()}`, accepted: input.to };
  }
}
