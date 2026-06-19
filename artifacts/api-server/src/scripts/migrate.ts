#!/usr/bin/env tsx
/**
 * SipKit License Server — Schema Push
 * Runs on every `dev` start to ensure all tables exist.
 * Each statement is a separate db.execute() call — PostgreSQL does not allow
 * multiple DDL commands in a single prepared statement.
 */
import { db, pool } from "@workspace/db";
import { sql } from "drizzle-orm";

async function migrate() {
  console.log("Running schema migrations...");

  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS providers (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      name TEXT NOT NULL,
      contact_email TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS licenses (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      provider_id UUID NOT NULL REFERENCES providers(id),
      key_hash TEXT NOT NULL,
      key_prefix TEXT NOT NULL DEFAULT '',
      features JSONB NOT NULL DEFAULT '["audio"]'::jsonb,
      max_accounts INTEGER NOT NULL DEFAULT 5,
      max_concurrent_calls INTEGER NOT NULL DEFAULT 10,
      max_devices INTEGER NOT NULL DEFAULT 10,
      expires_at TIMESTAMPTZ,
      revoked_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  await db.execute(sql`ALTER TABLE licenses ADD COLUMN IF NOT EXISTS key_prefix TEXT NOT NULL DEFAULT ''`);

  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS devices (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      license_id UUID NOT NULL REFERENCES licenses(id),
      device_id TEXT NOT NULL,
      app_id TEXT NOT NULL,
      first_seen TIMESTAMPTZ NOT NULL DEFAULT now(),
      last_seen TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS refresh_tokens (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      license_id UUID NOT NULL REFERENCES licenses(id),
      device_id UUID NOT NULL REFERENCES devices(id),
      token_hash TEXT NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      revoked_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS usage_events (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      license_id UUID NOT NULL REFERENCES licenses(id),
      device_id UUID NOT NULL REFERENCES devices(id),
      call_minutes INTEGER NOT NULL DEFAULT 0,
      registrations INTEGER NOT NULL DEFAULT 0,
      calls_placed INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `);

  await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_licenses_provider_id ON licenses(provider_id)`);
  await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_licenses_revoked_at ON licenses(revoked_at)`);
  await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_licenses_key_prefix ON licenses(key_prefix)`);
  await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_devices_license_id ON devices(license_id)`);
  await db.execute(sql`CREATE UNIQUE INDEX IF NOT EXISTS idx_devices_unique ON devices(license_id, device_id, app_id)`);
  await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_refresh_tokens_license_id ON refresh_tokens(license_id)`);
  await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_refresh_tokens_expires_at ON refresh_tokens(expires_at)`);
  await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_usage_events_license_id ON usage_events(license_id)`);
  await db.execute(sql`CREATE INDEX IF NOT EXISTS idx_usage_events_created_at ON usage_events(created_at)`);

  console.log("✅ Schema migrations complete.");
  await pool.end();
}

migrate().catch((err) => {
  console.error("Migration failed:", err);
  process.exit(1);
});
