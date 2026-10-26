# GlassFolders iOS 16 — Optics Lab 03

目标：以**独立、默认关闭**的方式，为普通桌面文件夹和展开面板增加对*现有第三方已注册 CAFilter* 的安全桥接，而不动现有 Liquid Glass 材质。

## 新设置

在「文件夹样式 → Liquid Glass」中增加：`文件夹实时折射桥接（需兼容引擎）`。

- 默认关闭。只在插件已激活、文件夹已启用并选择 Liquid Glass 时尝试工作。
- 只有发现 `dylv.liquidglass.refraction` 或 `dylv.liquidglass.dock` 这类**已注册且可实例化**的滤镜时才新建折射边缘层。没有兼容引擎时维持原来的模糊、高光与色散，不制造假“折射”。
- 折射层不拦截触摸、不截图、不使用常驻渲染循环、不注入 `backboardd`。仅覆盖圆角边缘，避免整块卡片被替换成未知材质。
- 限制重试频率，避免每个文件夹每次布局都查找私有滤镜工厂。失败时删除实验层。
- 控制台的 `[GFOptics03]` 日志用于检查滤镜是否注册/被接纳。但 **CAFilter 实例化并成功附着 ≠ 后台真实执行了折射着色器**。实际折射仍需在 iOS 16 设备上对具有高对比图案的壁纸进行对比验证。

## 测试步骤

1. 安装此实验分支的编译包之前备份稳定版；不要直接合并 `main`。
2. 保持 `文件夹`、`Liquid Glass` 开启；新开关先关闭，对比原版视觉。
3. 仅当设备上有**受信任且兼容的折射渲染引擎**时，打开新开关并查看桌面图标边缘及展开面板。
4. 如无变化，检查系统日志中 `GFOptics03` 是否提示无兼容滤镜。缺少兼容引擎是预期的正常降级，不是编译失败。
5. 若出现 SpringBoard 视觉异常，关闭新开关并重新加载 SpringBoard；必要时恢复此前的 `.deb`。

## 不包含

不附带 Mango 代码、不附带支持 iOS 16 的独立 render-server shader、不宣称已经实现引擎级动态背景采样。`Experiments/GFRefraction.metal` 仍不参与 Theos 构建。

## 自动检查

`python3 tests/test_folder_native_bridge.py` 验证默认关闭、独立设置、两个安装位置和代码回退保护；原 Lab 02 的算法测试继续运行。真正构建和设备测试由 GitHub Actions 与 iOS 16 RootHide 设备完成。
