import { z } from "zod";

export const GmailMessageSchema = z.object({
  id: z.string(),
  threadId: z.string(),
  from: z.string(),
  to: z.array(z.string()),
  subject: z.string(),
  snippet: z.string(),
  receivedAt: z.iso.datetime(),
  unread: z.boolean(),
});

export type GmailMessage = z.infer<typeof GmailMessageSchema>;

export const CalendarEventSchema = z.object({
  id: z.string(),
  title: z.string(),
  startsAt: z.iso.datetime(),
  endsAt: z.iso.datetime(),
  attendees: z.array(z.string()),
  location: z.string().optional(),
});

export type CalendarEvent = z.infer<typeof CalendarEventSchema>;

export const DriveFileSchema = z.object({
  id: z.string(),
  name: z.string(),
  mimeType: z.string(),
  modifiedAt: z.iso.datetime(),
  excerpt: z.string(),
});

export type DriveFile = z.infer<typeof DriveFileSchema>;

export const ConnectorStatusSchema = z.object({
  id: z.enum(["gmail", "google_calendar", "google_drive"]),
  label: z.string(),
  status: z.enum(["demo", "connected", "disconnected", "error"]),
  scopes: z.array(z.string()),
  lastSyncedAt: z.iso.datetime().optional(),
});

export type ConnectorStatus = z.infer<typeof ConnectorStatusSchema>;
