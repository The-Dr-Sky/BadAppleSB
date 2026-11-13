#import <UIKit/UIKit.h>

@interface BadAppleCanvasView : UIView

- (instancetype)initWithFrame:(CGRect)frame
                      columns:(NSUInteger)columns
                         rows:(NSUInteger)rows
                   iconImages:(NSArray<UIImage *> *)iconImages;

- (void)renderFrameBytes:(const uint8_t *)bytes;
- (void)showExitHintBriefly;

@end
