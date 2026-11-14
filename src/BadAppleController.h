#import <UIKit/UIKit.h>

@class SBHIconManager;
@class SBHomeScreenViewController;

@interface BadAppleController : NSObject

@property (nonatomic, readonly, getter=isPlaying) BOOL playing;

+ (instancetype)sharedController;

- (void)attachTriggerGestureToHomeScreenViewController:(SBHomeScreenViewController *)homeVC
                                             controller:(id)controller;
- (void)attachTriggerGestureFromController:(id)controller;
- (void)ensureTriggerGestureAttached;
- (void)stopPlaybackAnimated:(BOOL)animated;

@end
