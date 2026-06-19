import { pgTable, text, timestamp, uuid, integer, jsonb } from "drizzle-orm/pg-core";
import { createInsertSchema } from "drizzle-zod";
import { z } from "zod/v4";
import { providersTable } from "./providers";

export const licensesTable = pgTable("licenses", {
  id: uuid("id").primaryKey().defaultRandom(),
  providerId: uuid("provider_id").notNull().references(() => providersTable.id),
  keyHash: text("key_hash").notNull(),
  keyPrefix: text("key_prefix").notNull().default(""),
  features: jsonb("features").$type<string[]>().notNull().default(["audio"]),
  maxAccounts: integer("max_accounts").notNull().default(5),
  maxConcurrentCalls: integer("max_concurrent_calls").notNull().default(10),
  maxDevices: integer("max_devices").notNull().default(10),
  expiresAt: timestamp("expires_at", { withTimezone: true }),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const insertLicenseSchema = createInsertSchema(licensesTable).omit({ id: true, createdAt: true });
export type InsertLicense = z.infer<typeof insertLicenseSchema>;
export type License = typeof licensesTable.$inferSelect;
