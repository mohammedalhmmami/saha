// JodelTweakQuickReplies.m — Quick Replies (ردود سريعة) for Jodel v7.199.
//
// Written from scratch. No Zero framework code, no activation code.
// Local only: reply templates live in NSUserDefaults on the device.
//
// WHAT IT IS:
//   User-defined reply templates. The user writes short replies in
//   the Quick Replies editor (reached from the Tweak Settings screen).
//   When replying to a post, the templates appear as tappable chips in
//   a horizontal bar at the bottom of the reply screen. Tapping a chip
//   inserts its text into the reply field.
//
// HOW INSERTION WORKS (honest note):
//   Jodel does not expose its reply field to us. We find the reply
//   field by walking the reply screen's view hierarchy for the first
//   UITextView (or UITextField) and append the template text to
//   whatever is already there. If no text field can be found, the chip
//   tap copies the template to the clipboard and shows a message that
//   says so. The clipboard fallback is real and reported, not hidden.
//
// HOOK:
//   We hook -viewDidLoad on JDLReplyViewController (candidate class
//   names checked at runtime). We call the original, then add the chip
//   bar (only if Quick Replies is ON and at least one template exists).
//   The bar is a plain UIScrollView at the bottom of the reply screen.
//   When Quick Replies (or the master switch) is OFF, no bar is added.

#import "JodelTweakFeatures.h"
#import <objc/runtime.h>

static NSString * const kJodelTweakQuickRepliesKey = @"com.nebra.jodeltweak.quickReplies.v1";

// ---------------------------------------------------------------------------
// Quick Replies store. A reply is a plain NSString.
// ---------------------------------------------------------------------------
@implementation JodelTweakQuickRepliesStore

+ (NSArray<NSString *> *)allReplies {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kJodelTweakQuickRepliesKey];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id item in raw) {
        if ([item isKindOfClass:[NSString class]] && ((NSString *)item).length > 0) {
            [out addObject:item];
        }
    }
    return out;
}

+ (void)addReply:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    NSMutableArray *replies = [[self allReplies] mutableCopy];
    [replies addObject:trimmed];
    [[NSUserDefaults standardUserDefaults] setObject:replies forKey:kJodelTweakQuickRepliesKey];
}

+ (void)updateReplyAtIndex:(NSUInteger)index withText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    NSMutableArray *replies = [[self allReplies] mutableCopy];
    if (index >= replies.count) return;
    replies[index] = trimmed;
    [[NSUserDefaults standardUserDefaults] setObject:replies forKey:kJodelTweakQuickRepliesKey];
}

+ (void)deleteReplyAtIndex:(NSUInteger)index {
    NSMutableArray *replies = [[self allReplies] mutableCopy];
    if (index >= replies.count) return;
    [replies removeObjectAtIndex:index];
    [[NSUserDefaults standardUserDefaults] setObject:replies forKey:kJodelTweakQuickRepliesKey];
}

+ (NSUInteger)replyCount {
    return [self allReplies].count;
}

@end

// ---------------------------------------------------------------------------
// Chip bar — a horizontal scroll view of tappable reply templates.
// ---------------------------------------------------------------------------
static NSString * const kJodelTweakChipBarKey = @"com.nebra.jodeltweak.chipBar";

@interface UIViewController (JodelTweakQuickReplies)
- (void)jodelTweak_quickReplyChipTapped:(UIButton *)sender;
@end

@implementation UIViewController (JodelTweakQuickReplies)

- (void)jodelTweak_quickReplyChipTapped:(UIButton *)sender {
    NSString *replyText = sender.titleLabel.text;
    if (!replyText || replyText.length == 0) return;
    @try {
        UITextView *tv = JodelTweakFindTextViewInView(self.view);
        if (tv) {
            NSString *existing = tv.text ?: @"";
            NSString *joined = existing.length > 0
                ? [existing stringByAppendingFormat:@" %@", replyText]
                : replyText;
            tv.text = joined;
            // Move the caret to the end.
            UITextPosition *end = [tv endOfDocument];
            if (end) tv.selectedTextRange = [tv textRangeFromPosition:end toPosition:end];
            [tv becomeFirstResponder];
            return;
        }
        UITextField *tf = JodelTweakFindTextFieldInView(self.view);
        if (tf) {
            NSString *existing = tf.text ?: @"";
            tf.text = existing.length > 0
                ? [existing stringByAppendingFormat:@" %@", replyText]
                : replyText;
            [tf becomeFirstResponder];
            return;
        }
        // No text field found — copy to the clipboard and say so.
        [UIPasteboard generalPasteboard].string = replyText;
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"تم نسخ الرد"
                                                message:@"تعذّر إدراج الرد تلقائياً، فتم نسخه إلى الحافظة. الصقه في حقل الرد."
                                         preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"حسناً"
                                                  style:UIAlertActionStyleDefault
                                                handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    } @catch (NSException *e) {
        [UIPasteboard generalPasteboard].string = replyText;
    }
}

@end

static void JodelTweakAddChipBar(UIViewController *vc) {
    if (!vc || !vc.view) return;
    // Add only once per view controller instance.
    if (objc_getAssociatedObject(vc, (__bridge const void *)kJodelTweakChipBarKey)) return;

    NSArray<NSString *> *replies = [JodelTweakQuickRepliesStore allReplies];
    if (replies.count == 0) return;

    CGFloat barHeight = 44.0;
    CGRect viewBounds = vc.view.bounds;
    UIScrollView *bar = [[UIScrollView alloc]
        initWithFrame:CGRectMake(0, viewBounds.size.height - barHeight,
                                 viewBounds.size.width, barHeight)];
    bar.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    bar.showsHorizontalScrollIndicator = NO;
    bar.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    if (@available(iOS 13.0, *)) {
        bar.backgroundColor = [UIColor secondarySystemBackgroundColor];
    }

    CGFloat x = 8.0;
    for (NSString *reply in replies) {
        UIButton *chip = [UIButton buttonWithType:UIButtonTypeSystem];
        [chip setTitle:reply forState:UIControlStateNormal];
        chip.titleLabel.font = [UIFont systemFontOfSize:14.0];
        chip.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [chip sizeToFit];
        CGFloat width = MIN(chip.frame.size.width + 24.0, 220.0);
        chip.frame = CGRectMake(x, 6.0, width, barHeight - 12.0);
        chip.layer.cornerRadius = (barHeight - 12.0) / 2.0;
        chip.layer.borderWidth = 1.0;
        chip.layer.borderColor = [UIColor lightGrayColor].CGColor;
        chip.backgroundColor = [UIColor whiteColor];
        if (@available(iOS 13.0, *)) {
            chip.backgroundColor = [UIColor systemBackgroundColor];
        }
        [chip addTarget:vc
                 action:@selector(jodelTweak_quickReplyChipTapped:)
       forControlEvents:UIControlEventTouchUpInside];
        [bar addSubview:chip];
        x += width + 8.0;
    }
    bar.contentSize = CGSizeMake(x, barHeight);
    [vc.view addSubview:bar];
    objc_setAssociatedObject(vc, (__bridge const void *)kJodelTweakChipBarKey,
                             bar, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// ---------------------------------------------------------------------------
// Reply hook — add the chip bar when the reply screen loads.
// ---------------------------------------------------------------------------
@interface NSObject (JodelTweakQuickReplies)
- (void)jodelTweak_replyViewDidLoad;
@end

@implementation NSObject (JodelTweakQuickReplies)

- (void)jodelTweak_replyViewDidLoad {
    [self jodelTweak_replyViewDidLoad];   // original viewDidLoad
    if (![self isKindOfClass:[UIViewController class]]) return;
    UIViewController *vc = (UIViewController *)self;
    if (!JodelTweakIsEnabled() || !JodelTweakQuickRepliesEnabled()) return;
    @try {
        JodelTweakAddChipBar(vc);
    } @catch (NSException *e) {
    }
}

@end

// ---------------------------------------------------------------------------
// Installation.
// ---------------------------------------------------------------------------
void JodelTweakInstallQuickRepliesHooks(void) {
    @try {
        NSArray<NSString *> *candidateClassNames = @[
            @"JDLReplyViewController",
            @"Jodel.JDLReplyViewController",
        ];
        SEL originalSel = @selector(viewDidLoad);
        SEL swizzledSel = @selector(jodelTweak_replyViewDidLoad);
        for (NSString *name in candidateClassNames) {
            Class cls = NSClassFromString(name);
            if (!cls) continue;
            Method m = class_getInstanceMethod(cls, originalSel);
            if (!m) continue;
            JodelTweakSwizzleMethod(cls, originalSel, swizzledSel);
        }
    } @catch (NSException *e) {
        // Never crash the host app because of the tweak.
    }
}
