# GlassFolders — iOS 16 Optics Lab 04: independent refraction core

**范围明确：Lab 04 实现了对输入背景纹理的真实采样位移和可调用的离屏 Metal 绘制接口；未实现从 SpringBoard 实时合成器取得输入纹理，也未接入当前插件。** 这不是可在桌面上实时折射的新 `.deb`。

## 文件清单

| 文件 | 用途 |
| --- | --- |
| `Experiments/GFRefraction.metal` | 真正的背景纹理坐标位移、RGB 分通道采样、圆角裁切、预乘 alpha 输出 |
| `Experiments/GFRefractionMath.h/.c` | 跨平台的同公式标量版本，可定量检查 UV 坐标，而非仅检查截图颜色 |
| `Experiments/GFStandaloneRefractionRenderer.h/.mm` | 接收调用方 **显式提供** 的 `MTLTexture` 背景与目标纹理，编码一次 Metal 绘制命令，不创建屏幕截图、不拦截 SpringBoard |
| `tests/test_refraction_math.c` | 圆角内外、背景位移、RGB 色散、禁用回退、坐标平移、异常输入检查 |
| `tests/test_refraction_isolation.py` | 防止误以为独立引擎已经加入 SpringBoard/RootHide tweak |
| `tools/render_refraction_demo.py` | 用合成网格制作可视化前后对照图（需 Python Pillow、C 编译器） |

## 测试和结果

```bash
cc -std=c11 -O2 -Wall -Wextra -Werror \
  tests/test_refraction_math.c Experiments/GFRefractionMath.c \
  -lm -o /tmp/gf-refraction-tests
/tmp/gf-refraction-tests
python3 tests/test_refraction_isolation.py
python3 tools/render_refraction_demo.py
```

演示网格：600×360 输入、280×204 面板、12K 以上像素产生非零采样位移，最大偏移约 7.04 px（实验参数 maxOffset=8px）。**这是 CPU 公式和软件采样的演示数字，并非设备帧率或实际 Metal GPU 测试结果。**

## 纹理坐标合同（接入前必须遵守）

1. 输入捕获纹理 `capture` 表示**文件夹玻璃后方的已合成背景**（未包含将要渲染的实验玻璃层），使用左上角原点；它不是静态壁纸截图。
2. 所有坐标用 **物理像素**，不是 UIKit point。`originPx` 为面板左上角相对输入纹理的像素坐标。支持屏幕旋转、窗口移动时更新原点。
3. 目标 `output` 是面板大小的 2D、单采样、renderTarget 纹理，与输入纹理不是同一对象。输入需能 shaderRead，最终合成使用**预乘 alpha**。
4. 着色器只在距离圆角轮廓 `bevelWidthPx` 内做折射；中部保持原采样坐标，边缘采用反走样透明裁切。
5. 输入纹理的刷新、生命周期、屏幕缩放、安全区以及最终与 SpringBoard 的层合成由**尚未实现**的后端处理。

在支持 Metal 编译工具链的 macOS/Xcode 上，可先单独检查 `.metal` 并生成库（**不是** Theos tweak 所需操作）：

```bash
xcrun -sdk iphoneos metal -c Experiments/GFRefraction.metal -o /tmp/GFRefraction.air
xcrun -sdk iphoneos metallib /tmp/GFRefraction.air -o /tmp/GFRefraction.metallib
```

`GFStandaloneRefractionRenderer` 初始化时需要调用方传入包含 `gfRefractionVertex/gfRefractionFragment` 的 `id<MTLLibrary>`，并提供每次绘制使用的源与目标纹理。它编码但不会提交命令缓冲区，确保调用者掌握同步与刷新时机。

## 未完成与风险

- 未使用 Apple Metal 编译器验证本次 `.metal` 或 Objective-C++ 主机；当前环境只有 Linux/Clang 的 C 单元测试。
- 未有 iOS 16 真机及 SpringBoard/`backboardd` 实时背景捕获，无法宣称视觉等价或性能达标。
- **没有增加任何新开关**，当前 `.deb` 构建配置仍只有 `Tweak.xm`；因此推送 Lab04 并重新跑原 Theos workflow 后，安装包的视觉行为不会改变。这是刻意的隔离保护。
- 未复用、修改或分发 Mango 的闭源着色器及动态库；参考的是通用 SDF/位移采样方法。

下一步 Lab05 的门槛：先确认 RootHide iOS 16 中可获取且会更新的后台合成纹理来源与可管理的输出合成点；在满足两者之前，禁止把离屏 GPU 输出冒充实时系统折射。
