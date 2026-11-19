// JodelTweakProtection.h — Ban detection + fresh-account recovery ("unban").
//
// WHAT THIS IS:
//   The protection half of the JodelTweak tweak for the user's original
//   Jodel v7.199 IPA. Written from scratch in our own code. It does TWO
//   things, both learned from studying how the Zero mod handles bans
//   (see PROTECTION.md for the full study):
//
//     1. BAN DETECTION — watches Jodel's own server responses and shows
//        an "Account Banned" alert the moment a ban is detected.
//     2. FRESH ACCOUNT ("unban") — on the user's tap, wipes the current
//        account's local identity (OAuth tokens in the Keychain, the
//        App Attest key, Jodel's UserDefaults keys, caches and the local
//        database) and restarts the app, so Jodel creates a brand-new
//        anonymous account on the next launch.
//
// HONEST LIMIT (read this before expecting a miracle):
//   A server-side ban CANNOT be lifted from the client. Nothing in this
//   file contacts Jodel's server, and nothing here can un-ban an account
//   on Jodel's side. What the "fresh account" does is give the user a
//   NEW account (new tokens, new identity) — the old banned account is
//   abandoned, with its karma and posts. That is exactly what Zero's
//   "Create New Account" does too (its own text says "The current app
//   data will be erased").
//
//   There is one more limit: Jodel stores a ban state in Apple's
//   DeviceCheck (the string "deviceCheck.ban.state" is in Jodel's
//   binary). The DeviceCheck bits live on Apple's servers and only
//   Jodel's server can change them — no client code can clear them.
//   So if Jodel's server has flagged THIS DEVICE (not just the account),
//   a fresh account on the same device may still be treated as banned.
//   That cannot be determined or fixed from the client. This is stated
//   plainly in PROTECTION.md.
//
// NO activation code. NO Zero framework code. NO network call to any
// third party. NO data collection. The only network inspection is
// reading Jodel's OWN responses to Jodel's OWN server, on the device,
// to detect a ban — nothing is sent anywhere.

#import <Foundation/Foundation.h>

// Installs the protection hooks. Safe to call once at load time;
// every lookup is guarded and failures are silent (no crash).
void JodelTweakInstallProtection(void);
