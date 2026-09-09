#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ServiceManagement/ServiceManagement.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSMenuItem *statusLine;
@property NSMenuItem *toggleItem;
@property NSMenuItem *loginItem;
@property EventHotKeyRef hotkey;
@property EventHandlerRef handler;
- (void)openTerminal;
@end

static OSStatus hotkeyPressed(EventHandlerCallRef next, EventRef event, void *context) {
    EventHotKeyID identifier;
    OSStatus result = GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(identifier), NULL, &identifier);
    if (result == noErr && identifier.signature == 'TFST' && identifier.id == 1) {
        [(__bridge AppDelegate *)context openTerminal];
        return noErr;
    }
    return eventNotHandledErr;
}

@implementation AppDelegate
- (void)alert:(NSString *)title message:(NSString *)message {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = message;
    [alert runModal];
}
- (NSMenuItem *)item:(NSString *)title action:(SEL)action menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = self;
    [menu addItem:item];
    return item;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSArray *instances = [NSRunningApplication runningApplicationsWithBundleIdentifier:NSBundle.mainBundle.bundleIdentifier];
    if (instances.count > 1) { [NSApp terminate:nil]; return; }
    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"⌘1";
    self.statusItem.button.toolTip = @"Terminal First";
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    self.statusLine = [self item:@"Terminal First — starting…" action:NULL menu:menu];
    self.statusLine.enabled = NO;
    [menu addItem:NSMenuItem.separatorItem];
    [self item:@"Open Terminal" action:@selector(openTerminal) menu:menu];
    self.toggleItem = [self item:@"Enable ⌘1" action:@selector(toggleHotkey) menu:menu];
    self.loginItem = [self item:@"Start at Login" action:@selector(toggleLogin) menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    [self item:@"About Terminal First" action:@selector(showAbout) menu:menu];
    [self item:@"Quit Terminal First" action:@selector(quit) menu:menu];
    self.statusItem.menu = menu;
    [self refreshLogin];
    EventTypeSpec type = {kEventClassKeyboard, kEventHotKeyPressed};
    EventHandlerRef handler = NULL;
    OSStatus status = InstallApplicationEventHandler(hotkeyPressed, 1, &type, (__bridge void *)self, &handler);
    self.handler = handler;
    if (status != noErr) {
        self.statusLine.title = @"Terminal First — unavailable";
        self.toggleItem.enabled = NO;
        [self alert:@"Unable to listen for ⌘1" message:[NSString stringWithFormat:@"macOS returned error %d. Quit and reopen the app from Finder.", (int)status]];
        return;
    }
    if (![NSUserDefaults.standardUserDefaults boolForKey:@"Paused"]) [self enableHotkey];
    else self.statusLine.title = @"Terminal First — paused";
}
- (void)enableHotkey {
    EventHotKeyRef key = NULL;
    EventHotKeyID identifier = {'TFST', 1};
    OSStatus status = RegisterEventHotKey(kVK_ANSI_1, cmdKey, identifier, GetApplicationEventTarget(), kEventHotKeyExclusive, &key);
    if (status != noErr) {
        self.statusLine.title = @"Terminal First — shortcut unavailable";
        [self alert:@"Couldn’t reserve ⌘1" message:[NSString stringWithFormat:@"Another global shortcut utility may be using this key. Disable its ⌘1 binding, then choose Enable ⌘1 here. macOS error: %d.", (int)status]];
        return;
    }
    self.hotkey = key;
    self.statusLine.title = @"Terminal First — ⌘1 active";
    self.toggleItem.title = @"Pause ⌘1";
    self.statusItem.button.appearsDisabled = NO;
    [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"Paused"];
}
- (void)toggleHotkey {
    if (self.hotkey) {
        UnregisterEventHotKey(self.hotkey);
        self.hotkey = NULL;
        self.statusLine.title = @"Terminal First — paused";
        self.toggleItem.title = @"Enable ⌘1";
        self.statusItem.button.appearsDisabled = YES;
        [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"Paused"];
    } else [self enableHotkey];
}
- (void)openTerminal {
    NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.Terminal"];
    if (!url) { [self alert:@"Terminal not found" message:@"The Apple Terminal app could not be found on this Mac."]; return; }
    NSWorkspaceOpenConfiguration *config = NSWorkspaceOpenConfiguration.configuration;
    config.activates = YES;
    [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:config completionHandler:^(NSRunningApplication *app, NSError *error) {
        if (error) dispatch_async(dispatch_get_main_queue(), ^{
            [self alert:@"Couldn’t open Terminal" message:error.localizedDescription];
        });
    }];
}
- (void)refreshLogin {
    SMAppServiceStatus status = SMAppService.mainAppService.status;
    self.loginItem.state = status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginItem.title = status == SMAppServiceStatusRequiresApproval ? @"Approve Start at Login…" : @"Start at Login";
}
- (void)toggleLogin {
    SMAppService *service = SMAppService.mainAppService;
    if (service.status == SMAppServiceStatusRequiresApproval) {
        [SMAppService openSystemSettingsLoginItems];
        return;
    }
    NSError *error = nil;
    if (service.status == SMAppServiceStatusEnabled) [service unregisterAndReturnError:&error];
    else [service registerAndReturnError:&error];
    [self refreshLogin];
    if (error) [self alert:@"Login setting couldn’t be changed" message:[NSString stringWithFormat:@"%@\n\nMove Terminal First to Applications and try again. You can also add it in System Settings → General → Login Items.", error.localizedDescription]];
}
- (void)showAbout {
    [self refreshLogin];
    [self alert:@"Terminal First 1.0" message:@"Press ⌘1 to open or focus Apple Terminal.\n\nWhile active, this global shortcut takes priority over ordinary app shortcuts. Use Pause or Quit to restore their normal behavior.\n\nUses the physical 1 key on the main keyboard. No network access, keystroke recording, or Accessibility permission is needed.\n\nFor automatic startup, move the app to Applications and enable Start at Login."];
}
- (void)quit { [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    if (self.hotkey) UnregisterEventHotKey(self.hotkey);
    if (self.handler) RemoveEventHandler(self.handler);
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate *delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
