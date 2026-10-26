#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#import <math.h>
#import "../GFStandaloneRefractionRenderer.h"

// Optics Lab 05 is a separate, synthetic GPU test application.
// It does NOT read the screen, capture SpringBoard or register any CAFilter.
typedef struct { vector_float2 sizePx; float timeSec; float reserved; } GFProbeBackgroundParams;
typedef struct {
    vector_float2 screenSizePx;
    vector_float2 originPx;
    vector_float2 panelSizePx;
    float opacity;
    float reserved;
} GFProbePanelParams;
static_assert(sizeof(GFProbeBackgroundParams) == 16, "background shader ABI mismatch");
static_assert(sizeof(GFProbePanelParams) == 32, "panel shader ABI mismatch");

@interface GFProbeViewController : UIViewController <MTKViewDelegate>
@end
@implementation GFProbeViewController {
    MTKView *_metalView;
    UISlider *_slider;
    UILabel *_status;
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _generate;
    id<MTLRenderPipelineState> _copy;
    id<MTLRenderPipelineState> _panel;
    id<MTLTexture> _capture;
    id<MTLTexture> _panelTexture;
    GFStandaloneRefractionRenderer *_refraction;
    CFTimeInterval _started;
    BOOL _ready;
}
- (id<MTLRenderPipelineState>)pipeline:(id<MTLLibrary>)library
                                vertex:(NSString *)vertex
                              fragment:(NSString *)fragment
                                format:(MTLPixelFormat)format
                                 blend:(BOOL)blend error:(NSError **)error {
    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = [library newFunctionWithName:vertex];
    desc.fragmentFunction = [library newFunctionWithName:fragment];
    desc.colorAttachments[0].pixelFormat = format;
    if (blend) {
        desc.colorAttachments[0].blendingEnabled = YES;
        desc.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
        desc.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
        desc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
        desc.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
        desc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        desc.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    }
    return [_device newRenderPipelineStateWithDescriptor:desc error:error];
}
- (id<MTLTexture>)textureWithWidth:(NSUInteger)w height:(NSUInteger)h {
    MTLTextureDescriptor *desc = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                     width:w height:h mipmapped:NO];
    desc.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    desc.storageMode = MTLStorageModePrivate;
    return [_device newTextureWithDescriptor:desc];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;
    _device = MTLCreateSystemDefaultDevice();
    _metalView = [[MTKView alloc] initWithFrame:self.view.bounds device:_device];
    _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalView.preferredFramesPerSecond = 30;
    _metalView.enableSetNeedsDisplay = NO;
    _metalView.paused = YES;  // render only after full initialization
    _metalView.delegate = self;
    [self.view addSubview:_metalView];
    UIView *hud = [[UIView alloc] initWithFrame:CGRectZero];
    hud.translatesAutoresizingMaskIntoConstraints = NO;
    hud.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
    hud.layer.cornerRadius = 16;
    [self.view addSubview:hud];
    _status = [[UILabel alloc] initWithFrame:CGRectZero];
    _status.translatesAutoresizingMaskIntoConstraints = NO;
    _status.numberOfLines = 0;
    _status.textColor = UIColor.whiteColor;
    _status.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _status.text = @"Lab 05 / synthetic GPU refraction\nNo SpringBoard capture";
    [hud addSubview:_status];
    _slider = [[UISlider alloc] initWithFrame:CGRectZero];
    _slider.translatesAutoresizingMaskIntoConstraints = NO;
    _slider.minimumValue = 0;
    _slider.maximumValue = 16;
    _slider.value = 8;
    [hud addSubview:_slider];
    [NSLayoutConstraint activateConstraints:@[
        [hud.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:14],
        [hud.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-14],
        [hud.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:14],
        [_status.leadingAnchor constraintEqualToAnchor:hud.leadingAnchor constant:14],
        [_status.trailingAnchor constraintEqualToAnchor:hud.trailingAnchor constant:-14],
        [_status.topAnchor constraintEqualToAnchor:hud.topAnchor constant:12],
        [_slider.leadingAnchor constraintEqualToAnchor:hud.leadingAnchor constant:14],
        [_slider.trailingAnchor constraintEqualToAnchor:hud.trailingAnchor constant:-14],
        [_slider.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:7],
        [_slider.bottomAnchor constraintEqualToAnchor:hud.bottomAnchor constant:-10]
    ]];
    NSError *error = nil;
    NSString *shaderPath = [NSBundle.mainBundle pathForResource:@"GFOpticsLab05" ofType:@"metallib"];
    id<MTLLibrary> library = shaderPath ? [_device newLibraryWithURL:[NSURL fileURLWithPath:shaderPath] error:&error] : nil;
    _queue = [_device newCommandQueue];
    _refraction = [[GFStandaloneRefractionRenderer alloc] initWithDevice:_device library:library error:&error];
    if (library && _queue && _refraction) {
        _generate = [self pipeline:library vertex:@"gfProbeVertex" fragment:@"gfProbeBackground"
                           format:MTLPixelFormatBGRA8Unorm blend:NO error:&error];
        _copy = [self pipeline:library vertex:@"gfProbeVertex" fragment:@"gfProbeCopy"
                       format:MTLPixelFormatBGRA8Unorm blend:NO error:&error];
        _panel = [self pipeline:library vertex:@"gfProbeVertex" fragment:@"gfProbePanel"
                        format:MTLPixelFormatBGRA8Unorm blend:YES error:&error];
    }
    _ready = (_device && library && _queue && _refraction && _generate && _copy && _panel);
    if (!_ready) {
        _status.text = [NSString stringWithFormat:@"GPU test unavailable: %@",error.localizedDescription ?: @"Metal initialization failed"];
        return;
    }
    _started = CACurrentMediaTime();
    _metalView.paused = NO;
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    _capture = nil;
    _panelTexture = nil;
}
- (void)drawInMTKView:(MTKView *)view {
    if (!_ready) return;
    const NSUInteger w = (NSUInteger)view.drawableSize.width;
    const NSUInteger h = (NSUInteger)view.drawableSize.height;
    if (!w || !h || w > 4096 || h > 8192) return;
    // Mid-screen target, below the HUD; physical-pixel geometry throughout.
    NSUInteger panelW = MIN(w * 76 / 100, 820);
    NSUInteger panelH = MIN(panelW * 11 / 10, h * 45 / 100);
    panelW = MAX(panelW, 16);
    panelH = MAX(panelH, 16);
    vector_float2 origin = {(float)((w-panelW)/2), (float)(h-panelH)/2};
    if (!_capture || _capture.width != w || _capture.height != h)
        _capture = [self textureWithWidth:w height:h];
    if (!_panelTexture || _panelTexture.width != panelW || _panelTexture.height != panelH)
        _panelTexture = [self textureWithWidth:panelW height:panelH];
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (!_capture || !_panelTexture || !drawable) return;
    id<MTLCommandBuffer> cmd = [_queue commandBuffer];
    if (!cmd) return;
    MTLRenderPassDescriptor *capturePass = [MTLRenderPassDescriptor renderPassDescriptor];
    capturePass.colorAttachments[0].texture = _capture;
    capturePass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    capturePass.colorAttachments[0].storeAction = MTLStoreActionStore;
    id<MTLRenderCommandEncoder> encoder = [cmd renderCommandEncoderWithDescriptor:capturePass];
    if (!encoder) return;
    GFProbeBackgroundParams bg = {{(float)w, (float)h}, (float)(CACurrentMediaTime()-_started), 0};
    [encoder setRenderPipelineState:_generate];
    [encoder setFragmentBytes:&bg length:sizeof(bg) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    NSError *error = nil;
    BOOL encoded = [_refraction encodeCapture:_capture output:_panelTexture
                                      originPx:origin cornerRadiusPx:42.0f * view.contentScaleFactor
                               bevelWidthPx:18.0f * view.contentScaleFactor
                                maxOffsetPx:_slider.value
                               dispersionPx:0.6f * view.contentScaleFactor
                              commandBuffer:cmd error:&error];
    if (!encoded) {
        // Don't partially present a misleading composite on error.
        dispatch_async(dispatch_get_main_queue(), ^{ self->_status.text = error.localizedDescription; });
        view.paused = YES;
        return;
    }
    MTLRenderPassDescriptor *screenPass = view.currentRenderPassDescriptor;
    if (!screenPass) return;
    encoder = [cmd renderCommandEncoderWithDescriptor:screenPass];
    if (!encoder) return;
    [encoder setRenderPipelineState:_copy];
    [encoder setFragmentTexture:_capture atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    GFProbePanelParams panel = {{(float)w,(float)h},origin,
                                {(float)panelW,(float)panelH},1.0f,0.0f};
    [encoder setRenderPipelineState:_panel];
    [encoder setFragmentTexture:_panelTexture atIndex:0];
    [encoder setFragmentBytes:&panel length:sizeof(panel) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    [cmd presentDrawable:drawable];
    [cmd commit];
}
@end
