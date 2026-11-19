// JodelTweakFeatures.h — shared declarations for the JodelTweak tweak.
//
// This header is the single place where the tweak's settings keys,
// feature toggles, view controllers, stores and hook installers are
// declared. Every .m file in the tweak imports it. All code is written
// from scratch; no Zero framework code, no activation code, no network.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ---------------------------------------------------------------------------
// Settings — toggles, persisted in NSUserDefaults under
// com.nebra.jodeltweak.*. Every toggle defaults to ON (a missing key
// reads as YES). The master switch gates everything: when it is OFF,
// the tweak does nothing at all.
// ---------------------------------------------------------------------------
BOOL JodelTweakIsEnabled(void);
BOOL JodelTweakNotesEnabled(void);
BOOL JodelTweakBanDetectionEnabled(void);
BOOL JodelTweakHidingEnabled(void);
BOOL JodelTweakBookmarksEnabled(void);
BOOL JodelTweakDraftsEnabled(void);
BOOL JodelTweakQuickRepliesEnabled(void);

void JodelTweakSetEnabled(BOOL enabled);
void JodelTweakSetNotesEnabled(BOOL enabled);
void JodelTweakSetBanDetectionEnabled(BOOL enabled);
void JodelTweakSetHidingEnabled(BOOL enabled);
void JodelTweakSetBookmarksEnabled(BOOL enabled);
void JodelTweakSetDraftsEnabled(BOOL enabled);
void JodelTweakSetQuickRepliesEnabled(BOOL enabled);

// Shared swizzle helper (implemented in JodelTweakSettings.m).
// Exchanges the implementations of two instance methods on a class.
// If the class does not implement the original itself, our method is
// added first so the exchange only affects this class.
BOOL JodelTweakSwizzleMethod(Class cls, SEL originalSel, SEL swizzledSel);

// Find the first UITextView (or UITextField) in a view hierarchy.
// Returns nil if none is found. Used to read/write Jodel's compose
// and reply fields without knowing Jodel's property names.
UITextView *JodelTweakFindTextViewInView(UIView *view);
UITextField *JodelTweakFindTextFieldInView(UIView *view);

// ---------------------------------------------------------------------------
// View controllers (implemented in their own .m files).
// ---------------------------------------------------------------------------
@interface JodelTweakSettingsViewController : UITableViewController
@end

@interface JodelTweakBookmarksViewController : UITableViewController
@end

@interface JodelTweakDraftsViewController : UITableViewController
@end

@interface JodelTweakQuickRepliesViewController : UITableViewController
@end

// ---------------------------------------------------------------------------
// Stores.
// ---------------------------------------------------------------------------
@interface JodelTweakBookmarksStore : NSObject
+ (NSArray<NSDictionary *> *)allBookmarks;
+ (void)addBookmarkWithText:(NSString *)text channel:(NSString *)channel;
+ (void)deleteBookmarkWithId:(NSString *)bookmarkId;
+ (NSUInteger)bookmarkCount;
@end

@interface JodelTweakDraftsStore : NSObject
+ (NSArray<NSDictionary *> *)allDrafts;
+ (void)addDraftWithText:(NSString *)text;
+ (void)deleteDraftWithId:(NSString *)draftId;
+ (NSUInteger)draftCount;
@end

@interface JodelTweakQuickRepliesStore : NSObject
+ (NSArray<NSString *> *)allReplies;
+ (void)addReply:(NSString *)text;
+ (void)updateReplyAtIndex:(NSUInteger)index withText:(NSString *)text;
+ (void)deleteReplyAtIndex:(NSUInteger)index;
+ (NSUInteger)replyCount;
@end

// ---------------------------------------------------------------------------
// Hook installers (each feature file installs its own hooks; the
// constructor in JodelTweak.m calls all of them).
// ---------------------------------------------------------------------------
void JodelTweakInstallBookmarksHooks(void);
void JodelTweakInstallDraftsHooks(void);
void JodelTweakInstallQuickRepliesHooks(void);

// Hiding hooks (JodelTweakHiding.m): setIsBanned: forced to NO and
// TweakInject returning "clean". Installed at load time; respects the
// master toggle and the hiding toggle (both default ON).
void JodelTweakInstallHiding(void);

// Opens Jodel's compose screen with the given text pre-filled. If the
// compose screen cannot be opened or the text cannot be inserted, the
// text is copied to the clipboard and a message is shown instead.
// (Implemented in JodelTweakDrafts.m.)
void JodelTweakOpenComposeWithText(NSString *text, UIViewController *fromVC);
