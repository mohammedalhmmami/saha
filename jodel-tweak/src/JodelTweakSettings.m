// JodelTweakSettings.m — feature toggles + the Tweak Settings screen.
//
// Written from scratch. No Zero framework code, no activation code.
//
// WHAT THIS IS:
//   1. The toggle accessors. Every feature in the tweak has an on/off
//      switch, persisted in NSUserDefaults under com.nebra.jodeltweak.*.
//      Every toggle defaults to ON (a missing key reads as YES).
//      The master switch (com.nebra.jodeltweak.enabled) gates everything:
//      when it is OFF, the tweak does nothing at all.
//   2. The Tweak Settings screen (JodelTweakSettingsViewController):
//      a table with one switch per feature, plus rows that open the
//      Bookmarks, Drafts and Quick Replies screens. It is reached from
//      the gear button in the Private Notes screen.
//   3. The Quick Replies editor (JodelTweakQuickRepliesViewController):
//      add / edit / delete the user's short reply templates.
//   4. Shared helpers: JodelTweakSwizzleMethod and the view-hierarchy
//      text-field finders used by the Drafts and Quick Replies hooks.

#import "JodelTweakFeatures.h"
#import <objc/runtime.h>

// ---------------------------------------------------------------------------
// Settings keys (our own namespace — never touches Jodel's keys).
// ---------------------------------------------------------------------------
static NSString * const kJodelTweakEnabledKey = @"com.nebra.jodeltweak.enabled";
static NSString * const kJodelTweakNotesEnabledKey = @"com.nebra.jodeltweak.notesEnabled";
static NSString * const kJodelTweakBanDetectionEnabledKey = @"com.nebra.jodeltweak.banDetectionEnabled";
static NSString * const kJodelTweakBookmarksEnabledKey = @"com.nebra.jodeltweak.bookmarksEnabled";
static NSString * const kJodelTweakDraftsEnabledKey = @"com.nebra.jodeltweak.draftsEnabled";
static NSString * const kJodelTweakQuickRepliesEnabledKey = @"com.nebra.jodeltweak.quickRepliesEnabled";

// A missing key reads as YES (every feature defaults to ON).
static BOOL JodelTweakBoolForKey(NSString *key) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if ([d objectForKey:key] == nil) return YES;
    return [d boolForKey:key];
}

BOOL JodelTweakIsEnabled(void) { return JodelTweakBoolForKey(kJodelTweakEnabledKey); }
BOOL JodelTweakNotesEnabled(void) { return JodelTweakBoolForKey(kJodelTweakNotesEnabledKey); }
BOOL JodelTweakBanDetectionEnabled(void) { return JodelTweakBoolForKey(kJodelTweakBanDetectionEnabledKey); }
BOOL JodelTweakBookmarksEnabled(void) { return JodelTweakBoolForKey(kJodelTweakBookmarksEnabledKey); }
BOOL JodelTweakDraftsEnabled(void) { return JodelTweakBoolForKey(kJodelTweakDraftsEnabledKey); }
BOOL JodelTweakQuickRepliesEnabled(void) { return JodelTweakBoolForKey(kJodelTweakQuickRepliesEnabledKey); }

void JodelTweakSetEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kJodelTweakEnabledKey];
}
void JodelTweakSetNotesEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kJodelTweakNotesEnabledKey];
}
void JodelTweakSetBanDetectionEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kJodelTweakBanDetectionEnabledKey];
}
void JodelTweakSetBookmarksEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kJodelTweakBookmarksEnabledKey];
}
void JodelTweakSetDraftsEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kJodelTweakDraftsEnabledKey];
}
void JodelTweakSetQuickRepliesEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kJodelTweakQuickRepliesEnabledKey];
}

// ---------------------------------------------------------------------------
// Shared swizzle helper.
// ---------------------------------------------------------------------------
BOOL JodelTweakSwizzleMethod(Class cls, SEL originalSel, SEL swizzledSel) {
    Method originalMethod = class_getInstanceMethod(cls, originalSel);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzledSel);
    if (!originalMethod || !swizzledMethod) return NO;
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

// ---------------------------------------------------------------------------
// View-hierarchy text-field finders.
// Recursively search a view's subviews for the first UITextView (or
// UITextField). Used to read/write Jodel's compose and reply fields
// without knowing Jodel's property names. Returns nil if none is found.
// ---------------------------------------------------------------------------
UITextView *JodelTweakFindTextViewInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITextView class]]) return (UITextView *)view;
    for (UIView *sub in view.subviews) {
        UITextView *found = JodelTweakFindTextViewInView(sub);
        if (found) return found;
    }
    return nil;
}

UITextField *JodelTweakFindTextFieldInView(UIView *view) {
    if (!view) return nil;
    if ([view isKindOfClass:[UITextField class]]) return (UITextField *)view;
    for (UIView *sub in view.subviews) {
        UITextField *found = JodelTweakFindTextFieldInView(sub);
        if (found) return found;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// Tweak Settings screen.
// ---------------------------------------------------------------------------
@implementation JodelTweakSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"إعدادات الإضافات";
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ToggleCell"];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ManageCell"];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(doneTapped)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)doneTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 6;   // the six toggles
    return 3;                     // Bookmarks / Drafts / Quick Replies
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"الإضافات — تفعيل / إيقاف";
    return @"إدارة";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"إيقاف «تفعيل الإضافات» يوقف كل شيء: لا زر ملاحظات، لا كشف حظر، لا تنبيه حظر.";
    return @"المفضلة والمسودات والردود السريعة محفوظة على جهازك فقط.";
}

// Toggle rows: tag 0 = master, 1 = notes, 2 = ban detection,
// 3 = bookmarks, 4 = drafts, 5 = quick replies.
- (UITableViewCell *)toggleCellForRow:(NSInteger)row {
    UITableViewCell *cell =
        [self.tableView dequeueReusableCellWithIdentifier:@"ToggleCell"];
    BOOL masterOn = JodelTweakIsEnabled();
    UISwitch *sw = [[UISwitch alloc] init];
    sw.tag = row;
    [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    switch (row) {
        case 0:
            cell.textLabel.text = @"تفعيل الإضافات";
            cell.detailTextLabel.text = @"المفتاح الرئيسي — إيقافه يوقف كل شيء";
            sw.on = masterOn;
            break;
        case 1:
            cell.textLabel.text = @"ملاحظاتي الخاصة";
            cell.detailTextLabel.text = @"دفتر ملاحظات شخصي داخل التطبيق";
            sw.on = JodelTweakNotesEnabled();
            sw.enabled = masterOn;
            break;
        case 2:
            cell.textLabel.text = @"كشف الحظر";
            cell.detailTextLabel.text = @"تنبيه عند الحظر + زر إنشاء حساب جديد";
            sw.on = JodelTweakBanDetectionEnabled();
            sw.enabled = masterOn;
            break;
        case 3:
            cell.textLabel.text = @"المفضلة";
            cell.detailTextLabel.text = @"حفظ المنشورات في قائمة محلية";
            sw.on = JodelTweakBookmarksEnabled();
            sw.enabled = masterOn;
            break;
        case 4:
            cell.textLabel.text = @"المسودات";
            cell.detailTextLabel.text = @"حفظ نص المنشور قبل إرساله";
            sw.on = JodelTweakDraftsEnabled();
            sw.enabled = masterOn;
            break;
        case 5:
            cell.textLabel.text = @"ردود سريعة";
            cell.detailTextLabel.text = @"قوالب ردود جاهزة تظهر عند الرد";
            sw.on = JodelTweakQuickRepliesEnabled();
            sw.enabled = masterOn;
            break;
        default:
            break;
    }
    cell.accessoryView = sw;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (void)switchChanged:(UISwitch *)sender {
    switch (sender.tag) {
        case 0:
            JodelTweakSetEnabled(sender.isOn);
            // Toggling the master switch re-greys the other switches.
            [self.tableView reloadData];
            break;
        case 1: JodelTweakSetNotesEnabled(sender.isOn); break;
        case 2: JodelTweakSetBanDetectionEnabled(sender.isOn); break;
        case 3: JodelTweakSetBookmarksEnabled(sender.isOn); break;
        case 4: JodelTweakSetDraftsEnabled(sender.isOn); break;
        case 5: JodelTweakSetQuickRepliesEnabled(sender.isOn); break;
        default: break;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        return [self toggleCellForRow:indexPath.row];
    }
    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"ManageCell" forIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.row == 0) {
        cell.textLabel.text = @"المفضلة";
        cell.detailTextLabel.text =
            [NSString stringWithFormat:@"%lu منشور محفوظ", (unsigned long)[JodelTweakBookmarksStore bookmarkCount]];
    } else if (indexPath.row == 1) {
        cell.textLabel.text = @"المسودات";
        cell.detailTextLabel.text =
            [NSString stringWithFormat:@"%lu مسودة", (unsigned long)[JodelTweakDraftsStore draftCount]];
    } else {
        cell.textLabel.text = @"ردود سريعة";
        cell.detailTextLabel.text =
            [NSString stringWithFormat:@"%lu قالب", (unsigned long)[JodelTweakQuickRepliesStore replyCount]];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    UIViewController *vc = nil;
    if (indexPath.row == 0) {
        vc = [[JodelTweakBookmarksViewController alloc] initWithStyle:UITableViewStylePlain];
    } else if (indexPath.row == 1) {
        vc = [[JodelTweakDraftsViewController alloc] initWithStyle:UITableViewStylePlain];
    } else {
        vc = [[JodelTweakQuickRepliesViewController alloc] initWithStyle:UITableViewStylePlain];
    }
    if (vc) [self.navigationController pushViewController:vc animated:YES];
}

@end

// ---------------------------------------------------------------------------
// Quick Replies editor — add / edit / delete reply templates.
// ---------------------------------------------------------------------------
@interface JodelTweakQuickRepliesViewController ()
@property (nonatomic, strong) NSArray<NSString *> *replies;
@end

@implementation JodelTweakQuickRepliesViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"ردود سريعة";
    self.replies = [JodelTweakQuickRepliesStore allReplies];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ReplyCell"];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                      target:self
                                                      action:@selector(addReplyTapped)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.replies = [JodelTweakQuickRepliesStore allReplies];
    [self.tableView reloadData];
}

- (void)addReplyTapped {
    [self editReplyAtIndex:NSNotFound withText:@""];
}

- (void)editReplyAtIndex:(NSUInteger)index withText:(NSString *)existingText {
    BOOL isNew = (index == NSNotFound);
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:isNew ? @"رد سريع جديد" : @"تعديل الرد السريع"
                                            message:@"اكتب نص الرد الجاهز. سيظهر كزر عند الرد على منشور."
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"مثال: شكراً لك!";
        textField.text = existingText;
    }];
    __weak typeof(self) weakSelf = self;
    UIAlertAction *save =
        [UIAlertAction actionWithTitle:@"حفظ" style:UIAlertActionStyleDefault
                               handler:^(UIAlertAction *action) {
            NSString *text = alert.textFields.firstObject.text;
            if (isNew) {
                [JodelTweakQuickRepliesStore addReply:text ?: @""];
            } else {
                [JodelTweakQuickRepliesStore updateReplyAtIndex:index withText:text ?: @""];
            }
            weakSelf.replies = [JodelTweakQuickRepliesStore allReplies];
            [weakSelf.tableView reloadData];
        }];
    [alert addAction:save];
    [alert addAction:[UIAlertAction actionWithTitle:@"إلغاء"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Table view

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.replies.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell =
        [tableView dequeueReusableCellWithIdentifier:@"ReplyCell" forIndexPath:indexPath];
    cell.textLabel.text = self.replies[indexPath.row];
    cell.textLabel.numberOfLines = 2;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self editReplyAtIndex:indexPath.row withText:self.replies[indexPath.row]];
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [JodelTweakQuickRepliesStore deleteReplyAtIndex:indexPath.row];
        self.replies = [JodelTweakQuickRepliesStore allReplies];
        [tableView deleteRowsAtIndexPaths:@[indexPath]
                         withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end
