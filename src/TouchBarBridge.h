#import <AppKit/AppKit.h>
BOOL HDInstallTray(NSCustomTouchBarItem *item);
BOOL HDShowBar(NSTouchBar *bar, NSString *identifier);
void HDHideBar(NSTouchBar *bar);
void HDRemoveTray(NSCustomTouchBarItem *item);
