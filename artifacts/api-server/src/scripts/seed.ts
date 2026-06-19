#!/usr/bin/env tsx
/**
 * SipKit License Server — Seed Script
 *
 * Creates a demo provider + demo license key for immediate testing.
 * Run: pnpm --filter @workspace/api-server run seed
 *
 * The license key is printed ONCE — save it immediately.
 */
import bcrypt from "bcryptjs";
import { db } from "@workspace/db";
import { providersTable, licensesTable } from "@workspace/db/schema";

const KEY_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";

async function generateLicenseKey(): Promise<string> {
  const { randomBytes } = await import("node:crypto");
  const bytes = randomBytes(32);
  let key = "pk_live_";
  for (const byte of bytes) {
    key += KEY_ALPHABET[byte % KEY_ALPHABET.length];
  }
  return key;
}

async function main() {
  console.log("🌱 Seeding SipKit license server...\n");

  const [provider] = await db
    .insert(providersTable)
    .values({
      name: "Demo VoIP Provider",
      contactEmail: "demo@provider.example.com",
    })
    .returning();

  console.log(`✅ Provider created: ${provider!.name} (id: ${provider!.id})`);

  const plainKey = await generateLicenseKey();
  const keyHash = await bcrypt.hash(plainKey, 12);

  const expiresAt = new Date();
  expiresAt.setFullYear(expiresAt.getFullYear() + 1);

  const [license] = await db
    .insert(licensesTable)
    .values({
      providerId: provider!.id,
      keyHash,
      features: ["audio", "video", "conference", "transfer", "dtmf"],
      maxAccounts: 10,
      maxConcurrentCalls: 50,
      maxDevices: 100,
      expiresAt,
    })
    .returning();

  console.log(`✅ License issued for provider: ${provider!.id}`);

  console.log("\n" + "=".repeat(60));
  console.log("DEMO LICENSE KEY (shown once — save this now!)");
  console.log("=".repeat(60));
  console.log(`\nLicense Key:  ${plainKey}`);
  console.log(`License ID:   ${license!.id}`);
  console.log(`Provider ID:  ${provider!.id}`);
  console.log(`Features:     audio, video, conference, transfer, dtmf`);
  console.log(`Max Accounts: 10`);
  console.log(`Expires:      ${expiresAt.toISOString()}`);
  console.log("\n" + "=".repeat(60));
  console.log("Use this key in the Flutter SDK:");
  console.log(`  SipKitClient().activate(`);
  console.log(`    licenseKey: '${plainKey}',`);
  console.log(`    baseUrl: 'https://YOUR_SERVER_URL',`);
  console.log(`    appId: 'com.your.softphone',`);
  console.log(`  )`);
  console.log("=".repeat(60) + "\n");

  process.exit(0);
}

main().catch((err) => {
  console.error("Seed failed:", err);
  process.exit(1);
});
