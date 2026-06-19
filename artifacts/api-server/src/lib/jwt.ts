import { createPublicKey } from "node:crypto";
import jwt from "jsonwebtoken";
import { v4 as uuidv4 } from "uuid";

export interface EntitlementClaims {
  iss: string;
  sub: string;
  appId: string;
  features: string[];
  maxAccounts: number;
  maxConcurrentCalls: number;
  iat?: number;
  exp?: number;
  jti: string;
}

const ISSUER = "sipkit-license";

/**
 * Normalise a PEM stored as an env var.
 * Replit Secrets may store the key with:
 *   - real newlines (ideal)
 *   - escaped \n sequences
 *   - spaces instead of newlines (when pasted without quoting)
 * This function handles all three cases.
 */
function normalisePem(raw: string): string {
  // 1. Handle escaped \n sequences
  let pem = raw.replace(/\\n/g, "\n");

  // 2. If already has real newlines, just trim and return
  if (pem.includes("\n")) return pem.trim();

  // 3. Handle space-delimited PEM (Replit Secrets strips newlines to spaces).
  // Format: "-----BEGIN PRIVATE KEY----- <base64body> -----END PRIVATE KEY-----"
  // Strategy: extract the type, base64 body, and rebuild with proper 64-char lines.
  const match = pem.match(/-----BEGIN ([^-]+)-----\s*([\s\S]+?)\s*-----END ([^-]+)-----/);
  if (!match) return pem; // give up, return as-is

  const type = match[1]!.trim();
  // base64 body: remove all whitespace, then re-chunk into 64-char lines
  const body = match[2]!.replace(/\s+/g, "");
  const lines: string[] = [];
  for (let i = 0; i < body.length; i += 64) {
    lines.push(body.slice(i, i + 64));
  }

  return `-----BEGIN ${type}-----\n${lines.join("\n")}\n-----END ${type}-----`;
}

function getPrivateKey(): string {
  const key = process.env["JWT_PRIVATE_KEY"];
  if (!key) throw new Error("JWT_PRIVATE_KEY env var is required");
  return normalisePem(key);
}

function getPublicKey(): string {
  const key = process.env["JWT_PUBLIC_KEY"];
  if (!key) throw new Error("JWT_PUBLIC_KEY env var is required");
  return normalisePem(key);
}

export function signEntitlement(claims: Omit<EntitlementClaims, "iss" | "iat" | "exp" | "jti">): string {
  const ttl = parseInt(process.env["ENTITLEMENT_TTL_SECONDS"] ?? "86400");
  const payload: EntitlementClaims = {
    iss: ISSUER,
    jti: uuidv4(),
    ...claims,
  };
  return jwt.sign(payload, getPrivateKey(), {
    algorithm: "RS256",
    expiresIn: ttl,
  });
}

export function verifyEntitlement(token: string): EntitlementClaims {
  return jwt.verify(token, getPublicKey(), {
    algorithms: ["RS256"],
    issuer: ISSUER,
  }) as EntitlementClaims;
}

export function getPublicKeyPem(): string {
  return getPublicKey();
}

export function getPublicKeyJwks(): object {
  const pem = getPublicKey();

  // Use Node's crypto to properly extract n and e from the DER-encoded public key
  const keyObj = createPublicKey({ key: pem, format: "pem" });
  const jwk = keyObj.export({ format: "jwk" }) as {
    kty: string;
    n: string;
    e: string;
  };

  return {
    keys: [
      {
        kty: jwk.kty,
        use: "sig",
        alg: "RS256",
        kid: "sipkit-1",
        n: jwk.n,
        e: jwk.e,
      },
    ],
  };
}
