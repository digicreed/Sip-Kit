#!/usr/bin/env tsx
/**
 * SipKit License Server — RS256 Key Generator
 *
 * Run: pnpm --filter @workspace/api-server run generate-keys
 *
 * Copy the output values into your environment secrets:
 *   JWT_PRIVATE_KEY — used by the server to sign entitlement JWTs
 *   JWT_PUBLIC_KEY  — served publicly; bundle into the Flutter SDK
 */
import { generateKeyPairSync } from "node:crypto";

const { privateKey, publicKey } = generateKeyPairSync("rsa", {
  modulusLength: 2048,
  publicKeyEncoding: { type: "spki", format: "pem" },
  privateKeyEncoding: { type: "pkcs8", format: "pem" },
});

console.log("=".repeat(60));
console.log("RS256 Keypair generated — copy these into your env secrets");
console.log("=".repeat(60));
console.log("\n--- JWT_PRIVATE_KEY (keep secret, server only) ---");
console.log(privateKey);
console.log("--- JWT_PUBLIC_KEY (safe to publish, bundle in SDK) ---");
console.log(publicKey);
console.log("=".repeat(60));
console.log("IMPORTANT: These keys are shown once. Store them securely.");
