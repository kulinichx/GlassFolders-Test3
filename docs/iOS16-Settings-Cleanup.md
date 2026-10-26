# GlassFolders iOS 16 设置精简

只精简设置界面，不改变稳定版文件夹、资源库、Dock、锁屏、横幅、样式强度及授权功能。

移除八项未完成/调试/可选实验设置：原生实时折射、资源库透光镜片、资源库模糊诊断、iOS27 风格原型、文件夹折射桥接、文件夹微色散与其强度、Dock 透光镜片。

这些实验的旧配置键可能仍保留在用户偏好文件中，为避免隐藏功能继续生效，`GFLoadPreferences` 对应状态强制为关闭。没有清除用户其他偏好、也没有删除历史渲染代码或改动授权。

本次修改 **没有** 实现 Mango 的实时桌面背景折射。

## 资源库玻璃统一（追加）

App Library 分类卡片及搜索胶囊使用已存在的 `GFAppLibraryGlassView` 和
`CABackdropLayer`，但将固定 8–10pt 的重复模糊材质改为**跟随对应文件夹
Clear/Liquid Glass 强度曲线**，并因资源库页已存在系统模糊而缩小局部半径。

同一材质链路增加轻微中性亮度补偿、柔和体积渐变及低强度边缘高光；
不加第二个背景采样层，不触及 SpringBoard 页面切换 / 图标 / 锁屏 / Dock。

原有“资源库”开关和“跟随文件夹 / Clear / Liquid Glass”样式选择继续有效。
用户使用 Clear/Liquid Glass 强度滑块即可调节资源库效果，无新增实验选项。

这是背景材质对齐，并非 Mango 的真实像素折射。需 iOS 16.6 真机确认。

## Dock 清透外观修复

前一版设置清理将 `GFDockLensMaterialEnabled` 强制关闭，导致 Dock 在
`Dock Mode = Glass Effect` 时从原有约 4pt 的清透模糊材质退回到约
10pt 的普通模糊材质。这会让 Dock 看起来更糊。

现在 `DockEnabled = ON` 且 `DockMode = Glass Effect` 时，自动启用
已有的 4pt 清透方案（边缘独立 1.15pt 采样），无需恢复旧 Beta 开关。
Dock 的隐藏背景模式仍保持不变；文件夹、资源库、锁屏和授权代码不修改。
这只是恢复之前已存在的 Dock 配方，不涉及新渲染引擎。
