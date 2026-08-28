---
name: Provider diagnostic safety
description: Safety rules for real-call troubleshooting sessions and shareable diagnostic evidence.
---

An opt-in controlled diagnostic call must retain its entitlement reservation until the matching terminal call event arrives, with only a bounded fallback if the native callback is broken.

**Why:** Native hangup methods return before PJSIP, CallKit, or Telecom necessarily confirms termination. Releasing the slot immediately can admit another call while the diagnostic call still consumes native or provider capacity.

**How to apply:** Any future diagnostic or probe call must wait for terminal state during cleanup, keep normal call-slot accounting aware of the reservation, and always bound the wait so a missing callback cannot stall forever.

Shareable diagnostic evidence must redact complete values when they resemble SIP authorization headers, Digest/Basic/Bearer payloads, or multiline protocol messages.

**Why:** Redacting only sensitive map keys or a single token can leave usernames, nonces, responses, credentials, or raw headers visible in untrusted native reason strings.

**How to apply:** Treat auth-shaped and protocol-shaped strings as unsafe by default, redact the whole value, and add hostile-value regression cases whenever evidence sources expand.