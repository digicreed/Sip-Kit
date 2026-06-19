# SipKit License Server

The commercial control plane for SipKit — a B2B SIP/VoIP SDK. VoIP providers embed the Flutter SDK in their softphone and activate it with a license key you issue. This server validates keys, issues signed RS256 JWT entitlement tokens, and tracks usage.

---

## Quick Start

### 1. Environment Setup

All required env vars are already configured on Replit. To regenerate the RS256 keypair:

```bash
pnpm --filter @workspace/api-server run generate-keys
```

Copy the output values into your environment secrets as `JWT_PRIVATE_KEY` and `JWT_PUBLIC_KEY`.

Required environment variables:

| Variable | Description |
|---|---|
| `DATABASE_URL` | PostgreSQL connection string (auto-provisioned on Replit) |
| `JWT_PRIVATE_KEY` | RS256 private key PEM (signs entitlement JWTs) |
| `JWT_PUBLIC_KEY` | RS256 public key PEM (served publicly, bundle into SDK) |
| `ADMIN_API_KEY` | Bearer token for admin endpoints |
| `PORT` | HTTP port (auto-set by Replit) |
| `CORS_ORIGINS` | Comma-separated allowed origins, or `*` (default: `*`) |
| `ENTITLEMENT_TTL_SECONDS` | JWT lifetime in seconds (default: `86400` = 24h) |
| `REFRESH_TOKEN_TTL_DAYS` | Refresh token lifetime in days (default: `30`) |

### 2. Run the database migration

```bash
pnpm --filter @workspace/api-server run migrate
```

### 3. Seed a demo provider and license key

```bash
pnpm --filter @workspace/api-server run seed
```

**Save the printed license key** — it is shown only once. Use it in the Flutter SDK:

```dart
await SipKitClient().activate(
  licenseKey: 'pk_live_XXXX',
  baseUrl: 'https://your-server.replit.app',
  appId: 'com.yourcompany.softphone',
);
```

### 4. Start the server

```bash
pnpm --filter @workspace/api-server run dev
```

---

## API Reference

All SDK-facing endpoints are at `/api/v1/`. Admin endpoints are at `/api/v1/admin/`.

### SDK-facing endpoints (public, rate-limited)

#### `POST /api/v1/activate`

Validates a license key and returns a signed entitlement JWT.

```bash
curl -X POST https://YOUR_SERVER/api/v1/activate \
  -H "Content-Type: application/json" \
  -d '{
    "licenseKey": "pk_live_XXXX",
    "appId": "com.provider.softphone",
    "deviceId": "unique-device-id-abc123"
  }'
```

Response:
```json
{
  "entitlement": "<RS256 JWT>",
  "refreshToken": "<opaque token>",
  "expiresIn": 86400
}
```

The entitlement JWT payload:
```json
{
  "iss": "sipkit-license",
  "sub": "<providerId>",
  "appId": "com.provider.softphone",
  "features": ["audio", "video", "conference", "transfer", "dtmf"],
  "maxAccounts": 5,
  "maxConcurrentCalls": 50,
  "iat": 0,
  "exp": 0,
  "jti": "<uuid>"
}
```

Errors: `400` missing fields · `401` invalid/revoked/expired key or device limit reached · `429` rate limited

---

#### `POST /api/v1/refresh`

Rotates the refresh token and issues a fresh entitlement JWT. Call this before the JWT expires.

```bash
curl -X POST https://YOUR_SERVER/api/v1/refresh \
  -H "Content-Type: application/json" \
  -d '{ "refreshToken": "<token from activate>" }'
```

Response: same shape as `/activate`. Revoked or expired licenses return `401`.

---

#### `POST /api/v1/usage`

Reports usage metrics. Authenticated via entitlement JWT.

```bash
curl -X POST https://YOUR_SERVER/api/v1/usage \
  -H "Authorization: Bearer <entitlement JWT>" \
  -H "Content-Type: application/json" \
  -d '{
    "deviceId": "unique-device-id-abc123",
    "callMinutes": 15,
    "registrations": 1,
    "callsPlaced": 3
  }'
```

---

#### `GET /api/v1/public-key`

Returns the RS256 public key PEM. Bundle this into the Flutter SDK for offline JWT verification.

```bash
curl https://YOUR_SERVER/api/v1/public-key
```

#### `GET /api/v1/jwks`

Returns the public key as a JWKS JSON document.

---

### Admin endpoints (require `Authorization: Bearer <ADMIN_API_KEY>`)

#### `POST /api/v1/admin/providers`

Create a new VoIP provider.

```bash
curl -X POST https://YOUR_SERVER/api/v1/admin/providers \
  -H "Authorization: Bearer $ADMIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{ "name": "Acme VoIP", "contactEmail": "admin@acme.com" }'
```

---

#### `POST /api/v1/admin/providers/:providerId/licenses`

Issue a license key for a provider. **The plaintext key is returned once only.**

```bash
curl -X POST https://YOUR_SERVER/api/v1/admin/providers/PROVIDER_ID/licenses \
  -H "Authorization: Bearer $ADMIN_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "features": ["audio", "video", "conference", "transfer", "dtmf"],
    "maxAccounts": 10,
    "maxConcurrentCalls": 50,
    "maxDevices": 100,
    "expiresAt": "2027-01-01T00:00:00Z"
  }'
```

Valid features: `audio`, `video`, `conference`, `transfer`, `dtmf`

---

#### `POST /api/v1/admin/licenses/:licenseId/revoke`

Revoke a license immediately. All active refresh tokens for that license are also revoked. The SDK will lock within 24h (one JWT lifetime).

```bash
curl -X POST https://YOUR_SERVER/api/v1/admin/licenses/LICENSE_ID/revoke \
  -H "Authorization: Bearer $ADMIN_API_KEY"
```

---

#### `GET /api/v1/admin/usage?providerId=PROVIDER_ID`

Query usage events. Omit `providerId` to get all usage.

```bash
curl "https://YOUR_SERVER/api/v1/admin/usage?providerId=PROVIDER_ID" \
  -H "Authorization: Bearer $ADMIN_API_KEY"
```

---

## Running tests

```bash
pnpm --filter @workspace/api-server run test
```

Tests cover: JWT sign/verify (valid, expired, tampered, wrong key), feature gating, admin auth middleware (accept/reject), entitlement auth middleware (accept/reject).

---

## Security model

- **License keys** stored as bcrypt hashes (cost 12) — plaintext never persisted
- **Entitlement JWTs** short-lived (24h), RS256-signed — verified offline by the SDK using the bundled public key
- **Refresh tokens** hashed (bcrypt), rotated on every use, revocable individually or by revoking the parent license
- **`/v1/activate`** rate-limited: 20 requests per 15 minutes per IP
- **Revocation** takes effect on the next `/v1/refresh` — within one JWT TTL (24h default)
- **Offline grace** is enforced entirely by the SDK (72h default) — server has no role in that

## Architecture decisions

- Built directly in the shared Express api-server (no separate NestJS process needed)
- RS256 over HS256: public key can be safely bundled in the Flutter SDK for offline verification
- Bcrypt cost 12 for license key hashing — higher cost is acceptable since activation is rare
- Refresh token rotation on use — compromised tokens self-revoke after first use
- Generic `401 Unauthorized` for all activation failures — doesn't reveal which check failed
