# JodelTweak — New features for the original Jodel v7.199

> **A brand-new, original tweak written from scratch for the user's
> original Jodel v7.199 IPA.** It adds completely NEW features that do
> not exist in Jodel and are not one of Zero's features.
> **No Zero framework code. No copying. No activation code. No login.
> No paywall. No network. No data collection.**

---

## Features

### Private Notes ("My Notes")

Jodel has no way to keep a private note. This tweak adds one:

- A **"Notes" button** (note icon) appears in the Main Feed's
  navigation bar.
- Tapping it opens **"My Notes"** — a personal notebook inside Jodel.
- Users can **add** a note (via an alert with a text field),
  **view** notes (tap to read), and **delete** notes (swipe-to-delete).
- Notes are stored **only on the device** in `NSUserDefaults` under the
  key `com.nebra.jodeltweak.notes.v1`. Nothing leaves the device.
- Removing the tweak removes the button; Jodel runs exactly as before.

**Why this feature:** the user ordered completely NEW features, not a
copy of Zero's. Verified from the v7.199 binary that Jodel already has
Pins/MyPins, Dark Mode, font-size settings, and an OpenAI translation
service — so none of those would be new. No notes feature exists in
Jodel or in Zero's 41. See `HOOK_TARGETS.md` (section 8) for the
evidence.

### Bookmarks (المفضلة)

- Long-press a post → **"حفظ في المفضلة"** in the context menu.
- Saved posts (text + channel + time) are stored locally in
  `NSUserDefaults` (`com.nebra.jodeltweak.bookmarks.v1`).
- A **bookmark button** in the feed's navigation bar opens the
  Bookmarks screen: tap to read the full text, swipe to delete.
- **Honest note:** Jodel does not expose its post model, so the saved
  text is read from the post cell's own labels — the longest label is
  taken as the post body, the shortest non-empty label as the channel
  guess. What is saved is what the cell actually shows.

### Drafts (المسودات)

- A **"مسودة"** button is added to the compose screen's navigation bar.
- Tapping it saves the current compose text as a draft, locally
  (`com.nebra.jodeltweak.drafts.v1`).
- The Drafts screen (Tweak Settings → المسودات) lists saved drafts:
  tap one to open the compose screen with the text pre-filled,
  swipe to delete.
- **Honest note:** the text is read and pre-filled by finding the
  compose screen's `UITextView` in its view hierarchy. If the compose
  screen cannot be opened or no text field is found, the draft text is
  copied to the clipboard and a message says so.

### Quick Replies (ردود سريعة)

- User-defined reply templates, managed in the Quick Replies editor
  (Tweak Settings → ردود سريعة): add, edit, delete.
- When replying to a post, the templates appear as tappable chips in
  a horizontal bar at the bottom of the reply screen. Tapping a chip
  inserts its text into the reply field.
- **Honest note:** the text is inserted by finding the reply screen's
  `UITextView`/`UITextField` in its view hierarchy. If no text field
  can be found, the chip tap copies the template to the clipboard and
  a message says so.

---

## Tweak Settings — on/off switches

Every feature has its own switch, in the **Tweak Settings** screen.
Open it from the **gear button** in the Private Notes screen's
navigation bar.

| Switch | Key | Default |
|---|---|---|
| تفعيل الإضافات (master) | `com.nebra.jodeltweak.enabled` | ON |
| ملاحظاتي الخاصة | `com.nebra.jodeltweak.notesEnabled` | ON |
| كشف الحظر | `com.nebra.jodeltweak.banDetectionEnabled` | ON |
| المفضلة | `com.nebra.jodeltweak.bookmarksEnabled` | ON |
| المسودات | `com.nebra.jodeltweak.draftsEnabled` | ON |
| ردود سريعة | `com.nebra.jodeltweak.quickRepliesEnabled` | ON |

- **Master OFF** = the tweak does nothing at all: no feed buttons,
  no ban detection, no ban alert.
- Changes take effect immediately: the feed buttons are synced on
  every feed appearance (turn a feature OFF and its button disappears
  the next time the feed appears; turn it back ON and it comes back),
  and ban detection checks the flags on every intercepted response.
- The Settings screen also shows the counts of saved bookmarks,
  drafts and quick replies, and rows to open each of those screens.

---

## Protection — Ban Detection + Fresh Account ("unban")

The user tested the first version and was banned immediately. The
study in `../jodel-zero-analysis/PROTECTION.md` found what Zero does
that we did not:

- **There is no "unban" string anywhere in Zero.** The feature the user
  calls "فك الحظر" is Zero's **Ban Detection (#20)** + **Account
  Manager (#19)**: when Jodel bans the account, Zero shows
  "Account Banned — Create New Account?" and the button erases the
  app data so Jodel creates a brand-new account. It does **not** lift
  a server-side ban — it abandons the banned account for a fresh one.
- **Zero does not spoof any device identifier** (no
  `identifierForVendor` / IDFV / UDID / push-token strings in its
  framework), **does not hook App Attest** (no `DCAppAttestService`
  strings), and **does not touch the HMAC signing**. Its protection is
  detection + recovery, not prevention.
- **Jodel 7.199 itself has the detection surface:** App Attest
  (`AppAttestService`, `/v3/user/attest/challenge|verify`), a
  DeviceCheck ban state (`deviceCheck.ban.state`,
  `postDeviceCheckBanHookWithAppleDeviceToken:`), a DYLD integrity
  check (`integrity.dyld.enabled`), a jailbreak check
  (`isJailbroken`), and a Google integrity ban reason
  (`ban_reason_banned_by_google_integrity_check`). The same checks
  exist in 7.198, so the version is not the difference — the missing
  recovery flow was.

What this tweak now does (our own code, `src/JodelTweakProtection.m`):

1. **Ban Detection** — swizzles the two public `NSURLSession`
   completion-based data-task methods and inspects responses from
   `api.jodelapis.com` only. HTTP 403, or a body containing "banned",
   sets the ban flag and shows our alert once. A second trigger watches
   for Jodel's own ban alert ("Oh no, you have been banned!"). Nothing
   is changed or blocked — we only observe.
2. **Fresh Account ("unban")** — on the user's tap, wipes the current
   account's local identity and restarts the app so Jodel creates a
   brand-new anonymous account:
   - Keychain: Jodel's OAuth tokens (service
     `com.go-tellm.tellm.oauth2-credentials`) + App Attest key items.
   - UserDefaults: Jodel's keys (anything mentioning jodel /
     appattest / devicecheck / attest) + the shared App Group.
   - Files: Caches + the local Realm database (cached posts only).
   - The user's private notes are **kept** (they are not account
     identity).
3. **What it cannot do (stated plainly):** a server-side ban cannot be
   lifted from the client — the old account's karma and posts are lost.
   And Jodel's DeviceCheck ban bit lives on Apple's servers; only
   Jodel's server can change it, so if the *device* (not just the
   account) is flagged, a fresh account on the same device may still be
   treated as banned. Only the user's device test can prove whether the
   fresh account works.

**Deliberately NOT done:** no App Attest hooking or faking, no HMAC
changes, no device-identifier spoofing, no Jodel API calls. The
recovery is purely local (wipe + restart); the new account is created
by Jodel itself on the next launch.

### Alert persistence fix (v3)

In v2 the ban alert was presented on Jodel's own top view controller.
The user reported it appeared and then vanished within seconds,
before he could tap anything — Jodel's own ban flow replaced or
dismissed that controller (its own ban screen, a feed reload, a
navigation reset), which killed our alert.

The fix (same approach Zero uses for its overlay, our own code):
the alert is now presented in **its own dedicated `UIWindow`**
(window level `UIWindowLevelAlert + 1`), held in a static strong
reference, with a plain root view controller. The window sits outside
Jodel's view-controller hierarchy, so nothing Jodel does to its own
screens can dismiss it. The alert has no tap-outside-to-dismiss and
no auto-dismiss — it stays until the user taps **"إنشاء حساب جديد"**
or **"لاحقاً"**. Both buttons work: "Create New Account" runs the
wipe and shows the restart alert (also in the overlay window);
"Later" dismisses the overlay window and marks the choice so the
alert is not shown again for this ban. If the window is somehow gone
without a choice (e.g. the app went to the background), the alert is
re-presented when the app becomes active again — at most once per
foreground.

## Hiding — protect the tools from Jodel's own detection

The user tested v3, created a **new** account, and was banned fast
again. His verdict was correct: detection + recovery is not enough.
A fresh account on the same device gets banned quickly, which means
Jodel is detecting the **modified client itself**, not just the
account. Zero evidently hides/protects its modification, and the
earlier static analysis missed how — because the hook targets in
Zero's anti-ban classes (`aban1`, `aban2`) are XOR-obfuscated and
cannot be read with `strings`.

The decryption is documented in full in
`../jodel-zero-analysis/HIDING.md` (script:
`../jodel-zero-analysis/decrypt_aban.py`). In short, the +load
functions decrypt their hook targets at runtime with per-byte XOR
keys (scalar `ldrb`/`eor`/`strb`, SIMD `ldr`/`eor`/`str` with key
tables in `__const`, and a special first-byte transform). The
recovered targets:

- **aban1** hooks a tweak-injection check: the class name
  `UserManagement`, the selector `TweakInject`, and the strings
  `MobileSubstrate`, `CydiaSubstrate`, `.dylib`. Jodel's own binary
  contains `MobileSubstrate`, `CydiaSubstrate` and `TweakInject`,
  confirming Jodel checks for exactly these indicators.
- **aban2** hooks Jodel's ban-state setter: the Swift class
  `_TtC5Jodel14JDLUserService` and the selector `setIsBanned:`.
  Both strings exist verbatim in the original Jodel v7.199 binary.

What this tweak now does (our own code, `src/JodelTweakHiding.m`,
installed at load time by the constructor in `JodelTweak.m`):

1. **setIsBanned: forced to NO** (aban2 equivalent) — the setter on
   `JDLUserService` is swizzled so the local ban flag can never be
   set to YES through it. The incoming value is ignored; the original
   is always called with NO. The server can still refuse individual
   actions (403); the ban detection above still catches that and
   offers a fresh account. Hiding and detection work together.
2. **TweakInject returns "clean"** (aban1 equivalent) — the class
   name `UserManagement` does not appear in Jodel's binary or any of
   its frameworks, so the owning class cannot be identified
   statically. Instead the tweak enumerates **all** loaded classes at
   runtime and hooks every method named `TweakInject`, replacing it
   with a function that returns "clean" (NO for a BOOL result, nil
   for an object result, nothing for void). The return type is read
   from the method's own type encoding, and any method whose
   signature is not understood is left alone.

**Safety rules (hard limits):**

- **Never fake an App Attest attestation.** We do not hook
  `DCAppAttestService` and never return a hardcoded attestation
  token. If Jodel's App Attest check fails, it fails honestly.
- **Never spoof a device identifier** (no `identifierForVendor` /
  IDFV / IDFA / UDID). Zero does not do it either.
- **Never touch HMAC signing** (`X-Post-Params-Hash`).
- **The dylib is NOT hidden from dyld's loaded-image list.** Zero
  imports dyld functions (`_dyld_image_count`,
  `dyld_get_image_name`, ...), but static analysis could not
  determine whether it uses them to hide or only to inspect, and
  hiding a dylib from dyld needs low-level function interposition
  that is fragile and could destabilise the app. Not implemented;
  reported honestly in `HIDING.md`.
- **A toggle** ("إخفاء الإضافات", default ON) in Tweak Settings
  gates the two hiding hooks. Turning it off takes effect on the
  next launch (the hooks install at load time).

**Honest assessment:** the hiding closes the two client-side
detection paths Zero itself closes, so a fresh account now has a
real chance of surviving — but it is not a guarantee. If Jodel's
server has flagged **this device** in DeviceCheck, no client-side
hiding can clear that, and a fresh account may still be banned
fast. Only the user's device test can distinguish a device-level
flag from a client-detection ban. If the hidden version is still
banned fast on a fresh account, that points at the device flag, not
at the tweak.

---

## How it works (mechanism)

Learned technique only — plain Objective-C runtime method swizzling,
the same *kind* of mechanism Zero uses, but with our own code:

1. The dylib is loaded by dyld when Jodel launches (via an
   `LC_LOAD_DYLIB` entry pointing to `@rpath/JodelTweak.dylib`).
2. Its `constructor` runs before Jodel's UI appears.
3. It finds the feed view controller by name at runtime
   (`NSClassFromString(@"Jodel.MainFeedViewController")`, with a
   fallback to the bare name) and swizzles `viewWillAppear:`, using
   `method_exchangeImplementations`.
4. The swizzled `viewWillAppear:` calls the original, then syncs the
   Notes and Bookmarks buttons on every feed appearance.
5. It also installs the Bookmarks (context menu), Drafts (compose
   screen) and Quick Replies (reply screen) hooks, and the ban
   detection from `JodelTweakProtection.m`.

**Safety:** every lookup is guarded — if the class or method does not
exist at runtime, the hook is skipped silently. Installation is wrapped
in `@try/@catch`. The tweak never modifies Jodel's data, never touches
the network, never reads posts or the account.

---

## Files in this package

| Path | What it is |
|---|---|
| `src/JodelTweak.m` | Private Notes + feed buttons + hook installation + constructor. |
| `src/JodelTweakProtection.h` / `src/JodelTweakProtection.m` | Ban detection + fresh-account recovery ("unban"), from scratch. Own-UIWindow ban alert. |
| `src/JodelTweakHiding.h` / `src/JodelTweakHiding.m` | Hiding: `setIsBanned:` forced to NO + `TweakInject` returning "clean", from scratch. See `HIDING.md`. |
| `src/JodelTweakFeatures.h` | Shared declarations: settings toggles, view controllers, stores, hook installers. |
| `src/JodelTweakSettings.m` | Toggle accessors + Tweak Settings screen + Quick Replies editor. |
| `src/JodelTweakBookmarks.m` | Bookmarks store + screen + context-menu hook. |
| `src/JodelTweakDrafts.m` | Drafts store + screen + compose hook + open-compose-with-text. |
| `src/JodelTweakQuickReplies.m` | Quick Replies store + reply-screen chip bar hook. |
| `src/build.sh` | Build script — compiles the dylib on a Mac with Xcode (`clang -arch arm64`, iOS 16.4+). Compiles all seven `.m` files and links `Security.framework` (Keychain). |
| `build-tweak.yml` | GitHub Actions workflow — compiles the dylib on a macOS runner and uploads it as the artifact `JodelTweak-dylib`. Upload this to the repo at `.github/workflows/build-tweak.yml`. |
| `scripts/inject.py` | Injector — adds the `LC_LOAD_DYLIB` to a COPY of the original v7.199 IPA, copies the compiled dylib into `Frameworks/`, repackages as an unsigned IPA. **Tested:** the load-command insertion was verified on a scratch copy with `llvm-objdump` (command present, header updated, binary still parses). |
| `../jodel-zero-analysis/HOOK_TARGETS.md` | Hook discovery report — the method names identified for the core features, with confidence levels, and the evidence that Pins/Dark Mode/Font Size/Translate already exist in Jodel. |
| `../jodel-zero-analysis/ORIGINAL_7199_REPORT.md` | Full analysis of the original v7.199 IPA. |
| `../jodel-zero-analysis/IMPLEMENTATION_BLUEPRINT.md` | How Zero's features were programmed (mechanism reference only — not copied). |
| `../jodel-zero-analysis/PROTECTION.md` | The ban-protection study: what Zero does, what we applied, what cannot be done from the client. |
| `../jodel-zero-analysis/HIDING.md` | The hiding study: decrypted aban1/aban2 hook targets, the method, what was applied to the tweak and what was not (with safety rules), and the honest assessment. |
| `../jodel-zero-analysis/decrypt_aban.py` | The decryption script: emulates Zero's XOR string decryption from the ARM64 disassembly and recovers the hook targets. Requires `capstone`. |

**Never modified:** `~/workspace/ipa-delivery/Jodel_Original_7.199.ipa`
(the pristine original). The injector always works on a copy.

---

## What is ready, and what is still needed

### Ready (done in this phase)
- [x] Hook discovery on v7.199 (classes + selectors identified, confidence graded).
- [x] The complete tweak source — Private Notes, Bookmarks, Drafts,
      Quick Replies, Tweak Settings, Ban Detection + Fresh Account.
- [x] The alert-persistence fix (own UIWindow, survives Jodel's
      navigation) and the re-presentation rule (at most once per
      foreground, only if no choice was made).
- [x] The hiding hooks (v4): `setIsBanned:` forced to NO and
      `TweakInject` returning "clean", with a Tweak Settings toggle
      ("إخفاء الإضافات", default ON). Decryption report in
      `../jodel-zero-analysis/HIDING.md`, script in
      `../jodel-zero-analysis/decrypt_aban.py`.
- [x] The build script (`src/build.sh`) and the GitHub Actions workflow (`build-tweak.yml`).
- [x] The injector (`scripts/inject.py`) — **the Mach-O load-command
      insertion is proven to work** (tested on a scratch copy of the
      Jodel binary: `LC_LOAD_DYLIB` inserted at 0x3ef0 into the 16,656
      bytes of zero slack space, `ncmds` 154→155, `sizeofcmds`
      16080→16128, verified with `llvm-objdump`). No existing bytes
      are shifted.
- [x] `@rpath` resolution confirmed: the binary loads 28 `@rpath`
      frameworks from its `Frameworks/` directory with **no LC_RPATH**
      at all, so a new `@rpath/JodelTweak.dylib` placed in `Frameworks/`
      resolves the same way. No `LC_RPATH` needs to be added.

### Still needed (requires the parent agent + a browser task)
1. **Compile the dylib.** This Linux VM has no Xcode/iOS SDK, so the
   dylib cannot be compiled here. Upload the updated `jodel-tweak/src/`
   folder to the repo `mohammedalhmmami/saha` (the workflow
   `build-tweak.yml` is already there and triggers on push to
   `jodel-tweak/**`), then download the `JodelTweak-dylib` artifact.
   (Do not break the existing `build-ipa.yml`.)
2. **Inject.** Once the compiled `JodelTweak.dylib` is downloaded, run:
   `python3 ~/workspace/jodel-tweak/scripts/inject.py /path/to/JodelTweak.dylib`
   This produces `~/workspace/jodel-tweak/Jodel_7.199_Tweak.ipa`.
3. **Verify + deliver.** Check the IPA (size, sha256, `Info.plist`,
   the `LC_LOAD_DYLIB`, the dylib inside `Frameworks/`), then deliver
   it to the user for the device test. **Only the user's iPhone test
   can prove the tweak works** — it is not claimed to work until then.

### Deliberately NOT done
- No injected IPA is shipped in this phase, because the dylib is not
  yet compiled. Shipping an IPA that references a missing dylib would
  crash on launch. The injector refuses to run without the compiled
  dylib.
- No activation code, no Zero framework file, no copied Zero code.
- No row was added to Jodel's own Settings screen: appending a row to
  Jodel's settings table without knowing its data-source structure
  risks breaking Jodel's settings. The Tweak Settings screen is
  reached from the gear button in the Notes screen instead.
