#import "TouchBarBridge.h"
#import <objc/message.h>
#import <dlfcn.h>

// Runtime-checked private APIs, cross-checked with Toxblh/MTMR.
// No SIP changes, accessibility injection, or system patching.
static void *dfr;
static void (*presence)(NSString *, BOOL);
BOOL HDInstallTray(NSCustomTouchBarItem *item) {
    if (!dfr) dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY);
    if (!dfr) return NO;
    presence = dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier");
    SEL add = NSSelectorFromString(@"addSystemTrayItem:");
    SEL show = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    if (!presence || ![NSTouchBarItem respondsToSelector:add] || ![NSTouchBar respondsToSelector:show]) return NO;
    ((void (*)(id,SEL,id))objc_msgSend)(NSTouchBarItem.class, add, item);
    presence(item.identifier, YES);
    return YES;
}
BOOL HDKeepTrayVisible(NSCustomTouchBarItem *item) {
    if (!presence) return NO;
    presence(item.identifier, YES);
    return YES;
}
BOOL HDShowBar(NSTouchBar *bar, NSString *identifier) {
    SEL selector = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    if (![NSTouchBar respondsToSelector:selector]) return NO;
    ((void (*)(id,SEL,id,id))objc_msgSend)(NSTouchBar.class, selector, bar, identifier);
    if (presence) presence(identifier, YES);
    return YES;
}
void HDHideBar(NSTouchBar *bar) {
    SEL selector = NSSelectorFromString(@"minimizeSystemModalTouchBar:");
    if ([NSTouchBar respondsToSelector:selector]) ((void (*)(id,SEL,id))objc_msgSend)(NSTouchBar.class,selector,bar);
}
void HDRemoveTray(NSCustomTouchBarItem *item) {
    if (presence) presence(item.identifier,NO);
    SEL selector = NSSelectorFromString(@"removeSystemTrayItem:");
    if ([NSTouchBarItem respondsToSelector:selector]) ((void (*)(id,SEL,id))objc_msgSend)(NSTouchBarItem.class,selector,item);
}
