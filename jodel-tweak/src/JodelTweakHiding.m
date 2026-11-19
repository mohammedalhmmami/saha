// JodelTweakHiding.m — Hide the tweak from Jodel's own detection.
//
// Written from scratch in our own code. See JodelTweakHiding.h and
// HIDING.md (the decryption report) for what each hook is and why.
//
// The two hooks:
//   1. _TtC5Jodel14JDLUserService.setIsBanned:  — force the local ban
//      flag to NO (Zero's aban2).
//   2. TweakInject (any class) — return "clean" (Zero's aban1).
//
// Both are installed with plain ObjC runtime calls (NSClassFromString,
// method_exchangeImplementations, method_setImplementation) and guarded
// lookups. Nothing here touches App Attest, device identifiers, or HMAC.

#import "JodelTweakHiding.h"
#import "JodelTweakFeatures.h"
#import <objc/runtime.h>
#import <stdlib.h>   // malloc / free (class list)
#import <string.h>   // strlen (type-encoding length)

// ---------------------------------------------------------------------------
// Hook 1 — setIsBanned: on Jodel's JDLUserService (aban2 equivalent).
//
// Target (confirmed in the original Jodel v7.199 binary):
//   class    "_TtC5Jodel14JDLUserService"   (Swift class, ObjC runtime name)
//   selector "setIsBanned:"                 (takes a BOOL)
// After the exchange, calling [self jodelTweak_setIsBanned:] invokes the
// ORIGINAL setter. We always pass NO, so the local ban flag can never be
// set to YES through this setter. The incoming value is deliberately
// ignored (never used) so a Swift/ObjC BOOL encoding difference cannot
// matter: the only value ever forwarded is the constant NO (0).
// ---------------------------------------------------------------------------
@interface NSObject (JodelTweakHidingBan)
- (void)jodelTweak_setIsBanned:(BOOL)banned;
@end

@implementation NSObject (JodelTweakHidingBan)

- (void)jodelTweak_setIsBanned:(BOOL)banned {
    (void)banned;  // ignored on purpose — the flag is forced to NO.
    [self jodelTweak_setIsBanned:NO];
}

@end

static void JodelTweakInstallSetIsBannedHook(void) {
    @try {
        Class targetClass = NSClassFromString(@"_TtC5Jodel14JDLUserService");
        if (!targetClass) return;  // class not present — skip silently.

        SEL originalSel = NSSelectorFromString(@"setIsBanned:");
        SEL swizzledSel = @selector(jodelTweak_setIsBanned:);
        Method originalMethod = class_getInstanceMethod(targetClass, originalSel);
        // Get MY implementation from NSObject (where the category defines
        // it) — NOT from the target class. JDLUserService is a Swift class
        // and might not inherit NSObject; looking the method up on the
        // target would then return NULL and the hook would be skipped.
        // Fetching it from NSObject works in both cases.
        Method swizzledMethod = class_getInstanceMethod([NSObject class], swizzledSel);
        if (!originalMethod || !swizzledMethod) return;

        IMP myIMP = method_getImplementation(swizzledMethod);
        const char *myTypes = method_getTypeEncoding(swizzledMethod);
        // Add my method to the target class first, so an instance of the
        // target can call [self jodelTweak_setIsBanned:] even if the target
        // does not inherit NSObject.
        BOOL didAdd = class_addMethod(targetClass, swizzledSel, myIMP, myTypes);
        if (didAdd) {
            Method addedMethod = class_getInstanceMethod(targetClass, swizzledSel);
            if (addedMethod) {
                method_exchangeImplementations(originalMethod, addedMethod);
            }
        } else {
            // The target (or a superclass) already has our method — the
            // target inherits NSObject. A plain exchange is enough.
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    } @catch (NSException *e) {
        // Never crash the host app because of the tweak.
    }
}

// ---------------------------------------------------------------------------
// Hook 2 — TweakInject on ANY class (aban1 equivalent).
//
// Zero decrypts the class name "UserManagement" and the selector
// "TweakInject", plus the strings "MobileSubstrate", "CydiaSubstrate"
// and ".dylib". "UserManagement" does not appear in Jodel's binary or
// any of its frameworks, so the owning class cannot be identified
// statically. Instead we enumerate every loaded class at runtime and
// hook each method named TweakInject. The replacement returns "clean":
//   BOOL   -> NO        (not injected)
//   object -> nil       (no injected tweaks found)
//   void   -> nothing   (no-op)
// The return type is read from the method's own type encoding, and the
// method must take no arguments (TweakInject has no colon). Any method
// whose signature we do not recognise is left alone. Both instance
// methods and class methods are checked.
// ---------------------------------------------------------------------------

static BOOL JodelTweakCleanBool(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return NO;
}

static id JodelTweakCleanObject(id self, SEL _cmd) {
    (void)self; (void)_cmd;
    return nil;
}

static void JodelTweakCleanVoid(id self, SEL _cmd) {
    (void)self; (void)_cmd;
}

// Hook one TweakInject method if its signature is understood.
// Returns YES if the method was hooked.
static BOOL JodelTweakHookTweakInjectMethod(Method method) {
    if (!method) return NO;
    const char *types = method_getTypeEncoding(method);
    if (!types) return NO;
    // A no-argument method's encoding is: <return> "@" ":"
    // (return type, self, _cmd). We require exactly that shape.
    size_t len = strlen(types);
    if (len < 3) return NO;
    if (types[1] != '@' || types[2] != ':') return NO;

    IMP replacement = NULL;
    switch (types[0]) {
        case 'B':  // Swift/ObjC BOOL (C99 _Bool)
        case 'c':  // ObjC BOOL (signed char)
            replacement = (IMP)JodelTweakCleanBool;
            break;
        case '@':  // object (e.g. NSArray of detected tweaks)
            replacement = (IMP)JodelTweakCleanObject;
            break;
        case 'v':  // void
            replacement = (IMP)JodelTweakCleanVoid;
            break;
        default:
            // Unknown return type — do NOT hook. Guessing a return
            // value for an unknown signature could crash Jodel.
            return NO;
    }
    @try {
        method_setImplementation(method, replacement);
    } @catch (NSException *e) {
        return NO;
    }
    return YES;
}

static void JodelTweakInstallTweakInjectHooks(void) {
    @try {
        SEL tweakSel = NSSelectorFromString(@"TweakInject");
        if (!tweakSel) return;

        int classCount = objc_getClassList(NULL, 0);
        if (classCount <= 0) return;
        Class *classes = (Class *)malloc(sizeof(Class) * (size_t)classCount);
        if (!classes) return;
        classCount = objc_getClassList(classes, classCount);

        NSUInteger hooked = 0;
        for (int i = 0; i < classCount; i++) {
            Class cls = classes[i];
            if (!cls) continue;
            // Instance method.
            Method instanceMethod = class_getInstanceMethod(cls, tweakSel);
            if (instanceMethod) {
                if (JodelTweakHookTweakInjectMethod(instanceMethod)) hooked++;
            }
            // Class method (on the metaclass).
            Method classMethod = class_getClassMethod(cls, tweakSel);
            if (classMethod) {
                if (JodelTweakHookTweakInjectMethod(classMethod)) hooked++;
            }
        }
        free(classes);
        (void)hooked;  // count kept for future diagnostics; not logged.
    } @catch (NSException *e) {
        // Never crash the host app because of the tweak.
    }
}

// ---------------------------------------------------------------------------
// Installation.
// ---------------------------------------------------------------------------
void JodelTweakInstallHiding(void) {
    @try {
        // Master toggle gates everything; the hiding toggle gates just
        // these two hooks. Both default to ON (a missing key reads YES).
        if (!JodelTweakIsEnabled()) return;
        if (!JodelTweakHidingEnabled()) return;
        JodelTweakInstallSetIsBannedHook();
        JodelTweakInstallTweakInjectHooks();
    } @catch (NSException *e) {
    }
}
