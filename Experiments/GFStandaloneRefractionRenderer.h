#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

// Isolated GPU renderer. A caller must supply the COMPOSITED source texture.
// It does not capture SpringBoard, hook backboardd or register a CAFilter.
// Deliberately NOT part of the current Theos target.
@interface GFStandaloneRefractionRenderer : NSObject
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                                  library:(id<MTLLibrary>)library
                                    error:(NSError **)error;

// output dimensions must equal panelSizePx. originPx is relative to the top-left
// of capture, in pixels (NOT UIKit points). Encodes only; caller commits buffer.
- (BOOL)encodeCapture:(id<MTLTexture>)capture
               output:(id<MTLTexture>)output
            originPx:(vector_float2)originPx
       cornerRadiusPx:(float)cornerRadiusPx
         bevelWidthPx:(float)bevelWidthPx
          maxOffsetPx:(float)maxOffsetPx
         dispersionPx:(float)dispersionPx
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
