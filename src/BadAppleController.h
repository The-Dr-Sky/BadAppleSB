#import <UIKit/UIKit.h>

@class SBIconController;

@interface BadAppleController : NSObject

@property (nonatomic, readonly, getter=isPlaying) BOOL playing;

+ (instancetype)sharedController;

- (void)attachTriggerGestureToIconController:(SBIconController *)iconController;
- (void)ensureTriggerGestureAttached;
- (void)stopPlaybackAnimated:(BOOL)animated;

@end
