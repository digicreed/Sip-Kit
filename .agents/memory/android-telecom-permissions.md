---
name: Android Telecom lookup permissions
description: Android Telecom permission behavior relevant to SipKit native VoIP setup.
---

Avoid using TelecomManager.getPhoneAccount() as an existence check for the SipKit VoIP phone account. Some Android releases enforce READ_PHONE_NUMBERS for that lookup even when the app only owns a self-managed VoIP provider flow.

**Why:** The native SIP engine can initialize successfully while Telecom account discovery throws a platform permission error, preventing activation before any SIP registration is attempted.

**How to apply:** Gate phone-account operations on MANAGE_OWN_CALLS and register the same PhoneAccountHandle idempotently instead of querying it first. Keep READ_PHONE_NUMBERS out of the VoIP permission surface unless a separate product requirement genuinely needs phone-number access.