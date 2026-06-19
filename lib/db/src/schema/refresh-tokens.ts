import { pgTable, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { licensesTable } from "./licenses";
import { devicesTable } from "./devices";

export const refreshTokensTable = pgTable("refresh_tokens", {
  id: uuid("id").primaryKey().defaultRandom(),
  licenseId: uuid("license_id").notNull().references(() => licensesTable.id),
  deviceId: uuid("device_id").notNull().references(() => devicesTable.id),
  tokenHash: text("token_hash").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export type RefreshToken = typeof refreshTokensTable.$inferSelect;
