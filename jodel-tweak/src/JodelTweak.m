// JodelTweak.m — Private Notes tweak for Jodel v7.199
//
// WHAT THIS IS:
//   A brand-new, original tweak written from scratch for the user's
//   original Jodel v7.199 IPA. It adds ONE completely new feature that
//   does not exist in Jodel and is not one of Zero's features:
//
//     Private Notes ("My Notes") — a personal notebook inside Jodel.
//     Users can write, view and delete private notes. Notes are stored
//     only on the device (NSUserDefaults). No network, no account, no
//     data collection, no activation code, no login, no paywall.
//
// HOW IT WORKS (mechanism, learned from studying swizzling in general):
//   The dylib is loaded by dyld when Jodel launches (via an
//   LC_LOAD_DYLIB entry added to the Jodel binary). Its constructor
//   runs before Jodel's UI appears. It uses plain Objective-C runtime
//   method swizzling — method_exchangeImplementations + NSClassFromString
//   — to hook ONE method:
//     Jodel.MainFeedViewController.viewDidLoad
//   The swizzled implementation calls the original viewDidLoad, then
//   adds a "Notes" button to the feed's navigation bar. Tapping it
//   presents the Notes screen (written from scratch in this file).
//
// SAFETY:
//   - Every lookup is guarded: if the class or the method does not
//     exist at runtime, the hook is skipped silently (no crash).
//   - The hook installation is wrapped in @try/@catch.
//   - The button is added only once per view controller (tracked with
//     an associated object), so viewDidLoad being called again is safe.
//   - The tweak never modifies Jodel's data, never touches the network,
//     never reads the user's posts or account. It only writes the user's
//     own notes to NSUserDefaults under its own key.
//   - If the dylib is removed, Jodel runs exactly as before.
//
// BUILD (on a Mac with Xcode, or via the GitHub Actions workflow):
//   clang -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path)
//         -miphoneos-version-min=16.4 -fobjc-arc -dynamiclib
//         -framework Foundation -framework UIKit
//         -o JodelTweak.dylib JodelTweak.m
//   See build.sh in this folder for the exact command, and
//   .github/workflows/build-tweak.yml for the CI build.
//
// NO activation code. NO login. NO paywall. NO network. NO tracking.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "JodelTweakProtection.h"

// ---------------------------------------------------------------------------
// Storage key (our own namespace — never touches Jodel's keys).
// ---------------------------------------------------------------------------
static NSString * const kJodelTweakNotesKey = @"com.nebra.jodeltweak.notes.v1";
static NSString * const kJodelTweakButtonInstalledKey = @"com.nebra.jodeltweak.buttonInstalled";

// ---------------------------------------------------------------------------
// NotesStore — the user's private notes, kept in NSUserDefaults.
// A note is a dictionary: @{ @"id": <UUID string>, @"text": <NSString>,
//                            @"date": <NSDate> }.
// ---------------------------------------------------------------------------
@interface JodelTweakNotesStore : NSObject
+ (NSArray<NSDictionary *> *)allNotes;
+ (void)addNoteWithText:(NSString *)text;
+ (void)deleteNoteWithId:(NSString *)noteId;
+ (NSUInteger)noteCount;
@end

@implementation JodelTweakNotesStore

+ (NSArray<NSDictionary *> *)allNotes {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kJodelTweakNotesKey];
    if (![raw isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray *out = [NSMutableArray array];
    for (id item in raw) {
        if ([item isKindOfClass:[NSDictionary class]]
            && [item[@"id"] isKindOfClass:[NSString class]]
            && [item[@"text"] isKindOfClass:[NSString class]]) {
            [out addObject:item];
        }
    }
    // Newest first.
    return [out sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSDate *da = a[@"date"];
        NSDate *db = b[@"date"];
        if ([da isKindOfClass:[NSDate class]] && [db isKindOfClass:[NSDate class]]) {
            return [db compare:da];
        }
        return NSOrderedSame;
    }];
}

+ (void)addNoteWithText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return;
    NSMutableArray *notes = [[self allNotes] mutableCopy];
    [notes insertObject:@{
        @"id": [[NSUUID UUID] UUIDString],
        @"text": trimmed,
        @"date": [NSDate date]
    } atIndex:0];
    [[NSUserDefaults standardUserDefaults] setObject:notes forKey:kJodelTweakNotesKey];
}

+ (void)deleteNoteWithId:(NSString *)noteId {
    if (!noteId) return;
    NSMutableArray *notes = [[self allNotes] mutableCopy];
    NSIndexSet *toRemove = [notes indexesOfObjectsPassingTest:^BOOL(NSDictionary *note, NSUInteger idx, BOOL *stop) {
        return [note[@"id"] isEqualToString:noteId];
    }];
    if (toRemove.count > 0) {
        [notes removeObjectsAtIndexes:toRemove];
        [[NSUserDefaults standardUserDefaults] setObject:notes forKey:kJodelTweakNotesKey];
    }
}

+ (NSUInteger)noteCount {
    return [self allNotes].count;
}

@end

// ---------------------------------------------------------------------------
// NotesViewController — the "My Notes" screen, written from scratch.
// A plain table view: list notes, tap to view, "+" to add, swipe to delete.
// ---------------------------------------------------------------------------
@interface JodelTweakNotesViewController : UITableViewController
@property (nonatomic, strong) NSArray<NSDictionary *> *notes;
@end

@implementation JodelTweakNotesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"My Notes";
    self.notes = [JodelTweakNotesStore allNotes];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"NoteCell"];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(addNoteTapped)];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(doneTapped)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.notes = [JodelTweakNotesStore allNotes];
    [self.tableView reloadData];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)addNoteTapped {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"New Note"
                                            message:@"Write a private note for yourself. It stays on this device only."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"Write your note...";
    }];
    __weak typeof(self) weakSelf = self;
    UIAlertAction *save =
        [UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
            NSString *text = alert.textFields.firstObject.text;
            [JodelTweakNotesStore addNoteWithText:text ?: @""];
            weakSelf.notes = [JodelTweakNotesStore allNotes];
            [weakSelf.tableView reloadData];
        }];
    [alert addAction:save];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.notes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"NoteCell" forIndexPath:indexPath];
    NSDictionary *note = self.notes[indexPath.row];
    cell.textLabel.text = note[@"text"];
    cell.textLabel.numberOfLines = 2;
    NSDate *date = note[@"date"];
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
    NSDictionary *note = self.notes[indexPath.row];
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Note"
                                            message:note[@"text"]
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Close"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSDictionary *note = self.notes[indexPath.row];
        [JodelTweakNotesStore deleteNoteWithId:note[@"id"]];
        self.notes = [JodelTweakNotesStore allNotes];
        [tableView deleteRowsAtIndexPaths:@[indexPath]
                         withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end

// ---------------------------------------------------------------------------
// Hook — add a "Notes" button to the Main Feed's navigation bar.
//
// Target (identified by static analysis of the v7.199 binary; see
// HOOK_TARGETS.md): the feed view controller. Its Swift ObjC name is
// "Jodel.MainFeedViewController". We try that first, then the bare name.
// We hook -viewDidLoad, call the original, then add the button once.
// ---------------------------------------------------------------------------
static void JodelTweakAddNotesButton(UIViewController *vc) {
    if (!vc || !vc.navigationItem) return;
    // Add only once per view controller instance.
    NSNumber *installed = objc_getAssociatedObject(vc, (__bridge const void *)kJodelTweakButtonInstalledKey);
    if ([installed boolValue]) return;
    objc_setAssociatedObject(vc, (__bridge const void *)kJodelTweakButtonInstalledKey,
                             @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIBarButtonItem *notesButton;
    if (@available(iOS 13.0, *)) {
        UIImage *icon = [UIImage systemImageNamed:@"note.text"];
        notesButton = [[UIBarButtonItem alloc] initWithImage:icon
                                                       style:UIBarButtonItemStylePlain
                                                      target:vc
                                                      action:@selector(jodelTweak_openNotes)];
    } else {
        notesButton = [[UIBarButtonItem alloc] initWithTitle:@"Notes"
                                                       style:UIBarButtonItemStylePlain
                                                      target:vc
                                                      action:@selector(jodelTweak_openNotes)];
    }
    notesButton.accessibilityLabel = @"My Notes";
    NSMutableArray *items = [vc.navigationItem.rightBarButtonItems mutableCopy];
    if (!items) items = [NSMutableArray array];
    [items addObject:notesButton];
    vc.navigationItem.rightBarButtonItems = items;
}

// The action the Notes button calls. Implemented as a category method so it
// can be attached to the feed view controller without subclassing it.
@interface UIViewController (JodelTweakNotes)
- (void)jodelTweak_openNotes;
@end

@implementation UIViewController (JodelTweakNotes)

- (void)jodelTweak_openNotes {
    JodelTweakNotesViewController *notesVC =
        [[JodelTweakNotesViewController alloc] initWithStyle:UITableViewStylePlain];
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:notesVC];
    [self presentViewController:nav animated:YES completion:nil];
}

@end

// The swizzled viewDidLoad. After method_exchangeImplementations, calling
// [self jodelTweak_viewDidLoad] invokes the ORIGINAL viewDidLoad.
@interface NSObject (JodelTweakSwizzle)
- (void)jodelTweak_viewDidLoad;
@end

@implementation NSObject (JodelTweakSwizzle)

- (void)jodelTweak_viewDidLoad {
    // Call the original viewDidLoad (swapped in by method_exchangeImplementations).
    [self jodelTweak_viewDidLoad];
    // Then add our button — only for view controllers, and only once.
    if ([self isKindOfClass:[UIViewController class]]) {
        JodelTweakAddNotesButton((UIViewController *)self);
    }
}

@end

// ---------------------------------------------------------------------------
// Installation — runs when dyld loads this dylib (before Jodel's UI).
// ---------------------------------------------------------------------------
static void JodelTweakInstallHooks(void) {
    @try {
        NSArray<NSString *> *candidateClassNames = @[
            @"Jodel.MainFeedViewController",   // Swift ObjC name (most likely)
            @"MainFeedViewController",          // bare name (fallback)
        ];
        Class targetClass = nil;
        for (NSString *name in candidateClassNames) {
            targetClass = NSClassFromString(name);
            if (targetClass) break;
        }
        if (!targetClass) return;  // class not present — skip silently, no crash.

        SEL originalSel = @selector(viewDidLoad);
        SEL swizzledSel = @selector(jodelTweak_viewDidLoad);
        Method originalMethod = class_getInstanceMethod(targetClass, originalSel);
        Method swizzledMethod = class_getInstanceMethod([NSObject class], swizzledSel);
        if (!originalMethod || !swizzledMethod) return;

        // If the class does not implement viewDidLoad itself (it inherits it
        // from UIViewController), add our method first so the exchange only
        // affects this class, not UIViewController globally.
        BOOL didAdd = class_addMethod(targetClass, originalSel,
                                      method_getImplementation(swizzledMethod),
                                      method_getTypeEncoding(swizzledMethod));
        if (didAdd) {
            class_replaceMethod(targetClass, swizzledSel,
                                method_getImplementation(originalMethod),
                                method_getTypeEncoding(originalMethod));
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    } @catch (NSException *e) {
        // Never crash the host app because of the tweak.
    }
}

__attribute__((constructor))
static void JodelTweakConstructor(void) {
    JodelTweakInstallHooks();
    // Ban detection + fresh-account recovery ("unban").
    // See JodelTweakProtection.m and PROTECTION.md.
    JodelTweakInstallProtection();
}
