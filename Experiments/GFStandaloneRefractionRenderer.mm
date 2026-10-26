#import "GFStandaloneRefractionRenderer.h"
#import <simd/simd.h>
#import <math.h>

// Layout must stay synchronized with GFRefractionUniforms in GFRefraction.metal.
// float2 fields have 8 byte alignment: 3*8 + 4*4 = 40 bytes.
typedef struct {
    vector_float2 captureSizePx;
    vector_float2 originPx;
    vector_float2 panelSizePx;
    float cornerRadiusPx;
    float bevelWidthPx;
    float maxOffsetPx;
    float dispersionPx;
} GFRefractionUniforms;
static_assert(sizeof(GFRefractionUniforms) == 40, "Metal uniform ABI changed");

static NSError *GFOptics04Error(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"com.kulinich.glassfolders.opticslab04"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation GFStandaloneRefractionRenderer {
    id<MTLDevice> _device;
    id<MTLFunction> _vertex;
    id<MTLFunction> _fragment;
    NSMutableDictionary<NSNumber *, id<MTLRenderPipelineState>> *_pipelines;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device
                        library:(id<MTLLibrary>)library
                          error:(NSError **)error {
    if (!(self = [super init])) return nil;
    if (!device || !library || library.device != device) {
        if (error) *error = GFOptics04Error(1, @"Invalid device or Metal library");
        return nil;
    }
    _device = device;
    _vertex = [library newFunctionWithName:@"gfRefractionVertex"];
    _fragment = [library newFunctionWithName:@"gfRefractionFragment"];
    if (!_vertex || !_fragment) {
        if (error) *error = GFOptics04Error(2, @"Missing Optics Lab 04 shader functions");
        return nil;
    }
    _pipelines = [NSMutableDictionary dictionary];
    return self;
}

- (BOOL)encodeCapture:(id<MTLTexture>)capture
               output:(id<MTLTexture>)output
             originPx:(vector_float2)originPx
       cornerRadiusPx:(float)cornerRadiusPx
         bevelWidthPx:(float)bevelWidthPx
          maxOffsetPx:(float)maxOffsetPx
         dispersionPx:(float)dispersionPx
        commandBuffer:(id<MTLCommandBuffer>)commandBuffer
                error:(NSError **)error {
    if (!capture || !output || !commandBuffer ||
        capture == output || capture.device != _device || output.device != _device ||
        capture.width == 0 || capture.height == 0 ||
        output.width == 0 || output.height == 0 ||
        capture.textureType != MTLTextureType2D || output.textureType != MTLTextureType2D ||
        capture.sampleCount != 1 || output.sampleCount != 1 ||
        !(isfinite(originPx.x) && isfinite(originPx.y) &&
          isfinite(cornerRadiusPx) && isfinite(bevelWidthPx) &&
          isfinite(maxOffsetPx) && isfinite(dispersionPx)) ||
        cornerRadiusPx < 0 || bevelWidthPx < 1 || maxOffsetPx < 0 ||
        maxOffsetPx > 32 || dispersionPx < 0 || dispersionPx > 8) {
        if (error) *error = GFOptics04Error(3, @"Invalid texture or optical parameters");
        return NO;
    }
    // Explicit rendering semantics: no implicit UIKit screen snapshots.
    if ((capture.usage != MTLTextureUsageUnknown && !(capture.usage & MTLTextureUsageShaderRead)) ||
        (output.usage != MTLTextureUsageUnknown && !(output.usage & MTLTextureUsageRenderTarget))) {
        if (error) *error = GFOptics04Error(4, @"Texture usages are not shaderRead / renderTarget");
        return NO;
    }
    NSNumber *format = @(output.pixelFormat);
    id<MTLRenderPipelineState> pipeline = _pipelines[format];
    if (!pipeline) {
        MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
        desc.vertexFunction = _vertex;
        desc.fragmentFunction = _fragment;
        desc.colorAttachments[0].pixelFormat = output.pixelFormat;
        // Premultiplied output; blend when composing the output texture later.
        NSError *pipelineError = nil;
        pipeline = [_device newRenderPipelineStateWithDescriptor:desc error:&pipelineError];
        if (!pipeline) {
            if (error) *error = pipelineError ?: GFOptics04Error(5, @"Pipeline creation failed");
            return NO;
        }
        _pipelines[format] = pipeline;
    }
    const GFRefractionUniforms settings = {
        .captureSizePx = {(float)capture.width, (float)capture.height},
        .originPx = originPx,
        .panelSizePx = {(float)output.width, (float)output.height},
        .cornerRadiusPx = cornerRadiusPx,
        .bevelWidthPx = bevelWidthPx,
        .maxOffsetPx = maxOffsetPx,
        .dispersionPx = dispersionPx
    };
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = output;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0,0,0,0);
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) {
        if (error) *error = GFOptics04Error(6, @"Unable to create Metal encoder");
        return NO;
    }
    [encoder setRenderPipelineState:pipeline];
    [encoder setFragmentTexture:capture atIndex:0];
    [encoder setFragmentBytes:&settings length:sizeof(settings) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    return YES;
}
@end
