# 白色背景下的玻璃可读性研究

研究日期：2026-11-05。

范围：用户提供的两张截图、苹果公开 Liquid Glass 设计说明、本地 Mango 安装包、Liquidass 的公开通知实现，以及研究时的 GlassFolders 锁屏与横幅代码。研究阶段只增加本文档；随后用户要求继续实现，候选改动与验证边界见 [通知与横幅的白底可读性候选实现](notification-contrast-candidate.md)。没有构建或安装插件。

## 结论

白底问题需要分开处理：玻璃轮廓是否可见，以及文字是否可读。加粗白色高光只能影响前者，在接近纯白的背景上甚至不能产生明显差异，不能代替文字对比度保护。

苹果公开方案的核心是材质与前景内容协同适配，而不是在所有背景上使用同一组白色描边、固定模糊和固定透明度。Mango 则提供了可核实的工程参考：分场景参数、浅色与深色 Tint、独立于 Tint 的边缘光学渲染。但本次静态检查不能证明 Mango 已经解决相同白壁纸上的通知文字问题。

## 证据边界

- 截图能说明白色通知内容与浅背景的分离不足，不能单独确认操作系统版本、插件版本或实际使用的材质实现。
- 苹果部分依据 WWDC25《Meet Liquid Glass》和当前可读取的《Materials》指南。没有把这些资料标成已经核实的 iOS 27 专属内部实现或参数。
- Mango 部分只针对本地 `mango_1.0-Beta8-1_roothide.deb`，不代表其最新版本，也不代表所有功能路径。
- 没有运行 Mango、加载其动态库、修改授权或复制其渲染源码。只检查包结构、Mach-O 元数据、参数标识和嵌入着色器的相关计算。
- 符号、选择器与字符串的存在，只能说明包内存在相关接口线索，不能直接证明调用关系、默认值、运行频率、能耗或视觉效果。

## 苹果的公开处理方式

### Regular 与 Clear 不是同一类策略

`regular` 会对背景做模糊及亮度调整，适合背景可能影响可读性或文字较多的组件。

`clear` 更强调透出图片、视频等视觉内容，不具备 Regular 的完整自适应行为。苹果指南建议：背景明亮时，可以在 Clear 组件后考虑约 35% 不透明度的深色遮暗层；背景已经足够暗，或系统媒体控件已有遮暗时，则不需要重复添加。

因此，35% 不是所有玻璃、所有壁纸、所有通知和所有字体通用的“苹果参数”，也不是小字号文字对比度已经合格的证明。

### 前景内容也参与对比度适配

WWDC25 说明，小型玻璃元素及其符号可以随背后内容切换明暗，Regular 上的内容会获得相应处理。较大的菜单和侧栏也会适配，但不会简单地整片反复翻转明暗。

对 GlassFolders 的启示：替换系统底板后，必须重新验证系统原有文字、图标与 vibrancy 在新底板上是否仍有足够对比，不能因为保留原生文字就认定可读性也被保留。

### 阴影不是越重越好

苹果说明中的阴影会根据背景内容变化：背后有文字等细节时加强分离；背后是均匀浅色时反而降低阴影不透明度。不能将其概括为“白底统一加重外阴影”。

用于本项目的细暗缘、局部吸收和柔和投影属于拟合方向，需要实机比较，并非苹果公开的固定配方。

## Mango 安装包中的可核实信息

### 样本身份

- 包名：`com.go.mango`。
- 版本：`1.0-Beta8-1`。
- 架构：`iphoneos-arm64e`。
- 文件大小：15,667,662 字节。
- SHA256：`8dcb0e02c4402a4dfa92f64b9e3894386a03db327f5eb83f72b795c4c8b5378f`。

### 渲染与配置分层

`MangoOSRendering.dylib` 的注入配置包含 `com.apple.backboardd`；包内能识别 Metal 渲染接口以及 `mangoGlassVertex`、`mangoGlassFragment` 入口。

该模块包含以下参数标识：

- 表面颜色：`.TintR`、`.TintG`、`.TintB`、`.TintStrength`、`.LightTintColor`、`.DarkTintColor`。
- 光学形状：`.BezelRatio`、`.GlassThickness`、`.RefractionScale`、`.RefractiveIndex`。
- 边缘色散与高光：`.DispersionStrength`、`.DispersionEnabled`、`Renderer.FresnelGlareStrength`。
- 模糊：`.Blur`。

同一模块还包含 `Notification`、`Banner`、`Dock`、`QuickActions`、`OpenFolder`、`AppLibrary`、`Keyboard` 等场景标识。这支持“按场景管理材质参数”的架构判断，但不能只按字符串排列推断每个场景的默认值。

`LightTintColor` 与 `DarkTintColor` 说明存在区分明暗的配置入口，不能据此认定它们跟随局部壁纸亮度；也可能对应外观模式，具体选择逻辑仍需调用链或实机证据。

### 与白底直接相关的着色器行为

检查的平面与折射输出路径都包含表面 Tint 混合。边缘高光随后单独计算，其中有背景亮度参与的强度因子。

该高光输出使用只会维持或提高通道亮度的合成方式。由这段计算可推知：如果输入和 Tint 混合后的颜色已经是纯白，仅增加这段高光不会产生更深的轮廓。要改善白底分离，还需要合适的 Tint、前景处理或其他明暗层。

这不是对整个 Mango 的否定：宿主层还有其他配置和视图。这里仅说明不能把它的折射或菲涅尔高光单独视为白底可读性的完整解法。

### 前景与边缘的线索

`MangoHello.dylib` 中存在 `contrastColorForColor:`、`applyTextGlassShadowToLabel:enabled:`、`labelColor` 等选择器。

`MangoPanda.dylib` 与其他宿主模块中存在 `lgSpecularDarkEnabledOverride`、文字颜色和阴影相关选择器。

这些线索值得进一步检查，但尚未证明其具体作用于通知文字，也未证明它们按局部壁纸亮度实时更新。本次不将其写成已确认功能。

## 其他插件：Liquidass 的通知实现

本次读取的公开 `Hooks/Platter.x` 包含 `updateSeamlessLabelColor`，保存标签原始颜色，并有按条件使用黑色或白色文字、恢复原始颜色的处理。

可借鉴的重点是：前景文字并非完全不动，而是与玻璃功能一起管理；关闭或退出相关状态时，应能恢复原始颜色。本次没有据此认定它使用局部壁纸亮度自动选择文字颜色，也没有复制其实现。

此外，检查 GlassFolders 替换底板后的原生 vibrancy 与文字混合是否仍然合适，是本项目的排查建议，不是本次已确认的 Liquidass 实现或 GlassFolders 根因。不能直接删除所有 vibrancy。

## 研究时 GlassFolders 的对应差距

检查位置：`GFLockScreenGlass.h` 与 `GFGlassRim.h`。

- 锁屏卡片使用固定 8 pt 模糊；仅调模糊不能保证白底文字对比。
- 共享边缘具有白色反光、白色亮肩与很浅的内侧暗部，但检查路径中没有基于局部背景亮度切换这些参数的逻辑。
- 当前工作区在本次研究前已经存在通知专用的固定 35% 黑色遮暗改动，本次保留，没有覆盖或宣称它是本次完成的修复。
- 该改动对通知卡片和横幅启用，不等于已覆盖音乐面板、实时活动与圆形按钮。
- 固定遮暗能作为候选保底策略，但没有明暗背景条件判断，不能等同苹果 Regular 自适应；也没有证明截图中的实机已安装这份代码。
- 生产锁屏路径与实验性折射实现应分开看，不能因为仓库已有 Metal 实验就宣称通知已经使用实时折射。

## 建议的实现顺序

1. **先确认前景合成**：在同一白色壁纸上，比较原生底板与替换底板，确认标题、正文、时间与图标的 alpha、vibrancy 和混合行为。避免全局修改 UILabel 或覆盖不相关内容。
2. **先保证可读性**：若保留系统白色前景，就要在文字背后提供足够的局部深色背景；若采用浅色 Regular 风格，则需协调语义文字颜色，不能只把背景变浅。
3. **再调白底轮廓**：保留窄而柔和的高光，配合克制的暗部过渡。单独评估前排和折叠后排，避免全周粗黑边、宽灰雾圈或后排叠黑。
4. **分离场景配方**：通知正文、横幅、圆按钮、Dock 与文件夹各自校准，不复用一组全局 Tint 或遮暗值。
5. **最后验证动态光学**：折射、高光和运动响应在可读性稳定后再接入；不得以带有折射效果代替明暗适配。
6. **新增自适应须有可靠输入**：系统深浅模式不是壁纸亮度。若缺少可靠的背景信息，应先验证静态保底或原生材质回退，不臆造私有采样 API，也不为判亮度直接加入每帧截图。

以上记录研究阶段的实现建议。后续候选源码改动见 [候选实现记录](notification-contrast-candidate.md)，不代表全部建议已经完成或实机视觉通过。

## 实机验收

- 背景：纯白、浅灰、黑白高反差、彩色与深色壁纸。
- 文字：应用名、正文、时间、次要文字、隐藏预览及长文字。
- 通知：单条、展开、折叠后排、滑动删除与连续横幅。
- 状态：锁屏和应用内、明暗外观、开关恢复、解锁和取消解锁。
- 对比：同场景原生材质、当前正式包、候选配方，以及可获取时的相同 Mango 版本。
- 稳定性：无叠加变白或变黑、无闪烁、无文字突然变色、无触摸与动画回退。

## 来源与复查入口

1. Apple，《Meet Liquid Glass》，WWDC25，尤其 Adaptivity、Principles、Variants 与 Legibility 部分。
   https://developer.apple.com/videos/play/wwdc2025/219/
2. Apple，《Materials》，包含 Regular / Clear、亮背景遮暗与 vibrancy 的指导。
   https://developer.apple.com/design/human-interface-guidelines/materials
   可读取的正文数据：https://developer.apple.com/tutorials/data/design/human-interface-guidelines/materials.json
3. Liquidass，公开通知实现 `Hooks/Platter.x`；引用范围限于本次读取的实现，不代表其全部模块。
   https://github.com/TrollStoreX/liquidass/blob/main/Hooks/Platter.x
4. 本地 Mango 包：工作区根目录下 `mango_1.0-Beta8-1_roothide.deb`。
5. 包结构与渲染元数据复查：`GlassFolders-Test3-audit/tools/inspect_rendering_package.py`，本次复用了该只读脚本，并在内存中补查相关字符串和着色器计算；没有修改此脚本。
