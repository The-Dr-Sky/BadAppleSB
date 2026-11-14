#import <UIKit/UIKit.h>

struct SBIconImageInfo {
    CGSize size;
    CGFloat scale;
    CGFloat continuousCornerRadius;
};

@interface SBIcon : NSObject
- (BOOL)isApplicationIcon;
- (NSString *)applicationBundleID;
- (NSString *)nodeIdentifier;
- (UIImage *)generateIconImageWithInfo:(struct SBIconImageInfo)info;
- (UIImage *)iconImageWithInfo:(struct SBIconImageInfo)info;
@end

@interface SBIconView : UIView
@property (nonatomic, strong) SBIcon *icon;
@end

@interface SBHIconImageAppearance : NSObject
+ (instancetype)defaultAppearance;
@end

@interface SBHIconImageCache : NSObject
@property (nonatomic, readonly) struct SBIconImageInfo iconImageInfo;
- (UIImage *)realImageForIcon:(SBIcon *)icon options:(NSUInteger)options;
- (UIImage *)realImageForIcon:(SBIcon *)icon imageAppearance:(id)appearance options:(NSUInteger)options;
- (UIImage *)realImageForIcon:(SBIcon *)icon compatibleWithTraitCollection:(UITraitCollection *)traitCollection options:(NSUInteger)options;
- (UIImage *)imageForIcon:(SBIcon *)icon;
@end

@interface SBFolder : NSObject
- (id<NSFastEnumeration>)allIcons;
@end

@interface SBRootFolder : SBFolder
@end

@interface SBHIconModel : NSObject
- (NSSet<SBIcon *> *)leafIcons;
- (BOOL)isIconVisible:(SBIcon *)icon;
@end

@interface SBHIconManager : NSObject
@property (nonatomic, readonly) SBHIconModel *iconModel;
@property (nonatomic, readonly) SBHIconImageCache *iconImageCache;
@property (nonatomic, readonly) SBRootFolder *rootFolder;
@property (nonatomic, readonly, getter=isEditing) BOOL editing;
- (void)setEditing:(BOOL)editing withFeedbackBehavior:(id)behavior;
- (BOOL)hasOpenFolder;
- (BOOL)isOverlayTodayOrLibraryViewVisible;
- (BOOL)isMainDisplayLibraryViewVisible;
- (BOOL)isFolderPageManagementUIVisible;
- (BOOL)isShowingIconContextMenu;
- (BOOL)isIconDragging;
- (BOOL)isRootFolderContentVisible;
- (UIViewController *)floatingDockViewController;
- (void)enumerateDisplayedIconViewsUsingBlock:(void (^)(SBIconView *iconView, BOOL *stop))block;
@end

@class SBIconController;

@interface SBHomeScreenViewController : UIViewController
@property (nonatomic, readonly) SBIconController *iconController;
@property (nonatomic, readonly) SBHIconManager *iconManager;
@property (nonatomic, readonly) UIView *iconContentView;
@property (nonatomic, readonly, getter=isIconContentHidden) BOOL iconContentHidden;
@end

@interface SBHomeScreenController : NSObject
@property (nonatomic, readonly) SBHomeScreenViewController *homeScreenViewController;
@property (nonatomic, readonly) SBHIconManager *iconManager;
- (id)currentIconImageAppearance;
- (void)_lockScreenUIWillLock:(id)notification;
- (void)_coverSheetWillPresent:(id)notification;
- (void)_coverSheetWillDismiss:(id)notification;
@end

@interface SBIconController : NSObject
+ (instancetype)sharedInstanceIfExists;
+ (instancetype)sharedInstance;
@property (nonatomic, readonly) SBHIconManager *iconManager;
@property (nonatomic, readonly) SBHomeScreenViewController *homeScreenViewController;
- (void)_configureEditingGestureRecognizers;
- (void)_lockScreenUIWillLock:(id)notification;
- (void)_coverSheetWillPresent:(id)notification;
@end
