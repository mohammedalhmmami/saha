// JodelTweakBookmarks.m — Bookmarks (المفضلة) for Jodel v7.199.
//
// Written from scratch. No Zero framework code, no activation code.
// Local only: saved posts live in NSUserDefaults on the device.
//
// WHAT IT IS:
//   The user can save a post to a local bookmarks list from the post's
//   context menu (long-press a post → "حفظ في المفضلة"). The saved
//   bookmark holds the post text, the channel (best effort) and the
//   save time. The Bookmarks screen lists them: tap to read the full
//   text, swipe to delete.
//
// HOW THE POST TEXT IS READ (honest note):
//   Jodel does not expose its post model to us. We read the text from
//   the post cell's own labels: we walk the cell's view hierarchy,
//   collect every UILabel's text, and take the LONGEST text as the
//   post body (the post body is the longest text in a feed cell).
//   The channel is the shortest non-empty label that is not the body.
//   This is a heuristic — the saved text is what the cell actually
//   shows, which is the post as the user sees it. If a cell has no
//   readable labels, nothing is saved and the menu item is not added.
//
// HOOK:
//   We hook -tableView:contextMenuConfigurationForRowAtIndexPath:point:
//   (a UITableViewDelegate method that exists in Jodel's binary) on
//   whichever of the candidate delegate classes actually implements it
//   (checked at runtime). We call the original, then wrap its
//   UIContextMenuConfiguration with one extra action. Nothing about
//   Jodel's own menu is changed or removed. When Bookmarks (or the
//   master switch) is OFF, the hook is a no-op and Jodel's menu is
//   returned untouched.

#import "JodelTweakFeatures.h"
#import <objc/runtime.h>

static NSString * const kJodelTweakBookmarksKey = @"com.nebra.jodeltweak.bookmarks.v1";

// ---------------------------------------------------------------------------
// Bookmarks store.
// A bookmark is a dictionary: @{ @"id": <UUID>, @"text": <NSString>,
//   @"channel": <NSString>, @"date": <NSDate> }.
// ---------------------------------------------------------------------------
@implementation JodelTweakBookmarksStore

+ (NSArray<NSDictionary *> *)allBookmarks {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kJodelTweakBookmarksKey];
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

+ (void)addBookmarkWithText:(NSString *)text channel:(NSString *)channel {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    NSMutableArray *items = [[self allBookmarks] mutableCopy];
    // Avoid an exact duplicate of the same text saved twice in a row.
    for (NSDictionary *b in items) {
        if ([b[@"text"] isEqualToString:trimmed]) return;
    }
    [items insertObject:@{
        @"id": [[NSUUID UUID] UUIDString],
        @"text": trimmed,
        @"channel": channel ?: @"",
        @"date": [NSDate date]
    } atIndex:0];
    [[NSUserDefaults standardUserDefaults] setObject:items forKey:kJodelTweakBookmarksKey];
}

+ (void)deleteBookmarkWithId:(NSString *)bookmarkId {
    if (!bookmarkId) return;
    NSMutableArray *items = [[self allBookmarks] mutableCopy];
    NSIndexSet *toRemove = [items indexesOfObjectsPassingTest:^BOOL(NSDictionary *b, NSUInteger idx, BOOL *stop) {
        return [b[@"id"] isEqualToString:bookmarkId];
    }];
    if (toRemove.count > 0) {
        [items removeObjectsAtIndexes:toRemove];
        [[NSUserDefaults standardUserDefaults] setObject:items forKey:kJodelTweakBookmarksKey];
    }
}

+ (NSUInteger)bookmarkCount {
    return [self allBookmarks].count;
}

@end

// ---------------------------------------------------------------------------
// Bookmarks screen.
// ---------------------------------------------------------------------------
@interface JodelTweakBookmarksViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *bookmarks;
@end

@implementation JodelTweakBookmarksViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"المفضلة";
    self.bookmarks = [JodelTweakBookmarksStore allBookmarks];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"BookmarkCell"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.bookmarks = [JodelTweakBookmarksStore allBookmarks];
    [self.tableView reloadData];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.bookmarks.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"BookmarkCell" forIndexPath:indexPath];
    NSDictionary *b = self.bookmarks[indexPath.row];
    cell.textLabel.text = b[@"text"];
    cell.textLabel.numberOfLines = 2;
    NSString *channel = b[@"channel"];
    NSDate *date = b[@"date"];
    NSString *detail = @"";
    if ([date isKindOfClass:[NSDate class]]) {
        static NSDateFormatter *formatter = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            formatter = [[NSDateFormatter alloc] init];
            formatter.dateStyle = NSDateFormatterShortStyle;
            formatter.timeStyle = NSDateFormatterShortStyle;
        });
        detail = [formatter stringFromDate:date];
    }
    if ([channel isKindOfClass:[NSString class]] && channel.length > 0) {
        detail = [NSString stringWithFormat:@"%@ • %@", channel, detail];
    }
    cell.detailTextLabel.text = detail;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *b = self.bookmarks[indexPath.row];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:b[@"channel"] ?: @"منشور محفوظ"
                                            message:b[@"text"]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"إغلاق"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *b = self.bookmarks[indexPath.row];
        [JodelTweakBookmarksStore deleteBookmarkWithId:b[@"id"]];
        self.bookmarks = [JodelTweakBookmarksStore allBookmarks];
        [tableView deleteRowsAtIndexPaths:@[indexPath]
                         withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end

// ---------------------------------------------------------------------------
// Reading a post's text from its cell.
// Walk the cell's view hierarchy, collect every UILabel's text. The
// longest text is the post body; the shortest non-empty text that is
// not the body is the best channel guess. Returns nil if no text.
// ---------------------------------------------------------------------------
static void JodelTweakCollectLabelTexts(UIView *view, NSMutableArray<NSString *> *out) {
    if (!view) return;
    if ([view isKindOfClass:[UILabel class]]) {
        NSString *text = ((UILabel *)view).text;
        if (text.length > 0) [out addObject:text];
    }
    for (UIView *sub in view.subviews) {
        JodelTweakCollectLabelTexts(sub, out);
    }
}

static NSDictionary *JodelTweakPostDataFromCell(UITableViewCell *cell) {
    if (!cell) return nil;
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    JodelTweakCollectLabelTexts(cell.contentView, texts);
    if (texts.count == 0) return nil;
    NSString *body = texts[0];
    for (NSString *t in texts) {
        if (t.length > body.length) body = t;
    }
    NSString *channel = @"";
    for (NSString *t in texts) {
        if (![t isEqualToString:body] && t.length > 0 && t.length < 30) {
            if (channel.length == 0 || t.length < channel.length) channel = t;
        }
    }
    return @{ @"text": body, @"channel": channel };
}

// ---------------------------------------------------------------------------
// Context-menu hook.
// ---------------------------------------------------------------------------
@interface NSObject (JodelTweakBookmarks)
- (UIContextMenuConfiguration *)jodelTweak_tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                        point:(CGPoint)point;
@end

@implementation NSObject (JodelTweakBookmarks)

- (UIContextMenuConfiguration *)jodelTweak_tableView:(UITableView *)tableView
    contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
                                        point:(CGPoint)point {
    // Call the original (swapped in by the exchange) — Jodel's own menu.
    UIContextMenuConfiguration *original =
        [self jodelTweak_tableView:tableView
            contextMenuConfigurationForRowAtIndexPath:indexPath
                                                point:point];
    // Feature off → return Jodel's menu untouched.
    if (!JodelTweakIsEnabled() || !JodelTweakBookmarksEnabled()) return original;

    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    NSDictionary *post = JodelTweakPostDataFromCell(cell);
    if (!post) return original;   // nothing readable to save
    NSString *postText = post[@"text"];
    NSString *channelText = post[@"channel"];

    // Wrap the original configuration, appending our save action.
    // The original menu's children are kept exactly as Jodel built them.
    UIContextMenuConfiguration *wrapped =
        [UIContextMenuConfiguration configurationWithIdentifier:original.identifier
                                                previewProvider:original.previewProvider
                                                  actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
            UIMenu *originalMenu = nil;
            if (original.actionProvider) {
                @try { originalMenu = original.actionProvider(suggestedActions); } @catch (NSException *e) {}
            }
            UIAction *saveAction =
                [UIAction actionWithTitle:@"حفظ في المفضلة"
                                    image:[UIImage systemImageNamed:@"bookmark"]
                               identifier:nil
                                  handler:^(__kindof UIAction * _Nonnull action) {
                    [JodelTweakBookmarksStore addBookmarkWithText:postText channel:channelText];
                }];
            NSMutableArray<UIMenuElement *> *children = [NSMutableArray array];
            if (originalMenu) [children addObjectsFromArray:originalMenu.children];
            [children addObject:saveAction];
            return [UIMenu menuWithTitle:@"" children:children];
        }];
    return wrapped;
}

@end

// ---------------------------------------------------------------------------
// Installation. Hook the delegate method on whichever candidate class
// actually implements it (checked at runtime). The feed's table delegate
// is most likely the feed view controller or its table source object.
// ---------------------------------------------------------------------------
void JodelTweakInstallBookmarksHooks(void) {
    @try {
        NSArray<NSString *> *candidateClassNames = @[
            @"Jodel.MainFeedViewController",
            @"MainFeedViewController",
            @"Jodel.JDLFeedTableViewSource",
            @"JDLFeedTableViewSource",
        ];
        SEL originalSel = @selector(tableView:contextMenuConfigurationForRowAtIndexPath:point:);
        SEL swizzledSel = @selector(jodelTweak_tableView:contextMenuConfigurationForRowAtIndexPath:point:);
        for (NSString *name in candidateClassNames) {
            Class cls = NSClassFromString(name);
            if (!cls) continue;
            // Only hook a class that implements the method itself.
            Method m = class_getInstanceMethod(cls, originalSel);
            if (!m) continue;
            JodelTweakSwizzleMethod(cls, originalSel, swizzledSel);
        }
    } @catch (NSException *e) {
        // Never crash the host app because of the tweak.
    }
}
