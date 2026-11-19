// JodelTweakHiding.h — Hide the tweak from Jodel's own detection.
//
// WHAT THIS IS:
//   The hiding half of the JodelTweak tweak for the user's original
//   Jodel v7.199 IPA. Written from scratch in our own code. It applies
//   the two hiding hooks that the Zero mod uses (recovered by decrypting
//   the XOR-obfuscated hook targets in ZeroJodel.framework — see
//   HIDING.md for the full decryption report). The goal is the one the
//   user stated after the v3 test: a fresh account gets banned fast
//   because Jodel detects the MODIFIED CLIENT itself, not just the
//   account. Detection + recovery alone is not enough; the modification
//   itself has to be hidden from Jodel's checks.
//
// THE TWO HOOKS (each is Zero's hook, re-implemented from scratch):
//
//   1. JDLUserService.setIsBanned:  (Zero's aban2)
//      Jodel's own class _TtC5Jodel14JDLUserService has a setIsBanned:
//      setter. When Jodel's server says the account is banned, Jodel
//      calls it with YES and the app locks the user out. We intercept
//      the setter and always pass NO to the original, so the local ban
//      flag can never be set to YES through this path. The server can
//      still refuse individual actions (403); the existing ban
//      detection (JodelTweakProtection) still catches that and offers
//      a fresh account. Hiding and detection work together.
//
//   2. TweakInject  (Zero's aban1)
//      Jodel checks for tweak/jailbreak injection: its binary contains
//      the strings "MobileSubstrate", "CydiaSubstrate" and a method
//      named "TweakInject". We do not know statically which class owns
//      TweakInject (the class name "UserManagement" that Zero decrypts
//      does not appear in Jodel's binary or any of its frameworks),
//      so instead of guessing a class we enumerate ALL loaded classes
//      at runtime and hook every method named TweakInject, replacing
//      it with a function that returns "clean" (NO for a BOOL result,
//      nil for an object result, nothing for void). The return type is
//      read from the method's own type encoding at runtime, so we only
//      hook methods whose signature we understand; anything else is
//      left alone.
//
// SAFETY RULES (hard limits — see HIDING.md):
//   - We NEVER fake an App Attest attestation. We do not hook
//     DCAppAttestService and we never return a hardcoded attestation
//     token. If Jodel's App Attest check fails, it fails honestly.
//   - We NEVER spoof a device identifier (no identifierForVendor /
//     IDFV / IDFA / UDID). Zero does not do it either.
//   - We NEVER touch HMAC request signing (X-Post-Params-Hash).
//   - We do NOT hide the dylib from dyld's loaded-image list.
//     Zero imports dyld functions (_dyld_image_count,
//     dyld_get_image_name, ...), but static analysis could not
//     determine whether it uses them to hide or only to inspect.
//     Hiding a dylib from dyld needs low-level function interposition
//     that is fragile and could destabilise the app, so it is NOT
//     implemented. Reported honestly in HIDING.md.
//   - Every lookup is guarded; a missing class or method is skipped
//     silently. All installation is wrapped in @try/@catch so the
//     tweak can never crash Jodel at launch.
//
// NO activation code. NO Zero framework code. NO network. NO data
// collection. The hiding is purely local method interception.

#import <Foundation/Foundation.h>

// Installs the hiding hooks. Safe to call once at load time.
// Respects the master toggle and the hiding toggle (both default ON).
void JodelTweakInstallHiding(void);
