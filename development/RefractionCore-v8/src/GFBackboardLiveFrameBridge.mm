#import "GFBackboardLiveFrameBridge.h"
#import <math.h>

@implementation GFBackboardLiveFrame
- (instancetype)init {
    self = [super init];
    if (self) {
        _samplingAxes = simd_make_float4(1.0f,0.0f,0.0f,1.0f);
        _samplingTranslation = simd_make_float2(0.0f,0.0f);
    }
    return self;
}
@end

@implementation GFBackboardLiveFrameBridge {
    GFRefractionRenderer *_renderer;
    uint64_t _lastAcceptedFrameSequence;
}
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    _renderer = [[GFRefractionRenderer alloc] initWithDevice:device error:error];
    return _renderer ? self : nil;
}
- (BOOL)encodeLiveFrame:(GFBackboardLiveFrame *)frame error:(NSError **)error {
    // Serialise monotonic frame checks and encoding. Frame properties must not
    // be mutated concurrently by the caller.
    @synchronized (self) {
        // Only a verified OS-specific adapter can attest to this origin. This
        // Boolean alone does NOT authenticate a compositor source.
        if (!frame || !frame.verifiedCompositorBackdrop ||
            !frame.liveFrameSequence || frame.liveFrameSequence <= _lastAcceptedFrameSequence ||
            !frame.liveBackdrop || !frame.cardOutput || !frame.commandBuffer ||
            !isfinite(frame.screenPixelsPerPoint) ||
            frame.screenPixelsPerPoint < 1.0f || frame.screenPixelsPerPoint > 4.0f) {
            if (error) *error = [NSError errorWithDomain:@"com.kulinich.glassfolders.refractioncore"
                code:10 userInfo:@{NSLocalizedDescriptionKey: @"No verified fresh compositor frame or valid pixel scale"}];
            return NO;
        }
        // Design target: ~16pt rounded corner at the *actual* screen scale.
        // The rim is 8.5pt wide (~17 px on a 2x device). Never confuse pt/px.
        const float scale = frame.screenPixelsPerPoint;
        BOOL encoded = [_renderer encodeBackdrop:frame.liveBackdrop
                                        intoCard:frame.cardOutput
                                        cardRect:frame.cardRectInScreenPixels
                                    cornerRadius:16.0f * scale
                                      bevelWidth:8.5f * scale
                                  displacementPx:3.5f * scale
                                    dispersionPx:0.175f * scale
                                   sheenStrength:0.10f
                                         opacity:0.78f
                                    samplingAxes:frame.samplingAxes
                             samplingTranslation:frame.samplingTranslation
                                   commandBuffer:frame.commandBuffer error:error];
        if (encoded) _lastAcceptedFrameSequence = frame.liveFrameSequence;
        return encoded;
    }
}
@end
