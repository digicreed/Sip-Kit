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
const ENTITLEMENT_TTL_SECONDS = 24 * 60 * 60; // 24 hours

function getPrivateKey(): string {
  const key = process.env["JWT_PRIVATE_KEY"];
  if (!key) throw new Error("JWT_PRIVATE_KEY env var is required");
  return key.replace(/\\n/g, "\n");
}

function getPublicKey(): string {
  const key = process.env["JWT_PUBLIC_KEY"];
  if (!key) throw new Error("JWT_PUBLIC_KEY env var is required");
  return key.replace(/\\n/g, "\n");
}

export function signEntitlement(claims: Omit<EntitlementClaims, "iss" | "iat" | "exp" | "jti">): string {
  const payload: EntitlementClaims = {
    iss: ISSUER,
    jti: uuidv4(),
    ...claims,
  };
  return jwt.sign(payload, getPrivateKey(), {
    algorithm: "RS256",
    expiresIn: ENTITLEMENT_TTL_SECONDS,
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
  const key = Buffer.from(
    pem.replace("-----BEGIN PUBLIC KEY-----", "").replace("-----END PUBLIC KEY-----", "").replace(/\n/g, ""),
    "base64"
  );
  return {
    keys: [
      {
        kty: "RSA",
        use: "sig",
        alg: "RS256",
        kid: "sipkit-1",
        n: key.toString("base64url").slice(24, -5),
      },
    ],
  };
}
