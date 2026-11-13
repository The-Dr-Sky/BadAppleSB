#import "BadAppleController.h"
#import "BadApplePrivate.h"

%hook SBIconController

- (void)_configureEditingGestureRecognizers {
    %orig;
    [[BadAppleController sharedController] attachTriggerGestureToIconController:self];
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

%hook SBHomeScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [[BadAppleController sharedController] attachTriggerGestureToIconController:self.iconController];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [[BadAppleController sharedController] stopPlaybackAnimated:NO];
}

%end
