#import "GFRefractionRenderer.h"
#import "GFRefractionShaderEmbedded.h"
#import <math.h>
#import <simd/simd.h>

static NSString *const GFErrorDomain = @"com.kulinich.glassfolders.refractioncore";

typedef struct {
    simd_float4 cardRect;
    simd_float4 sourceShape;
    simd_float4 optics;
    simd_float4 affineAxes;
    simd_float4 affineOffset;
} GFUniforms;
static_assert(sizeof(GFUniforms) == 80, "Metal/ObjC uniform structure mismatch");

static BOOL GFFinite(float x) { return isfinite(x); }
static BOOL GFFiniteRect(CGRect r) {
    return isfinite(r.origin.x) && isfinite(r.origin.y) &&
           isfinite(r.size.width) && isfinite(r.size.height);
}
static void GFError(NSError **error, NSInteger code, NSString *description) {
    if (error) *error = [NSError errorWithDomain:GFErrorDomain code:code
        userInfo:@{ NSLocalizedDescriptionKey: description }];
}

@implementation GFRefractionRenderer {
    id<MTLDevice> _device;
    id<MTLComputePipelineState> _pipeline;
}

- (nullable instancetype)initWithDevice:(id<MTLDevice>)device
                                     error:(NSError **)error {
    if (!device) { GFError(error, 1, @"No Metal GPU device"); return nil; }
    self = [super init];
    if (!self) return nil;
    _device = device;
    NSError *compileError = nil;
    NSString *source = [NSString stringWithUTF8String:kGFRefractionMetalSource];
    id<MTLLibrary> lib = [device newLibraryWithSource:source options:nil error:&compileError];
    if (!lib) {
        if (error) *error = compileError ?: [NSError errorWithDomain:GFErrorDomain code:2 userInfo:nil];
        return nil;
    }
    id<MTLFunction> kernel = [lib newFunctionWithName:@"gfRefractCard"];
    if (!kernel) { GFError(error, 3, @"Metal kernel gfRefractCard missing"); return nil; }
    _pipeline = [device newComputePipelineStateWithFunction:kernel error:&compileError];
    if (!_pipeline) {
        if (error) *error = compileError ?: [NSError errorWithDomain:GFErrorDomain code:4 userInfo:nil];
        return nil;
    }
    return self;
}

- (BOOL)encodeBackdrop:(id<MTLTexture>)backdrop
              intoCard:(id<MTLTexture>)output
              cardRect:(CGRect)rect
          cornerRadius:(float)radius
            bevelWidth:(float)bevel
        displacementPx:(float)displacement
          dispersionPx:(float)dispersion
         sheenStrength:(float)sheen
               opacity:(float)opacity
          samplingAxes:(simd_float4)axes
   samplingTranslation:(simd_float2)translation
         commandBuffer:(id<MTLCommandBuffer>)buffer
                 error:(NSError **)error {
    // Fail closed before starting an encoder. Never touch a committed buffer.
    if (!backdrop || !output || !buffer || backdrop == output ||
        backdrop.device != _device || output.device != _device ||
        buffer.device != _device ||
        buffer.status >= MTLCommandBufferStatusCommitted ||
        backdrop.storageMode == MTLStorageModeMemoryless ||
        output.storageMode == MTLStorageModeMemoryless ||
        !(backdrop.usage & MTLTextureUsageShaderRead) ||
        !(output.usage & MTLTextureUsageShaderWrite) ||
        output.textureType != MTLTextureType2D || backdrop.textureType != MTLTextureType2D ||
        output.sampleCount != 1 || backdrop.sampleCount != 1 ||
        (output.pixelFormat != MTLPixelFormatRGBA8Unorm &&
         output.pixelFormat != MTLPixelFormatRGBA16Float)) {
        GFError(error, 5, @"Invalid or mismatched Metal textures; output must be RGBA");
        return NO;
    }
    if (!GFFiniteRect(rect) || rect.size.width <= 2.0 || rect.size.height <= 2.0 ||
        fabs(rect.size.width - (double)output.width) > 0.5 ||
        fabs(rect.size.height - (double)output.height) > 0.5 ||
        !GFFinite(radius) || !GFFinite(bevel) || !GFFinite(displacement) ||
        !GFFinite(dispersion) || !GFFinite(sheen) || !GFFinite(opacity) ||
        !GFFinite(axes.x) || !GFFinite(axes.y) || !GFFinite(axes.z) || !GFFinite(axes.w) ||
        !GFFinite(translation.x) || !GFFinite(translation.y)) {
        GFError(error, 6, @"Invalid geometry or optics");
        return NO;
    }
    float determinant = axes.x * axes.w - axes.y * axes.z;
    if (!GFFinite(determinant) || fabsf(determinant) < 0.01f) {
        GFError(error, 7, @"Sampling transform is degenerate");
        return NO;
    }
    // Do not render stale/out-of-bounds data. Validate the four corners using
    // the caller-provided screen-to-live-texture transformation.
    float x0 = rect.origin.x, x1 = CGRectGetMaxX(rect);
    float y0 = rect.origin.y, y1 = CGRectGetMaxY(rect);
    simd_float2 corners[4] = {
        simd_make_float2(x0, y0), simd_make_float2(x1, y0),
        simd_make_float2(x0, y1), simd_make_float2(x1, y1)
    };
    for (int i = 0; i < 4; i++) {
        simd_float2 c = corners[i];
        float tx = c.x * axes.x + c.y * axes.z + translation.x;
        float ty = c.x * axes.y + c.y * axes.w + translation.y;
        if (!GFFinite(tx) || !GFFinite(ty) || tx < 0 || ty < 0 ||
            tx > backdrop.width || ty > backdrop.height) {
            GFError(error, 8, @"Card is outside the live backdrop texture");
            return NO;
        }
    }
    // C++17 aggregate initialization: avoid C++20 designated-initializer extension.
    GFUniforms u = {};
    u.cardRect = simd_make_float4((float)rect.origin.x, (float)rect.origin.y,
                                  (float)output.width, (float)output.height);
    u.sourceShape = simd_make_float4((float)backdrop.width, (float)backdrop.height,
                                     fmaxf(0.0f, radius), fmaxf(2.0f, bevel));
    u.optics = simd_make_float4(fmaxf(0.0f, fminf(displacement, 24.0f)),
                               fmaxf(0.0f, fminf(dispersion, 2.0f)),
                               fmaxf(0.0f, fminf(sheen, 0.22f)),
                               fmaxf(0.0f, fminf(opacity, 0.94f)));
    u.affineAxes = axes;
    u.affineOffset = simd_make_float4(translation.x, translation.y, 0, 0);
    id<MTLComputeCommandEncoder> encoder = [buffer computeCommandEncoder];
    if (!encoder) { GFError(error, 9, @"Failed to create Metal compute encoder"); return NO; }
    [encoder setComputePipelineState:_pipeline];
    [encoder setTexture:backdrop atIndex:0];
    [encoder setTexture:output atIndex:1];
    [encoder setBytes:&u length:sizeof(u) atIndex:0];
    NSUInteger width = MIN(8u, _pipeline.maxTotalThreadsPerThreadgroup);
    NSUInteger height = MAX(1u, MIN(8u, _pipeline.maxTotalThreadsPerThreadgroup / width));
    [encoder dispatchThreads:MTLSizeMake(output.width, output.height, 1)
        threadsPerThreadgroup:MTLSizeMake(width, height, 1)];
    [encoder endEncoding];
    return YES; // Encoded, NOT a claim the command buffer rendered successfully.
}
@end
