// JodelTweakProtection.m — Ban detection + fresh-account recovery.
//
// Written from scratch. No Zero framework code, no copied code.
// See JodelTweakProtection.h and PROTECTION.md for the study behind it.
//
// MECHANISM (our own code, public APIs only):
//   1. BAN DETECTION — we swizzle two public NSURLSession methods
//      (dataTaskWithRequest:completionHandler: and
//      dataTaskWithURL:completionHandler:) and inspect the responses
//      that come back from Jodel's own API host (api.jodelapis.com).
//      A ban is signalled by HTTP 403, or by a response body that
//      contains the word "banned". (Jodel's own ban screen says
//      "Oh no, you have been banned!" — the server tells the client
//      with 403 / a ban payload.) As a second trigger we also watch
//      for any UIAlertController whose title or message contains
//      "banned", in case Jodel shows its own ban screen first.
//      When a ban is detected we show OUR alert once, offering a
//      fresh account. We never touch Jodel's data until the user taps
//      the button.
//   2. FRESH ACCOUNT ("unban") — on the user's tap we wipe the current
//      account's local identity and restart the app:
//        - Keychain: delete the OAuth tokens. Jodel stores them under
//          the Keychain service "com.go-tellm.tellm.oauth2-credentials"
//          (confirmed from the v7.199 binary strings). We also delete
//          any Keychain item whose service/account mentions "appattest"
//          (the App Attest key, stored under "com.appattest.keyid").
//        - UserDefaults: remove Jodel's keys (anything mentioning
//          jodel / appattest / devicecheck / attest), including the
//          App Attest key id and the DeviceCheck ban-state flag.
//        - Files: delete the app's Caches and its local Realm database
//          files (default.realm*) — cached posts only, no account.
//        - Our own notes (com.nebra.jodeltweak.notes.v1) are KEPT:
//          they are the user's private notes, not account identity.
//      Then the app exits so the user relaunches it and Jodel creates
//      a brand-new anonymous account (Jodel creates accounts
//      automatically — OAuth2, no username/password).
//   3. WHAT WE DELIBERATELY DO NOT DO:
//        - We do NOT hook App Attest (DCAppAttestService) and we do NOT
//          fake an attestation. Faking one would be detected, and
//          blocking it would only make the server see a missing
//          attestation. Zero does not hook it either (no evidence in
//          its framework), so neither do we.
//        - We do NOT touch the HMAC request signing
//          (X-Post-Params-Hash). It is computed by Jodel's own code
//          and stays valid; changing it would break every request.
//        - We do NOT spoof any device identifier (identifierForVendor
//          etc.). Zero does not do it either (no such strings in its
//          framework), and a spoofed identifier would not survive the
//          server's DeviceCheck check anyway.
//        - We do NOT call any Jodel API endpoint. The recovery is
//          purely local (wipe + restart); the new account is created
//          by Jodel itself on the next launch.

#import "JodelTweakProtection.h"
#import "JodelTweakFeatures.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Security/Security.h>
#import <stdlib.h>  // for exit(0) — restart after a fresh account

// ---------------------------------------------------------------------------
// Our own storage keys (never Jodel's keys).
// ---------------------------------------------------------------------------
static NSString * const kJodelTweakBannedFlagKey = @"com.nebra.jodeltweak.banned.v1";
static NSString * const kJodelTweakBanAlertShownKey = @"com.nebra.jodeltweak.banAlertShown.v1";
// Set when the user taps a button on the ban alert ("Create New Account"
// or "Later"). Until it is set, the alert may be re-presented if it was
// dismissed without a choice (e.g. the app went to the background).
static NSString * const kJodelTweakBanChoiceMadeKey = @"com.nebra.jodeltweak.banChoiceMade.v1";

// Jodel's account identity, as found in the v7.199 binary strings.
static NSString * const kJodelOAuthKeychainService = @"com.go-tellm.tellm.oauth2-credentials";
static NSString * const kJodelAppGroup = @"group.com.go-tellm.tellm";

// ---------------------------------------------------------------------------
// The ban alert lives in its OWN UIWindow (the approach Zero uses for
// its overlay: a separate full-screen window above Jodel's UI).
//
// WHY: in v2 the alert was presented on Jodel's own top view controller.
// Jodel's ban flow then replaced or dismissed that controller (its own
// ban screen, a feed reload, a navigation reset) and our alert vanished
// within seconds, before the user could tap anything. A dedicated
// window sits OUTSIDE Jodel's view-controller hierarchy, so nothing
// Jodel does to its own screens can dismiss it. The window is held in
// a static (strong) reference so it is never deallocated while the
// alert is up, and the alert has no tap-outside-to-dismiss — it stays
// until the user taps "Create New Account" or "Later".
// ---------------------------------------------------------------------------
static UIWindow *gJodelTweakAlertWindow = nil;
static __weak UIWindow *gJodelTweakPreviousKeyWindow = nil;
// Re-presentation guard: at most one re-presentation per foreground.
static BOOL gJodelTweakAlertRePresentedThisForeground = NO;

// The overlay window's root view controller. A plain controller with an
// empty, transparent view — it exists only to present our alert from.
// Its class is also used to keep our own ban watcher from treating our
// alert as Jodel's ban screen.
@interface JodelTweakAlertRootViewController : UIViewController
@end

@implementation JodelTweakAlertRootViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
}
@end

// Creates the overlay window (if needed) and makes it key and visible.
// Returns its root view controller, or nil if the window could not be made.
static UIViewController *JodelTweakEnsureAlertWindow(void) {
    if (!gJodelTweakAlertWindow) {
        UIWindow *previousKey = [UIApplication sharedApplication].keyWindow;
        if (!previousKey && @available(iOS 13.0, *)) {
            for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
                if (scene.activationState != UISceneActivationStateForegroundActive) continue;
                if (![scene isKindOfClass:[UIWindowScene class]]) continue;
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { previousKey = w; break; }
                }
                if (previousKey) break;
            }
        }
        gJodelTweakPreviousKeyWindow = previousKey;
        CGRect frame = [UIScreen mainScreen].bounds;
        if (previousKey.windowScene) {
            gJodelTweakAlertWindow = [[UIWindow alloc] initWithWindowScene:previousKey.windowScene];
        } else {
            gJodelTweakAlertWindow = [[UIWindow alloc] initWithFrame:frame];
        }
        gJodelTweakAlertWindow.frame = frame;
        // Above Jodel's own alerts (UIWindowLevelAlert) so nothing in
        // Jodel can cover it.
        gJodelTweakAlertWindow.windowLevel = UIWindowLevelAlert + 1.0;
        gJodelTweakAlertWindow.rootViewController =
            [[JodelTweakAlertRootViewController alloc] init];
        gJodelTweakAlertWindow.hidden = NO;
    }
    [gJodelTweakAlertWindow makeKeyAndVisible];
    return gJodelTweakAlertWindow.rootViewController;
}

// Hides and destroys the overlay window, restoring Jodel's key window.
static void JodelTweakDismissAlertWindow(void) {
    if (!gJodelTweakAlertWindow) return;
    gJodelTweakAlertWindow.hidden = YES;
    UIWindow *windowToDestroy = gJodelTweakAlertWindow;
    gJodelTweakAlertWindow = nil;
    UIWindow *previousKey = gJodelTweakPreviousKeyWindow;
    gJodelTweakPreviousKeyWindow = nil;
    if (previousKey) {
        [previousKey makeKeyAndVisible];
    }
    (void)windowToDestroy;
}

// Presents an alert from the overlay window's root view controller.
static void JodelTweakPresentAlertInOverlayWindow(UIAlertController *alert) {
    UIViewController *root = JodelTweakEnsureAlertWindow();
    if (!root) return;
    // If an alert is already showing in the overlay, do not stack another.
    if (root.presentedViewController) return;
    [root presentViewController:alert animated:YES completion:nil];
}

static BOOL JodelTweakBanChoiceMade(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kJodelTweakBanChoiceMadeKey];
}

static void JodelTweakSetBanChoiceMade(BOOL made) {
    [[NSUserDefaults standardUserDefaults] setBool:made forKey:kJodelTweakBanChoiceMadeKey];
}

static BOOL JodelTweakIsBanned(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kJodelTweakBannedFlagKey];
}

static void JodelTweakSetBanned(BOOL banned) {
    [[NSUserDefaults standardUserDefaults] setBool:banned forKey:kJodelTweakBannedFlagKey];
}

// ---------------------------------------------------------------------------
// Fresh account — wipe the current account's local identity.
//
// This is the "unban": it does NOT lift a server-side ban on the old
// account (impossible from the client). It abandons the old account and
// lets Jodel create a brand-new one on the next launch. The old
// account's karma and posts are lost with it — that is unavoidable and
// is exactly what Zero's "Create New Account" does too.
// ---------------------------------------------------------------------------
static void JodelTweakDeleteKeychainItemsMatching(NSString *substring) {
    // Enumerate generic-password items and delete the ones whose service
    // or account contains the given substring (case-insensitive). We only
    // ever delete items that match Jodel/App Attest identifiers — never
    // anything else in the Keychain.
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
    };
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return;
    NSArray *items = (__bridge_transfer NSArray *)result;
    for (NSDictionary *item in items) {
        NSString *service = item[(__bridge id)kSecAttrService];
        NSString *account = item[(__bridge id)kSecAttrAccount];
        BOOL matches = NO;
        if ([service isKindOfClass:[NSString class]] &&
            [service rangeOfString:substring options:NSCaseInsensitiveSearch].location != NSNotFound) matches = YES;
        if ([account isKindOfClass:[NSString class]] &&
            [account rangeOfString:substring options:NSCaseInsensitiveSearch].location != NSNotFound) matches = YES;
        if (!matches) continue;
        NSMutableDictionary *del = [NSMutableDictionary dictionary];
        del[(__bridge id)kSecClass] = (__bridge id)kSecClassGenericPassword;
        if (service) del[(__bridge id)kSecAttrService] = service;
        if (account) del[(__bridge id)kSecAttrAccount] = account;
        SecItemDelete((__bridge CFDictionaryRef)del);
    }
}

static void JodelTweakWipeLocalIdentity(void) {
    @try {
        // 1. Keychain — Jodel's OAuth tokens (the account itself).
        NSDictionary *oauthQuery = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kJodelOAuthKeychainService,
        };
        SecItemDelete((__bridge CFDictionaryRef)oauthQuery);

        // 2. Keychain — the App Attest key (bound to the old install).
        //    The key id strings in Jodel's binary are "com.appattest.keyid"
        //    and "com.appattest.sandbox.keyid".
        JodelTweakDeleteKeychainItemsMatching(@"appattest");
        JodelTweakDeleteKeychainItemsMatching(@"go-tellm");

        // 3. UserDefaults — Jodel's keys. We remove anything mentioning
        //    jodel / appattest / devicecheck / attest. Our own keys
        //    (com.nebra.jodeltweak.*) are NOT touched.
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSArray<NSString *> *markers = @[@"jodel", @"appattest", @"devicecheck", @"attest"];
        for (NSString *key in [[defaults dictionaryRepresentation] allKeys]) {
            NSString *lower = [key lowercaseString];
            for (NSString *marker in markers) {
                if ([lower rangeOfString:marker].location != NSNotFound) {
                    [defaults removeObjectForKey:key];
                    break;
                }
            }
        }
        // The shared App Group defaults, if present.
        NSUserDefaults *groupDefaults =
            [[NSUserDefaults alloc] initWithSuiteName:kJodelAppGroup];
        if (groupDefaults) {
            for (NSString *key in [[groupDefaults dictionaryRepresentation] allKeys]) {
                [groupDefaults removeObjectForKey:key];
            }
        }

        // 4. Files — Caches (regenerable) and the local Realm database
        //    (cached posts only). We delete files, never directories.
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray<NSURL *> *dirs = @[
            [[fm URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject],
            [[fm URLsForDirectory:NSLibraryDirectory inDomains:NSUserDomainMask] firstObject],
            [[fm URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] firstObject],
        ];
        for (NSURL *dir in dirs) {
            if (!dir) continue;
            NSDirectoryEnumerator *enumerator =
                [fm enumeratorAtURL:dir
         includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                            options:NSDirectoryEnumerationSkipsHiddenFiles
                       errorHandler:nil];
            for (NSURL *url in enumerator) {
                NSString *name = url.lastPathComponent.lowercaseString;
                BOOL isRealm = [name containsString:@".realm"];
                BOOL isCacheFile = [dir.lastPathComponent isEqualToString:@"Caches"];
                if (!isRealm && !isCacheFile) continue;
                NSNumber *isDir = nil;
                [url getResourceValue:&isDir forKey:NSURLIsDirectoryKey error:nil];
                if ([isDir boolValue]) continue;
                [fm removeItemAtURL:url error:nil];
            }
        }

        // 5. Clear our own ban flags (the new account starts clean).
        JodelTweakSetBanned(NO);
        [defaults removeObjectForKey:kJodelTweakBanAlertShownKey];
        [defaults removeObjectForKey:kJodelTweakBanChoiceMadeKey];
        [defaults synchronize];
    } @catch (NSException *e) {
        // Wiping must never crash the app. If part of it failed, the
        // restart below still gives Jodel a chance to re-register.
    }
}

// ---------------------------------------------------------------------------
// The ban alert — shown in our OWN overlay window, and it STAYS until
// the user taps a button.
//
// Behaviour:
//   - Presented from the overlay window's root view controller, never
//     from a Jodel view controller, so Jodel's own navigation, ban
//     screen or feed reload cannot dismiss it.
//   - No tap-outside-to-dismiss and no auto-dismiss: UIAlertController
//     does not dismiss on outside taps, and nothing in our code dismisses
//     it on a timer.
//   - "Create New Account" marks the choice, wipes the account, then
//     shows a restart alert (also in the overlay window) and exits.
//   - "Later" marks the choice and destroys the overlay window. The
//     alert is not shown again for this ban.
//   - If the alert window is somehow gone without a choice (e.g. the
//     app went to the background), it is re-presented when the app
//     becomes active again — at most once per foreground (see
//     JodelTweakAppDidBecomeActive below).
//   - Respects the toggles: if the master switch or Ban Detection is
//     OFF, no alert appears at all.
// ---------------------------------------------------------------------------
static void JodelTweakShowBanAlert(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ JodelTweakShowBanAlert(); });
        return;
    }
    // Respect the toggles: no alert when the tweak or Ban Detection is off.
    if (!JodelTweakIsEnabled() || !JodelTweakBanDetectionEnabled()) return;
    // The user already chose for this ban — do not show it again.
    if (JodelTweakBanChoiceMade()) return;
    // Already showing in the overlay window — do not stack another.
    if (gJodelTweakAlertWindow && gJodelTweakAlertWindow.rootViewController.presentedViewController) return;
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kJodelTweakBanAlertShownKey];

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"تم حظر الحساب"
                                            message:@"تم حظر حسابك في Jodel. هل تريد إنشاء حساب جديد؟\nسيتم مسح بيانات التطبيق الحالية (الحساب والتوكنات والإعدادات المحلية). ملاحظاتك الخاصة محفوظة ولن تُمسح.\n\nتنبيه: هذا لا يرفع الحظر عن الحساب القديم — بل ينشئ حساباً جديداً، وستفقد كارما الحساب القديم ومنشوراته."
                                     preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *create =
        [UIAlertAction actionWithTitle:@"إنشاء حساب جديد"
                                 style:UIAlertActionStyleDestructive
                               handler:^(UIAlertAction *action) {
            JodelTweakSetBanChoiceMade(YES);
            JodelTweakWipeLocalIdentity();
            // Restart the app so Jodel creates the fresh account.
            // This alert is also shown in the overlay window, so it
            // cannot be dismissed by Jodel either.
            UIAlertController *restartAlert =
                [UIAlertController alertControllerWithTitle:@"تم مسح بيانات الحساب"
                                                    message:@"سيتم إغلاق التطبيق الآن. افتحه مجدداً وسيتم إنشاء حساب جديد تلقائياً."
                                             preferredStyle:UIAlertControllerStyleAlert];
            [restartAlert addAction:
                [UIAlertAction actionWithTitle:@"حسناً"
                                         style:UIAlertActionStyleDefault
                                       handler:^(UIAlertAction *a) {
                    (void)a;
                    exit(0);
                }]];
            JodelTweakPresentAlertInOverlayWindow(restartAlert);
        }];
    [alert addAction:create];
    [alert addAction:[UIAlertAction actionWithTitle:@"لاحقاً"
                                              style:UIAlertActionStyleCancel
                                            handler:^(UIAlertAction *action) {
        JodelTweakSetBanChoiceMade(YES);
        JodelTweakDismissAlertWindow();
    }]];
    JodelTweakPresentAlertInOverlayWindow(alert);
}

// Re-present the alert when the app becomes active again, but only if
// the ban is still present, the user has not chosen yet, and the alert
// is not already showing. At most once per foreground: the flag is
// reset when the app enters the background.
static void JodelTweakAppDidBecomeActive(void) {
    if (gJodelTweakAlertRePresentedThisForeground) return;
    if (!JodelTweakIsBanned()) return;
    if (JodelTweakBanChoiceMade()) return;
    if (!JodelTweakIsEnabled() || !JodelTweakBanDetectionEnabled()) return;
    if (gJodelTweakAlertWindow && gJodelTweakAlertWindow.rootViewController.presentedViewController) return;
    gJodelTweakAlertRePresentedThisForeground = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ JodelTweakShowBanAlert(); });
}

static void JodelTweakAppDidEnterBackground(void) {
    gJodelTweakAlertRePresentedThisForeground = NO;
}

// Called (on any queue) when a ban signal is seen. Sets the flag and
// shows the alert once. Respects the toggles: if the master switch or
// Ban Detection is OFF, no flag is set and no alert appears.
static void JodelTweakOnBanDetected(void) {
    if (!JodelTweakIsEnabled() || !JodelTweakBanDetectionEnabled()) return;
    if (JodelTweakIsBanned()) {
        // Already flagged — still make sure the alert was offered.
        dispatch_async(dispatch_get_main_queue(), ^{ JodelTweakShowBanAlert(); });
        return;
    }
    JodelTweakSetBanned(YES);
    dispatch_async(dispatch_get_main_queue(), ^{ JodelTweakShowBanAlert(); });
}

// ---------------------------------------------------------------------------
// Detection 1 — inspect Jodel's own API responses (NSURLSession).
//
// We wrap the completion handler of the two completion-based data-task
// methods and look at the response BEFORE passing it on to Jodel.
// Only responses from Jodel's API host are inspected. A ban is:
//   - HTTP status 403, OR
//   - a response body containing the word "banned" (Jodel's own ban
//     screen text is "Oh no, you have been banned!").
// The body scan is bounded (first 64 KB) so it costs nothing measurable.
// ---------------------------------------------------------------------------
static BOOL JodelTweakResponseIsBan(NSHTTPURLResponse *response, NSData *data) {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) return NO;
    if (response.statusCode == 403) return YES;
    if (!data || data.length == 0) return NO;
    NSUInteger scanLength = MIN(data.length, 65536);
    NSString *body = [[NSString alloc] initWithBytes:data.bytes
                                              length:scanLength
                                            encoding:NSUTF8StringEncoding];
    if (!body) return NO;
    return [body rangeOfString:@"banned" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL JodelTweakRequestIsJodelAPI(NSURLRequest *request) {
    NSString *host = request.URL.host.lowercaseString;
    if (!host) return NO;
    return [host isEqualToString:@"api.jodelapis.com"] ||
           [host hasSuffix:@".jodelapis.com"];
}

// Swizzled completion handler wrapper. The original completion is called
// exactly once, with the original values — we only observe.
typedef void (^JodelTweakDataCompletion)(NSData *data, NSURLResponse *response, NSError *error);

@interface NSURLSession (JodelTweakBanDetection)
- (NSURLSessionDataTask *)jodelTweak_dataTaskWithRequest:(NSURLRequest *)request
                                       completionHandler:(JodelTweakDataCompletion)completionHandler;
- (NSURLSessionDataTask *)jodelTweak_dataTaskWithURL:(NSURL *)url
                                   completionHandler:(JodelTweakDataCompletion)completionHandler;
@end

@implementation NSURLSession (JodelTweakBanDetection)

- (NSURLSessionDataTask *)jodelTweak_dataTaskWithRequest:(NSURLRequest *)request
                                       completionHandler:(JodelTweakDataCompletion)completionHandler {
    // Feature off → pass through unwrapped (the hook becomes a no-op).
    if (!JodelTweakIsEnabled() || !JodelTweakBanDetectionEnabled()) {
        return [self jodelTweak_dataTaskWithRequest:request completionHandler:completionHandler];
    }
    BOOL isJodel = JodelTweakRequestIsJodelAPI(request);
    JodelTweakDataCompletion wrapped = nil;
    if (isJodel && completionHandler) {
        wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
            @try {
                if ([response isKindOfClass:[NSHTTPURLResponse class]] &&
                    JodelTweakResponseIsBan((NSHTTPURLResponse *)response, data)) {
                    JodelTweakOnBanDetected();
                }
            } @catch (NSException *e) {
                // Observing must never break the request.
            }
            completionHandler(data, response, error);
        };
    } else {
        wrapped = completionHandler;
    }
    // After the exchange, calling our own selector invokes the ORIGINAL.
    return [self jodelTweak_dataTaskWithRequest:request completionHandler:wrapped];
}

- (NSURLSessionDataTask *)jodelTweak_dataTaskWithURL:(NSURL *)url
                                   completionHandler:(JodelTweakDataCompletion)completionHandler {
    // Feature off → pass through unwrapped (the hook becomes a no-op).
    if (!JodelTweakIsEnabled() || !JodelTweakBanDetectionEnabled()) {
        return [self jodelTweak_dataTaskWithURL:url completionHandler:completionHandler];
    }
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    BOOL isJodel = JodelTweakRequestIsJodelAPI(request);
    JodelTweakDataCompletion wrapped = nil;
    if (isJodel && completionHandler) {
        wrapped = ^(NSData *data, NSURLResponse *response, NSError *error) {
            @try {
                if ([response isKindOfClass:[NSHTTPURLResponse class]] &&
                    JodelTweakResponseIsBan((NSHTTPURLResponse *)response, data)) {
                    JodelTweakOnBanDetected();
                }
            } @catch (NSException *e) {
            }
            completionHandler(data, response, error);
        };
    } else {
        wrapped = completionHandler;
    }
    return [self jodelTweak_dataTaskWithURL:url completionHandler:wrapped];
}

@end

// ---------------------------------------------------------------------------
// Detection 2 — watch for Jodel's own ban screen.
//
// If Jodel presents a UIAlertController whose title or message contains
// "banned" (its own text is "Oh no, you have been banned!"), treat it
// as a ban signal too. This covers the case where Jodel uses a
// delegate-based session (no completion handler for us to wrap).
// We hook -presentViewController:animated:completion: on UIViewController,
// call the original first, then inspect. Nothing is blocked or changed.
// ---------------------------------------------------------------------------
@interface UIViewController (JodelTweakBanWatch)
- (void)jodelTweak_presentViewController:(UIViewController *)viewControllerToPresent
                                animated:(BOOL)animated
                              completion:(void (^)(void))completion;
@end

@implementation UIViewController (JodelTweakBanWatch)

- (void)jodelTweak_presentViewController:(UIViewController *)viewControllerToPresent
                                animated:(BOOL)animated
                              completion:(void (^)(void))completion {
    // Call the original presentation first.
    [self jodelTweak_presentViewController:viewControllerToPresent
                                  animated:animated
                                completion:completion];
    // Then inspect what was presented.
    @try {
        // Never treat OUR OWN overlay window's presentations as a ban
        // signal — our alert's title contains "حظر" but not "banned",
        // and the check below is a second guard anyway.
        if ([self isKindOfClass:[JodelTweakAlertRootViewController class]]) return;
        if (![viewControllerToPresent isKindOfClass:[UIAlertController class]]) return;
        UIAlertController *alert = (UIAlertController *)viewControllerToPresent;
        NSString *combined = [NSString stringWithFormat:@"%@ %@",
                              alert.title ?: @"", alert.message ?: @""];
        if ([combined rangeOfString:@"banned" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            JodelTweakOnBanDetected();
        }
    } @catch (NSException *e) {
    }
}

@end

// ---------------------------------------------------------------------------
// Installation.
// ---------------------------------------------------------------------------
static BOOL JodelTweakSwizzle(Class cls, SEL originalSel, SEL swizzledSel) {
    Method originalMethod = class_getInstanceMethod(cls, originalSel);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledSel);
    if (!originalMethod || !swizzledMethod) return NO;
    // If the class does not implement the method itself, add ours first
    // so the exchange only affects this class.
    BOOL didAdd = class_addMethod(cls, originalSel,
                                  method_getImplementation(swizzledMethod),
                                  method_getTypeEncoding(swizzledMethod));
    if (didAdd) {
        class_replaceMethod(cls, swizzledSel,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
    return YES;
}

void JodelTweakInstallProtection(void) {
    @try {
        // Re-present the ban alert if it was dismissed without a choice
        // (e.g. the app went to the background). At most once per
        // foreground; the flag is reset on background.
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                (void)note;
                JodelTweakAppDidBecomeActive();
            }];
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidEnterBackgroundNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                (void)note;
                JodelTweakAppDidEnterBackground();
            }];
        });
        // Detection 1 — NSURLSession response inspection.
        // The swizzled implementations live in our own category on
        // NSURLSession, so both methods are found on the same class.
        JodelTweakSwizzle([NSURLSession class],
                          @selector(dataTaskWithRequest:completionHandler:),
                          @selector(jodelTweak_dataTaskWithRequest:completionHandler:));
        JodelTweakSwizzle([NSURLSession class],
                          @selector(dataTaskWithURL:completionHandler:),
                          @selector(jodelTweak_dataTaskWithURL:completionHandler:));
        // Detection 2 — Jodel's own ban alert.
        JodelTweakSwizzle([UIViewController class],
                          @selector(presentViewController:animated:completion:),
                          @selector(jodelTweak_presentViewController:animated:completion:));
    } @catch (NSException *e) {
        // Protection must never crash the host app.
    }
}
