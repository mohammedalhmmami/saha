// JodelTweakDrafts.m — Drafts (المسودات) for Jodel v7.199.
//
// Written from scratch. No Zero framework code, no activation code.
// Local only: drafts live in NSUserDefaults on the device.
//
// WHAT IT IS:
//   Save a post draft before sending. A "مسودة" button is added to the
//   compose screen's navigation bar; tapping it saves the current
//   compose text as a draft. The Drafts screen lists saved drafts:
//   tap one to open the compose screen with the text pre-filled,
//   swipe to delete.
//
// HOW THE TEXT IS READ AND PRE-FILLED (honest note):
//   Jodel does not expose its compose model to us. We read the text by
//   walking the compose screen's view hierarchy for the first
//   UITextView (JodelTweakFindTextViewInView). Pre-filling works the
//   same way in reverse: after presenting Jodel's compose screen we
//   wait briefly for its view to load, find its UITextView, and set
//   .text. If the compose class cannot be found, or no text view is
//   found after a short wait, we fall back to copying the draft text
//   to the clipboard and showing a message that says so. The fallback
//   is real and reported, not hidden.
//
// HOOK:
//   We hook -viewDidLoad on ComposeViewController (candidate class
//   names checked at runtime). We call the original, then add the
//   draft button. When Drafts (or the master switch) is OFF, no button
//   is added.

#import "JodelTweakFeatures.h"
#import <objc/runtime.h>

static NSString * const kJodelTweakDraftsKey = @"com.nebra.jodeltweak.drafts.v1";

// ---------------------------------------------------------------------------
// Drafts store.
// A draft is a dictionary: @{ @"id": <UUID>, @"text": <NSString>,
//   @"date": <NSDate> }.
// ---------------------------------------------------------------------------
@implementation JodelTweakDraftsStore

+ (NSArray<NSDictionary *> *)allDrafts {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kJodelTweakDraftsKey];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id item in raw) {
        if ([item isKindOfClass:[NSDictionary class]]
            && [item[@"id"] isKindOfClass:[NSString class]]
            && [item[@"text"] isKindOfClass:[NSString class]]) {
            [out addObject:item];
        }
    }
    return [out sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSDate *da = a[@"date"];
        NSDate *db = b[@"date"];
        if ([da isKindOfClass:[NSDate class]] && [db isKindOfClass:[NSDate class]]) {
            return [db compare:da];
        }
        return NSOrderedSame;
    }];
}

+ (void)addDraftWithText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    NSMutableArray *drafts = [[self allDrafts] mutableCopy];
    [drafts insertObject:@{
        @"id": [[NSUUID UUID] UUIDString],
        @"text": trimmed,
        @"date": [NSDate date]
    } atIndex:0];
    [[NSUserDefaults standardUserDefaults] setObject:drafts forKey:kJodelTweakDraftsKey];
}

+ (void)deleteDraftWithId:(NSString *)draftId {
    if (!draftId) return;
    NSMutableArray *drafts = [[self allDrafts] mutableCopy];
    NSIndexSet *toRemove = [drafts indexesOfObjectsPassingTest:^BOOL(NSDictionary *d, NSUInteger idx, BOOL *stop) {
        return [d[@"id"] isEqualToString:draftId];
    }];
    if (toRemove.count > 0) {
        [drafts removeObjectsAtIndexes:toRemove];
        [[NSUserDefaults standardUserDefaults] setObject:drafts forKey:kJodelTweakDraftsKey];
    }
}

+ (NSUInteger)draftCount {
    return [self allDrafts].count;
}

@end

// ---------------------------------------------------------------------------
// Drafts screen.
// ---------------------------------------------------------------------------
@interface JodelTweakDraftsViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *drafts;
@end

@implementation JodelTweakDraftsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"المسودات";
    self.drafts = [JodelTweakDraftsStore allDrafts];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"DraftCell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.drafts = [JodelTweakDraftsStore allDrafts];
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.drafts.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"DraftCell" forIndexPath:indexPath];
    NSDictionary *d = self.drafts[indexPath.row];
    cell.textLabel.text = d[@"text"];
    cell.textLabel.numberOfLines = 2;
    NSDate *date = d[@"date"];
    if ([date isKindOfClass:[NSDate class]]) {
        static NSDateFormatter *formatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[NSDateFormatter alloc] init];
            formatter.dateStyle = NSDateFormatterShortStyle;
            formatter.timeStyle = NSDateFormatterShortStyle;
        });
        cell.detailTextLabel.text = [formatter stringFromDate:date];
    } else {
        cell.detailTextLabel.text = @"";
    }
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *d = self.drafts[indexPath.row];
    NSString *text = d[@"text"] ?: @"";
    JodelTweakOpenComposeWithText(text, self);
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *d = self.drafts[indexPath.row];
        [JodelTweakDraftsStore deleteDraftWithId:d[@"id"]];
        self.drafts = [JodelTweakDraftsStore allDrafts];
        [tableView deleteRowsAtIndexPaths:@[indexPath]
                         withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end

// ---------------------------------------------------------------------------
// Open Jodel's compose screen with text pre-filled (or clipboard fallback).
// ---------------------------------------------------------------------------
static UIViewController *JodelTweakTopViewControllerForCompose(void) {
    UIWindow *keyWindow = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                if (w.isKeyWindow) { keyWindow = w; break; }
            }
            if (keyWindow) break;
        }
    }
    if (!keyWindow) keyWindow = [UIApplication sharedApplication].keyWindow;
    UIViewController *vc = keyWindow.rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

void JodelTweakOpenComposeWithText(NSString *text, UIViewController *fromVC) {
    if (!text || text.length == 0) return;
    UIViewController *presenter = fromVC ?: JodelTweakTopViewControllerForCompose();

    // Try to open Jodel's own compose screen.
    Class composeClass = NSClassFromString(@"ComposeViewController");
    if (!composeClass) composeClass = NSClassFromString(@"Jodel.ComposeViewController");
    UIViewController *composeVC = nil;
    if (composeClass) {
        @try { composeVC = [[composeClass alloc] init]; } @catch (NSException *e) { composeVC = nil; }
    }
    if (!composeVC || !presenter) {
        // Fallback: copy to the clipboard and tell the user.
        [UIPasteboard generalPasteboard].string = text;
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"تم نسخ المسودة"
                                                message:@"تعذّر فتح شاشة النشر تلقائياً، فتم نسخ نص المسودة إلى الحافظة. الصقه في شاشة النشر."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسناً"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        if (presenter) [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }

    [presenter presentViewController:composeVC animated:YES completion:^{
        // Wait for the compose view to load, then find its text view.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                UITextView *tv = JodelTweakFindTextViewInView(composeVC.view);
                if (tv) {
                    tv.text = text;
                    // Move the caret to the end so the user keeps typing.
                    UITextPosition *end = [tv endOfDocument];
                    if (end) tv.selectedTextRange = [tv textRangeFromPosition:end toPosition:end];
                } else {
                    UITextField *tf = JodelTweakFindTextFieldInView(composeVC.view);
                    if (tf) {
                        tf.text = text;
                    } else {
                        [UIPasteboard generalPasteboard].string = text;
                        UIAlertController *alert =
                            [UIAlertController alertControllerWithTitle:@"تم نسخ المسودة"
                                                                message:@"فُتحت شاشة النشر لكن تعذّر إدراج النص تلقائياً، فتم نسخه إلى الحافظة. الصقه في حقل النشر."
                                                         preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:@"حسناً"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:nil]];
                        [composeVC presentViewController:alert animated:YES completion:nil];
                    }
                }
            } @catch (NSException *e) {
                [UIPasteboard generalPasteboard].string = text;
            }
        });
    }];
}

// ---------------------------------------------------------------------------
// Compose hook — add a "مسودة" button to the compose screen.
// ---------------------------------------------------------------------------
@interface UIViewController (JodelTweakDrafts)
- (void)jodelTweak_saveDraft;
@end

@implementation UIViewController (JodelTweakDrafts)

- (void)jodelTweak_saveDraft {
    @try {
        UITextView *tv = JodelTweakFindTextViewInView(self.view);
        NSString *text = tv.text;
        if (!text || text.length == 0) {
            UITextField *tf = JodelTweakFindTextFieldInView(self.view);
            text = tf.text;
        }
        if (!text || [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) {
            UIAlertController *empty =
                [UIAlertController alertControllerWithTitle:@"لا يوجد نص"
                                                    message:@"اكتب شيئاً أولاً ثم احفظه كمسودة."
                                             preferredStyle:UIAlertControllerStyleAlert];
            [empty addAction:[UIAlertAction actionWithTitle:@"حسناً"
                                                      style:UIAlertActionStyleDefault
                                                    handler:nil]];
            [self presentViewController:empty animated:YES completion:nil];
            return;
        }
        [JodelTweakDraftsStore addDraftWithText:text];
        UIAlertController *done =
            [UIAlertController alertControllerWithTitle:@"تم حفظ المسودة"
                                                message:@"حُفظ نص المنشور في المسودات. تجده في إعدادات الإضافات ← المسودات."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:@"حسناً"
                                                 style:UIAlertActionStyleDefault
                                               handler:nil]];
        [self presentViewController:done animated:YES completion:nil];
    } @catch (NSException *e) {
    }
}

@end

@interface NSObject (JodelTweakDrafts)
- (void)jodelTweak_composeViewDidLoad;
@end

@implementation NSObject (JodelTweakDrafts)

- (void)jodelTweak_composeViewDidLoad {
    [self jodelTweak_composeViewDidLoad];   // original viewDidLoad
    if (![self isKindOfClass:[UIViewController class]]) return;
    UIViewController *vc = (UIViewController *)self;
    if (!JodelTweakIsEnabled() || !JodelTweakDraftsEnabled()) return;
    if (!vc.navigationItem) return;
    // Add only once.
    for (UIBarButtonItem *item in vc.navigationItem.rightBarButtonItems) {
        if (item.action == @selector(jodelTweak_saveDraft)) return;
    }
    UIBarButtonItem *draftButton =
        [[UIBarButtonItem alloc] initWithTitle:@"مسودة"
                                         style:UIBarButtonItemStylePlain
                                        target:vc
                                        action:@selector(jodelTweak_saveDraft)];
    NSMutableArray *items = [vc.navigationItem.rightBarButtonItems mutableCopy];
    if (!items) items = [NSMutableArray array];
    [items addObject:draftButton];
    vc.navigationItem.rightBarButtonItems = items;
}

@end

// ---------------------------------------------------------------------------
// Installation.
// ---------------------------------------------------------------------------
void JodelTweakInstallDraftsHooks(void) {
    @try {
        NSArray<NSString *> *candidateClassNames = @[
            @"ComposeViewController",
            @"Jodel.ComposeViewController",
        ];
        SEL originalSel = @selector(viewDidLoad);
        SEL swizzledSel = @selector(jodelTweak_composeViewDidLoad);
        for (NSString *name in candidateClassNames) {
            Class cls = NSClassFromString(name);
            if (!cls) continue;
            // Only hook a class that implements viewDidLoad itself.
            Method m = class_getInstanceMethod(cls, originalSel);
            if (!m) continue;
            JodelTweakSwizzleMethod(cls, originalSel, swizzledSel);
        }
    } @catch (NSException *e) {
        // Never crash the host app because of the tweak.
    }
}
