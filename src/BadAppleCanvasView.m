#import "BadAppleCanvasView.h"
#import <QuartzCore/QuartzCore.h>
#import <stdlib.h>

@implementation BadAppleCanvasView {
    NSUInteger _columns;
    NSUInteger _rows;
    NSUInteger _cellCount;
    UIView *_stageView;
    CALayer *_gridLayer;
    NSMutableArray<CALayer *> *_cellLayers;
    uint8_t *_prevFrame;
    uint8_t *_cellVisible;
    UILabel *_hintLabel;
}

- (instancetype)initWithFrame:(CGRect)frame
                      columns:(NSUInteger)columns
                         rows:(NSUInteger)rows
                   iconImages:(NSArray<UIImage *> *)iconImages {
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }

    _columns = columns;
    _rows = rows;
    _cellCount = columns * rows;
    _prevFrame = (uint8_t *)calloc(_cellCount, sizeof(uint8_t));
    _cellVisible = (uint8_t *)calloc(_cellCount, sizeof(uint8_t));
    _cellLayers = [NSMutableArray arrayWithCapacity:_cellCount];

    self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.62];
    self.clipsToBounds = YES;
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    _stageView = [[UIView alloc] initWithFrame:self.bounds];
    _stageView.userInteractionEnabled = NO;
    _stageView.clipsToBounds = YES;
    [self addSubview:_stageView];

    _gridLayer = [CALayer layer];
    [_stageView.layer addSublayer:_gridLayer];

    NSUInteger poolCount = iconImages.count;
    NSUInteger *assignedIndices = (NSUInteger *)malloc(sizeof(NSUInteger) * _cellCount);
    CGFloat screenScale = [UIScreen mainScreen].scale;

    for (NSUInteger r = 0; r < _rows; r++) {
        for (NSUInteger c = 0; c < _columns; c++) {
            NSUInteger idx = r * _columns + c;
            NSUInteger chosen = 0;
            if (poolCount > 0) {
                chosen = arc4random_uniform((uint32_t)poolCount);
                if (poolCount >= 4) {
                    NSUInteger leftIdx = (c > 0) ? assignedIndices[idx - 1] : NSNotFound;
                    NSUInteger topIdx = (r > 0) ? assignedIndices[idx - _columns] : NSNotFound;
                    for (int attempt = 0; attempt < 6 && (chosen == leftIdx || chosen == topIdx); attempt++) {
                        chosen = arc4random_uniform((uint32_t)poolCount);
                    }
                }
            }
            assignedIndices[idx] = chosen;

            CALayer *cell = [CALayer layer];
            if (poolCount > 0) {
                UIImage *img = iconImages[chosen];
                cell.contents = (__bridge id)img.CGImage;
                cell.contentsScale = screenScale;
            }
            cell.contentsGravity = kCAGravityResizeAspect;
            cell.minificationFilter = kCAFilterTrilinear;
            cell.opacity = 0.0f;
            [_gridLayer addSublayer:cell];
            [_cellLayers addObject:cell];
        }
    }
    free(assignedIndices);

    _hintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _hintLabel.text = @"ダブルタップで終了";
    _hintLabel.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
    _hintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.88];
    _hintLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    _hintLabel.textAlignment = NSTextAlignmentCenter;
    _hintLabel.layer.cornerRadius = 13.0;
    _hintLabel.layer.masksToBounds = YES;
    _hintLabel.alpha = 0.0;
    [_stageView addSubview:_hintLabel];

    return self;
}

- (void)dealloc {
    if (_prevFrame) {
        free(_prevFrame);
        _prevFrame = NULL;
    }
    if (_cellVisible) {
        free(_cellVisible);
        _cellVisible = NULL;
    }
}

- (void)safeAreaInsetsDidChange {
    [super safeAreaInsetsDidChange];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect hostBounds = self.bounds;
    if (hostBounds.size.width <= 0.0 || hostBounds.size.height <= 0.0 || _columns == 0 || _rows == 0) {
        return;
    }

    UIEdgeInsets hostSafe = self.safeAreaInsets;
    CGFloat screenScale = self.window.screen.scale > 0.0 ? self.window.screen.scale : [UIScreen mainScreen].scale;

    // Rotate 90deg clockwise (notch on left = LandscapeRight) when hosted on a portrait screen.
    BOOL rotateToLandscape = (hostBounds.size.height > hostBounds.size.width);
    CGFloat stageW = rotateToLandscape ? hostBounds.size.height : hostBounds.size.width;
    CGFloat stageH = rotateToLandscape ? hostBounds.size.width : hostBounds.size.height;

    CGFloat bottomSafe = rotateToLandscape ? hostSafe.left : hostSafe.bottom;

    CGAffineTransform targetTransform =
        rotateToLandscape ? CGAffineTransformMakeRotation(M_PI_2) : CGAffineTransformIdentity;
    CGSize targetSize = CGSizeMake(stageW, stageH);
    if (!CGSizeEqualToSize(_stageView.bounds.size, targetSize)) {
        _stageView.bounds = CGRectMake(0.0, 0.0, stageW, stageH);
    }
    CGPoint targetCenter = CGPointMake(CGRectGetMidX(hostBounds), CGRectGetMidY(hostBounds));
    if (!CGPointEqualToPoint(_stageView.center, targetCenter)) {
        _stageView.center = targetCenter;
    }
    if (!CGAffineTransformEqualToTransform(_stageView.transform, targetTransform)) {
        _stageView.transform = targetTransform;
    }

    // Aspect Fill across the full landscape display bounds (sacrificing top/bottom clipping).
    CGFloat aspect = (CGFloat)_columns / (CGFloat)_rows;
    CGFloat gridW = stageW;
    CGFloat gridH = gridW / aspect;
    if (gridH < stageH) {
        gridH = stageH;
        gridW = gridH * aspect;
    }

    // Snap cell pitch up to clean screen pixels so all four display edges are covered.
    CGFloat cellPitch = ceil((gridW / (CGFloat)_columns) * screenScale) / screenScale;
    gridW = cellPitch * (CGFloat)_columns;
    gridH = cellPitch * (CGFloat)_rows;

    CGFloat originX = floor(((stageW - gridW) * 0.5) * screenScale) / screenScale;
    CGFloat originY = floor(((stageH - gridH) * 0.5) * screenScale) / screenScale;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _gridLayer.frame = CGRectMake(originX, originY, gridW, gridH);

    CGFloat gap = MAX(0.5, floor(cellPitch * 0.08 * screenScale) / screenScale);
    CGFloat iconSide = cellPitch - gap;
    CGFloat inset = gap * 0.5;
    CGRect visibleRect = CGRectMake(0.0, 0.0, stageW, stageH);

    for (NSUInteger r = 0; r < _rows; r++) {
        for (NSUInteger c = 0; c < _columns; c++) {
            NSUInteger idx = r * _columns + c;
            CALayer *cell = _cellLayers[idx];
            CGRect cellLocalFrame = CGRectMake(c * cellPitch + inset, r * cellPitch + inset, iconSide, iconSide);
            CGRect cellInStage = CGRectOffset(cellLocalFrame, originX, originY);
            BOOL visible = CGRectIntersectsRect(visibleRect, cellInStage);
            if (_cellVisible) {
                _cellVisible[idx] = visible ? 1 : 0;
            }
            cell.hidden = !visible;
            cell.frame = cellLocalFrame;
        }
    }
    [CATransaction commit];

    CGFloat hintW = 148.0;
    CGFloat hintH = 26.0;
    _hintLabel.frame = CGRectMake((stageW - hintW) * 0.5,
                                  stageH - MAX(bottomSafe, 10.0) - hintH - 4.0,
                                  hintW,
                                  hintH);
}

- (void)renderFrameBytes:(const uint8_t *)bytes {
    if (!bytes || !_prevFrame) {
        return;
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    for (NSUInteger i = 0; i < _cellCount; i++) {
        if (_cellVisible && !_cellVisible[i]) {
            continue;
        }
        uint8_t val = bytes[i];
        if (val != _prevFrame[i]) {
            _prevFrame[i] = val;
            _cellLayers[i].opacity = (float)val / 255.0f;
        }
    }
    [CATransaction commit];
}

- (void)showExitHintBriefly {
    _hintLabel.alpha = 0.0;
    [UIView animateWithDuration:0.25 animations:^{
        self->_hintLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        if (!finished) {
            return;
        }
        [UIView animateWithDuration:0.5 delay:2.5 options:0 animations:^{
            self->_hintLabel.alpha = 0.0;
        } completion:nil];
    }];
}

@end
