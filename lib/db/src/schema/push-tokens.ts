import { pgTable, text, timestamp, unique, uuid } from "drizzle-orm/pg-core";
import { devicesTable } from "./devices";

export const pushTokensTable = pgTable(
  "push_tokens",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    deviceId: uuid("device_id")
      .notNull()
      .references(() => devicesTable.id, { onDelete: "cascade" }),
    platform: text("platform").notNull(),
    token: text("token").notNull(),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [unique("push_tokens_device_id_unique").on(t.deviceId)],
);

export type PushToken = typeof pushTokensTable.$inferSelect;
