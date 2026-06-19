import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { licensesTable } from "./licenses";

export const devicesTable = pgTable("devices", {
  id: uuid("id").primaryKey().defaultRandom(),
  licenseId: uuid("license_id").notNull().references(() => licensesTable.id),
  deviceId: text("device_id").notNull(),
  appId: text("app_id").notNull(),
  firstSeen: timestamp("first_seen", { withTimezone: true }).notNull().defaultNow(),
  lastSeen: timestamp("last_seen", { withTimezone: true }).notNull().defaultNow(),
});

export type Device = typeof devicesTable.$inferSelect;
