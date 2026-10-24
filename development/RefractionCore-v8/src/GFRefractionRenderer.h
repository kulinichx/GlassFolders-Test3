#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <CoreGraphics/CoreGraphics.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

// ONLY a live compositor texture should be supplied as `backdrop`.
// Both the backdrop and output textures must belong to the same Metal device.
// Does not capture views, install hooks, display layers or commit command buffers.
@interface GFRefractionRenderer : NSObject
- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                                     error:(NSError * _Nullable * _Nullable)error;

// Mapping from screen-pixel coordinates to backdrop texture-pixel coordinates:
// X = screenX * axes.x + screenY * axes.z + translation.x
// Y = screenX * axes.y + screenY * axes.w + translation.y
// Identity: axes=(1,0,0,1), translation=(0,0).
- (BOOL)encodeBackdrop:(id<MTLTexture>)backdrop
              intoCard:(id<MTLTexture>)output
              cardRect:(CGRect)cardRectInScreenPixels
          cornerRadius:(float)cornerRadiusPixels
            bevelWidth:(float)bevelWidthPixels
        displacementPx:(float)displacementPixels
          dispersionPx:(float)dispersionPixels
         sheenStrength:(float)sheenStrength
               opacity:(float)opacity
         samplingAxes:(simd_float4)axes
  samplingTranslation:(simd_float2)translation
         commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                 error:(NSError * _Nullable * _Nullable)error;
@end
NS_ASSUME_NONNULL_END
