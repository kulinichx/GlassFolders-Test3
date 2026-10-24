#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <simd/simd.h>
#import "GFRefractionRenderer.h"

NS_ASSUME_NONNULL_BEGIN

// An explicit integration boundary: an OS-version-specific *verified*
// compositor adapter must supply these. It is deliberately not a SpringBoard
// screenshot and contains no undocumented method offsets or hook addresses.
@interface GFBackboardLiveFrame : NSObject
@property (nonatomic, strong) id<MTLTexture> liveBackdrop;
@property (nonatomic, strong) id<MTLTexture> cardOutput;
@property (nonatomic, strong) id<MTLCommandBuffer> commandBuffer;
@property (nonatomic) CGRect cardRectInScreenPixels;
// Required, measured on the actual compositor display (NOT guessed at 2x).
// Card origin, extent, backdrop mapping, corner radius and optics use pixels.
@property (nonatomic) float screenPixelsPerPoint;
@property (nonatomic) simd_float4 samplingAxes;
@property (nonatomic) simd_float2 samplingTranslation;
@property (nonatomic) uint64_t liveFrameSequence;
@property (nonatomic) BOOL verifiedCompositorBackdrop;
@end

@interface GFBackboardLiveFrameBridge : NSObject
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device error:(NSError **)error;
// Returns NO if input is absent, stale, unverified or missing display scale;
// renders nothing. Treat input as immutable during encodeLiveFrame:.
// verifiedCompositorBackdrop is an assertion by the trusted adapter, NOT
// proof that this class can obtain or authenticate private compositor frames.
// Does NOT commit or present a Metal command buffer.
- (BOOL)encodeLiveFrame:(GFBackboardLiveFrame *)frame error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
