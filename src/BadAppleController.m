#import "BadAppleController.h"
#import "BadAppleCanvasView.h"
#import "BadApplePrivate.h"

#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <os/log.h>
#import <rootless.h>
#import <zlib.h>

static os_log_t BadAppleLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("com.yyyywaiwai.badapplesb", "BadApple");
    });
    return log;
}

typedef struct __attribute__((packed)) {
    char magic[4];
    uint16_t width;
    uint16_t height;
    uint16_t fpsNum;
    uint16_t fpsDen;
    uint32_t frameCount;
    uint32_t rawSize;
} BadAppleHeader;

@interface BadAppleController () <UIGestureRecognizerDelegate, AVAudioPlayerDelegate>

@property (nonatomic, readwrite, getter=isPlaying) BOOL playing;
@property (nonatomic, weak) SBIconController *iconController;
@property (nonatomic, weak) UIView *gestureHostView;
@property (nonatomic, strong) UILongPressGestureRecognizer *triggerGesture;
@property (nonatomic, strong) BadAppleCanvasView *canvasView;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;

@property (nonatomic, copy) NSString *savedAudioCategory;
@property (nonatomic, copy) NSString *savedAudioMode;
@property (nonatomic, assign) AVAudioSessionCategoryOptions savedAudioOptions;
@property (nonatomic, assign) BOOL hasSavedAudioSession;

@end

@implementation BadAppleController {
    uint8_t *_frameBuffer;
    uint16_t _frameWidth;
    uint16_t _frameHeight;
    uint32_t _frameCount;
    double _fps;
    NSInteger _lastRenderedFrame;
}

+ (instancetype)sharedController {
    static BadAppleController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)dealloc {
    [self freeFrameBuffer];
}

- (void)freeFrameBuffer {
    if (_frameBuffer) {
        free(_frameBuffer);
        _frameBuffer = NULL;
    }
    _frameWidth = 0;
    _frameHeight = 0;
    _frameCount = 0;
    _lastRenderedFrame = -1;
}

- (void)attachTriggerGestureToIconController:(SBIconController *)iconController {
    if (!iconController) {
        return;
    }
    self.iconController = iconController;
    [self ensureTriggerGestureAttached];
}

- (void)ensureTriggerGestureAttached {
    SBIconController *iconController = self.iconController;
    if (!iconController || ![iconController respondsToSelector:@selector(homeScreenViewController)]) {
        return;
    }
    SBHomeScreenViewController *homeVC = iconController.homeScreenViewController;
    UIView *homeView = homeVC.view;
    if (!homeView) {
        return;
    }

    if (self.triggerGesture && self.gestureHostView == homeView &&
        [homeView.gestureRecognizers containsObject:self.triggerGesture]) {
        return;
    }

    if (self.triggerGesture && self.triggerGesture.view) {
        [self.triggerGesture.view removeGestureRecognizer:self.triggerGesture];
    }

    UILongPressGestureRecognizer *lp =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                      action:@selector(handleTriggerLongPress:)];
    lp.minimumPressDuration = 10.0;
    lp.allowableMovement = 30.0;
    lp.cancelsTouchesInView = NO;
    lp.delaysTouchesBegan = NO;
    lp.delaysTouchesEnded = NO;
    lp.delegate = self;

    [homeView addGestureRecognizer:lp];
    self.triggerGesture = lp;
    self.gestureHostView = homeView;

    os_log(BadAppleLog(), "Attached 10s non-icon trigger gesture to %{public}@", homeView);
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)isRejectedTouchView:(UIView *)leafView stopAtView:(UIView *)stopView {
    Class iconViewClass = NSClassFromString(@"SBIconView");
    Class searchAffordanceClass = NSClassFromString(@"SBHSearchAffordance");
    Class searchPillClass = NSClassFromString(@"SBHSearchPillView");
    for (UIView *v = leafView; v && v != stopView; v = v.superview) {
        if ([v isKindOfClass:[UIControl class]] ||
            (iconViewClass && [v isKindOfClass:iconViewClass]) ||
            (searchAffordanceClass && [v isKindOfClass:searchAffordanceClass]) ||
            (searchPillClass && [v isKindOfClass:searchPillClass])) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer != self.triggerGesture) {
        return YES;
    }
    if (self.isPlaying) {
        return NO;
    }

    SBIconController *iconController = self.iconController;
    if (!iconController) {
        return NO;
    }
    SBHIconManager *iconManager = iconController.iconManager;
    SBHomeScreenViewController *homeVC = iconController.homeScreenViewController;
    if (!iconManager || !homeVC || !homeVC.view) {
        return NO;
    }

    if ([homeVC isIconContentHidden] ||
        [iconManager hasOpenFolder] ||
        [iconManager isOverlayTodayOrLibraryViewVisible] ||
        [iconManager isMainDisplayLibraryViewVisible] ||
        [iconManager isFolderPageManagementUIVisible] ||
        [iconManager isShowingIconContextMenu] ||
        [iconManager isIconDragging]) {
        return NO;
    }

    CGPoint ptInHome = [touch locationInView:homeVC.view];
    if (ptInHome.y < homeVC.view.safeAreaInsets.top) {
        return NO;
    }

    // Reject if touch hits any displayed icon/widget/folder view.
    __block BOOL touchesIcon = NO;
    [iconManager enumerateDisplayedIconViewsUsingBlock:^(SBIconView *iconView, BOOL *stop) {
        if (!iconView.window || iconView.hidden || iconView.alpha <= 0.01) {
            return;
        }
        CGPoint pt = [touch locationInView:iconView];
        if (CGRectContainsPoint(iconView.bounds, pt)) {
            touchesIcon = YES;
            if (stop) {
                *stop = YES;
            }
        }
    }];
    if (touchesIcon) {
        return NO;
    }

    // Also reject controls (Search pill, PageControl, Edit Done/+ buttons) or SBIconView ancestors.
    UIView *hitView = [homeVC.view hitTest:ptInHome withEvent:nil];
    if ([self isRejectedTouchView:hitView stopAtView:homeVC.view] ||
        [self isRejectedTouchView:touch.view stopAtView:homeVC.view]) {
        return NO;
    }

    os_log(BadAppleLog(),
           "Accepted touch at (%.1f, %.1f) on view %{public}@",
           ptInHome.x,
           ptInHome.y,
           NSStringFromClass([hitView class]));
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (gestureRecognizer == self.triggerGesture) {
        return YES;
    }
    return NO;
}

- (void)handleTriggerLongPress:(UILongPressGestureRecognizer *)recognizer {
    os_log(BadAppleLog(), "Trigger gesture state=%ld", (long)recognizer.state);
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        [self startPlayback];
    }
}

#pragma mark - Asset & Icon Loading

- (NSString *)assetPathForFilename:(NSString *)filename {
    NSString *rel = [@"/Library/Application Support/BadAppleSB/" stringByAppendingString:filename];
    NSString *resolved = ROOT_PATH_NS(rel);
    if ([[NSFileManager defaultManager] fileExistsAtPath:resolved]) {
        return resolved;
    }
    NSString *fallback = [@"/var/jb" stringByAppendingString:rel];
    if ([[NSFileManager defaultManager] fileExistsAtPath:fallback]) {
        return fallback;
    }
    return resolved;
}

- (BOOL)loadFrameData {
    [self freeFrameBuffer];

    NSString *binPath = [self assetPathForFilename:@"badapple.bin"];
    NSData *fileData = [NSData dataWithContentsOfFile:binPath options:NSDataReadingMappedIfSafe error:nil];
    if (fileData.length < sizeof(BadAppleHeader)) {
        os_log_error(BadAppleLog(), "Missing or invalid badapple.bin at %{public}@", binPath);
        return NO;
    }

    BadAppleHeader header;
    [fileData getBytes:&header length:sizeof(BadAppleHeader)];
    if (memcmp(header.magic, "BA01", 4) != 0 ||
        header.width == 0 ||
        header.height == 0 ||
        header.fpsDen == 0 ||
        header.frameCount == 0) {
        os_log_error(BadAppleLog(), "Invalid badapple.bin header");
        return NO;
    }

    uLongf destLen = (uLongf)header.rawSize;
    uint8_t *rawBuf = (uint8_t *)malloc(destLen);
    if (!rawBuf) {
        return NO;
    }

    const Bytef *srcPtr = (const Bytef *)fileData.bytes + sizeof(BadAppleHeader);
    uLong srcLen = (uLong)(fileData.length - sizeof(BadAppleHeader));
    int zres = uncompress(rawBuf, &destLen, srcPtr, srcLen);
    if (zres != Z_OK || destLen < (uLongf)header.frameCount * header.width * header.height) {
        os_log_error(BadAppleLog(), "zlib uncompress failed: %d", zres);
        free(rawBuf);
        return NO;
    }

    _frameBuffer = rawBuf;
    _frameWidth = header.width;
    _frameHeight = header.height;
    _frameCount = header.frameCount;
    _fps = (double)header.fpsNum / (double)header.fpsDen;
    _lastRenderedFrame = -1;

    os_log(BadAppleLog(),
           "Loaded %u frames (%ux%u @ %.2ffps)",
           _frameCount,
           _frameWidth,
           _frameHeight,
           _fps);
    return YES;
}

- (UIImage *)downscaledSquareImage:(UIImage *)source sidePixels:(CGFloat)sidePx {
    if (!source) {
        return nil;
    }
    CGFloat scale = [UIScreen mainScreen].scale;
    CGFloat sidePt = sidePx / scale;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = scale;
    fmt.opaque = NO;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(sidePt, sidePt) format:fmt];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [source drawInRect:CGRectMake(0, 0, sidePt, sidePt)];
    }];
}

- (NSArray<UIImage *> *)collectAppIconImages {
    SBIconController *iconController = self.iconController;
    SBHIconManager *iconManager = iconController.iconManager;
    SBHIconModel *iconModel = iconManager.iconModel;
    SBHIconImageCache *imageCache = iconManager.iconImageCache;
    SBRootFolder *rootFolder = iconManager.rootFolder;

    NSMutableArray<SBIcon *> *candidateIcons = [NSMutableArray array];
    NSMutableSet<NSString *> *seenIDs = [NSMutableSet set];

    void (^addIconIfEligible)(SBIcon *) = ^(SBIcon *icon) {
        if (!icon || ![icon isApplicationIcon]) {
            return;
        }
        NSString *key = [icon applicationBundleID] ?: [icon nodeIdentifier];
        if (!key.length || [seenIDs containsObject:key]) {
            return;
        }
        if (iconModel && [iconModel respondsToSelector:@selector(isIconVisible:)] && ![iconModel isIconVisible:icon]) {
            return;
        }
        [seenIDs addObject:key];
        [candidateIcons addObject:icon];
    };

    if (rootFolder) {
        for (SBIcon *icon in [rootFolder allIcons]) {
            addIconIfEligible(icon);
        }
    }
    if (iconModel) {
        for (SBIcon *icon in [iconModel leafIcons]) {
            addIconIfEligible(icon);
        }
    }

    struct SBIconImageInfo imageInfo = {CGSizeMake(60, 60), [UIScreen mainScreen].scale, 13.5};
    if (imageCache) {
        imageInfo = imageCache.iconImageInfo;
    }

    NSMutableArray<UIImage *> *images = [NSMutableArray arrayWithCapacity:candidateIcons.count];
    for (SBIcon *icon in candidateIcons) {
        UIImage *rawImg = nil;
        if (imageCache) {
            rawImg = [imageCache realImageForIcon:icon options:0];
        }
        if (!rawImg && [icon respondsToSelector:@selector(generateIconImageWithInfo:)]) {
            rawImg = [icon generateIconImageWithInfo:imageInfo];
        }
        if (!rawImg && imageCache) {
            rawImg = [imageCache imageForIcon:icon];
        }
        if (rawImg) {
            UIImage *compact = [self downscaledSquareImage:rawImg sidePixels:48.0];
            if (compact) {
                [images addObject:compact];
            }
        }
    }

    os_log(BadAppleLog(), "Collected %lu unique app icon images", (unsigned long)images.count);
    return images;
}

#pragma mark - Playback Lifecycle

- (void)startPlayback {
    if (self.isPlaying) {
        return;
    }

    SBIconController *iconController = self.iconController;
    SBHIconManager *iconManager = iconController.iconManager;
    SBHomeScreenViewController *homeVC = iconController.homeScreenViewController;
    if (!iconManager || !homeVC || !homeVC.view) {
        return;
    }

    if (![self loadFrameData]) {
        return;
    }

    NSArray<UIImage *> *iconImages = [self collectAppIconImages];
    if (iconImages.count == 0) {
        os_log_error(BadAppleLog(), "No app icon images collected; aborting playback");
        [self freeFrameBuffer];
        return;
    }

    NSString *audioPath = [self assetPathForFilename:@"badapple.m4a"];
    NSURL *audioURL = [NSURL fileURLWithPath:audioPath];
    NSError *audioErr = nil;
    AVAudioPlayer *player = [[AVAudioPlayer alloc] initWithContentsOfURL:audioURL error:&audioErr];
    if (!player || audioErr) {
        os_log_error(BadAppleLog(), "Failed to init AVAudioPlayer for %{public}@: %{public}@", audioPath, audioErr);
        [self freeFrameBuffer];
        return;
    }

    AVAudioSession *session = [AVAudioSession sharedInstance];
    self.savedAudioCategory = session.category;
    self.savedAudioMode = session.mode;
    self.savedAudioOptions = session.categoryOptions;
    self.hasSavedAudioSession = YES;

    NSError *sessionErr = nil;
    [session setCategory:AVAudioSessionCategoryPlayback
                    mode:AVAudioSessionModeDefault
                 options:0
                   error:&sessionErr];
    if (sessionErr) {
        os_log_error(BadAppleLog(), "AVAudioSession setCategory error: %{public}@", sessionErr);
    }
    NSError *activeErr = nil;
    [session setActive:YES error:&activeErr];
    if (activeErr) {
        os_log_error(BadAppleLog(), "AVAudioSession setActive error: %{public}@", activeErr);
    }
    os_log(BadAppleLog(), "Audio session active, outputVolume=%.2f", session.outputVolume);

    // Exit jiggle mode if the 10s hold triggered SpringBoard editing at ~0.5s.
    if ([iconManager isEditing]) {
        [iconManager setEditing:NO withFeedbackBehavior:nil];
    }

    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [haptic impactOccurred];

    self.playing = YES;
    self.audioPlayer = player;
    player.delegate = self;
    [player prepareToPlay];

    BadAppleCanvasView *canvas = [[BadAppleCanvasView alloc] initWithFrame:homeVC.view.bounds
                                                                   columns:_frameWidth
                                                                      rows:_frameHeight
                                                                iconImages:iconImages];
    canvas.alpha = 0.0;
    UITapGestureRecognizer *exitTap =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleExitDoubleTap:)];
    exitTap.numberOfTapsRequired = 2;
    [canvas addGestureRecognizer:exitTap];

    UIView *iconContentView = homeVC.iconContentView;
    [homeVC.view addSubview:canvas];
    self.canvasView = canvas;

    if (iconContentView) {
        iconContentView.userInteractionEnabled = NO;
    }

    [UIView animateWithDuration:0.28 animations:^{
        canvas.alpha = 1.0;
        if (iconContentView) {
            iconContentView.alpha = 0.0;
        }
    } completion:^(BOOL finished) {
        [canvas showExitHintBriefly];
    }];

    BOOL playOK = [player play];
    os_log(BadAppleLog(), "Bad Apple playback started (playOK=%d, duration=%.2fs)", playOK, player.duration);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.isPlaying && self.audioPlayer) {
            os_log(BadAppleLog(),
                   "Audio status check: playing=%d currentTime=%.2f volume=%.2f",
                   self.audioPlayer.isPlaying,
                   self.audioPlayer.currentTime,
                   self.audioPlayer.volume);
        }
    });

    CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(onDisplayLink:)];
    [link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.displayLink = link;
}

- (void)handleExitDoubleTap:(UITapGestureRecognizer *)tap {
    if (tap.state == UIGestureRecognizerStateRecognized) {
        os_log(BadAppleLog(), "Double-tap exit triggered");
        [self stopPlaybackAnimated:YES];
    }
}

- (void)onDisplayLink:(CADisplayLink *)link {
    if (!self.isPlaying || !_frameBuffer || !self.audioPlayer) {
        return;
    }

    NSTimeInterval t = self.audioPlayer.currentTime;
    NSInteger frameIdx = (NSInteger)floor(t * _fps);
    if (frameIdx < 0) {
        frameIdx = 0;
    }
    if ((uint32_t)frameIdx >= _frameCount) {
        if (!self.audioPlayer.isPlaying) {
            [self stopPlaybackAnimated:YES];
        }
        return;
    }

    if (frameIdx != _lastRenderedFrame) {
        _lastRenderedFrame = frameIdx;
        NSUInteger frameBytes = (NSUInteger)_frameWidth * (NSUInteger)_frameHeight;
        const uint8_t *ptr = _frameBuffer + ((NSUInteger)frameIdx * frameBytes);
        [self.canvasView renderFrameBytes:ptr];
    }
}

- (void)stopPlaybackAnimated:(BOOL)animated {
    if (!self.isPlaying) {
        return;
    }
    self.playing = NO;

    [self.displayLink invalidate];
    self.displayLink = nil;

    if (self.audioPlayer) {
        [self.audioPlayer stop];
        self.audioPlayer.delegate = nil;
        self.audioPlayer = nil;
    }

    if (self.hasSavedAudioSession) {
        AVAudioSession *session = [AVAudioSession sharedInstance];
        [session setActive:NO
               withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                     error:nil];
        if (self.savedAudioCategory) {
            [session setCategory:self.savedAudioCategory
                            mode:self.savedAudioMode ?: AVAudioSessionModeDefault
                         options:self.savedAudioOptions
                           error:nil];
        }
        self.hasSavedAudioSession = NO;
    }

    [self freeFrameBuffer];

    UIView *iconContentView = self.iconController.homeScreenViewController.iconContentView;
    BadAppleCanvasView *canvas = self.canvasView;
    self.canvasView = nil;

    if (iconContentView) {
        iconContentView.userInteractionEnabled = YES;
    }

    if (animated && canvas) {
        [UIView animateWithDuration:0.3 animations:^{
            canvas.alpha = 0.0;
            if (iconContentView) {
                iconContentView.alpha = 1.0;
            }
        } completion:^(BOOL finished) {
            [canvas removeFromSuperview];
        }];
    } else {
        if (iconContentView) {
            iconContentView.alpha = 1.0;
        }
        [canvas removeFromSuperview];
    }

    os_log(BadAppleLog(), "Bad Apple playback stopped");
}

#pragma mark - AVAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    os_log(BadAppleLog(), "Audio finished (success=%d)", flag);
    [self stopPlaybackAnimated:YES];
}

@end
