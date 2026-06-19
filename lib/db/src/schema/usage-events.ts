import { pgTable, timestamp, uuid, integer } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { licensesTable } from "./licenses";
import { devicesTable } from "./devices";

export const usageEventsTable = pgTable("usage_events", {
  id: uuid("id").primaryKey().defaultRandom(),
  licenseId: uuid("license_id").notNull().references(() => licensesTable.id),
  deviceId: uuid("device_id").notNull().references(() => devicesTable.id),
  callMinutes: integer("call_minutes").notNull().default(0),
  registrations: integer("registrations").notNull().default(0),
  callsPlaced: integer("calls_placed").notNull().default(0),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const insertUsageEventSchema = createInsertSchema(usageEventsTable).omit({ id: true, createdAt: true });
export type InsertUsageEvent = z.infer<typeof insertUsageEventSchema>;
export type UsageEvent = typeof usageEventsTable.$inferSelect;
