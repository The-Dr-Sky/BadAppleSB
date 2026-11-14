#import "BadAppleController.h"
#import "BadApplePrivate.h"
#import <objc/runtime.h>

%group CommonHooks

%hook SBHomeScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[BadAppleController sharedController] attachTriggerGestureToHomeScreenViewController:self controller:nil];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [[BadAppleController sharedController] stopPlaybackAnimated:NO];
}

%end

%end

%group LegacyIconControllerHooks

%hook SBIconController

- (void)_configureEditingGestureRecognizers {
    %orig;
    [[BadAppleController sharedController] attachTriggerGestureFromController:self];
}

- (void)_lockScreenUIWillLock:(id)notification {
    %orig;
    [[BadAppleController sharedController] stopPlaybackAnimated:NO];
}

- (void)_coverSheetWillPresent:(id)notification {
    %orig;
    [[BadAppleController sharedController] stopPlaybackAnimated:NO];
}

%end

%end

%group ModernHomeScreenHooks

%hook SBHomeScreenController

- (void)_lockScreenUIWillLock:(id)notification {
    %orig;
    [[BadAppleController sharedController] stopPlaybackAnimated:NO];
}

- (void)_coverSheetWillPresent:(id)notification {
    %orig;
    [[BadAppleController sharedController] stopPlaybackAnimated:NO];
}

- (void)_coverSheetWillDismiss:(id)notification {
    %orig;
    [[BadAppleController sharedController] attachTriggerGestureFromController:self];
}

%end

%end

%ctor {
    %init(CommonHooks);

    if (objc_getClass("SBHomeScreenController")) {
        %init(ModernHomeScreenHooks);
    }

    Class iconControllerClass = objc_getClass("SBIconController");
    if (iconControllerClass &&
        [iconControllerClass instancesRespondToSelector:@selector(_configureEditingGestureRecognizers)]) {
        %init(LegacyIconControllerHooks);
    }
}
