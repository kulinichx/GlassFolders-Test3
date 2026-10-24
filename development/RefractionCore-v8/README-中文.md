# GlassFolders Refraction Core v8.0.2-dev（Apple 编译验证版）

## 版本含义与真实状态

本包是在用户上传的 **v8.0.0-dev** 16 文件源码基础上增量修改的**独立研发模块**，没有把闭源 Mango/LiqLite 的 shader 或动态库复制进项目。它**不是新的 GlassFolders 正式插件版本**，不会自己注入 SpringBoard/backboardd、接管系统渲染或显示实时折射；生产包版本仍以原仓库 `control` 为准。

| 验证层级 | 当前实际证据 |
|---|---|
| 离线 CPU | 本环境运行 `python3 -m unittest discover -s tests -p 'test_*.py' -v`，14/14 通过 |
| 静态 / Shell / CI 结构 | Linux 本地脚本语法检查通过；YAML 解析通过 |
| Metal 编译（Apple Xcode） | 尚未在 Apple 工具链执行；提供可供 GitHub Actions 执行的真实编译检查 |
| Theos iOS ARM64 编译 | 尚未执行；GitHub Actions 独立编译 job 待运行 |
| Metal 真 GPU 执行 | 尚未执行；附合成纹理 GPU smoke 程序，需有 Metal 设备 |
| 系统实时背景采样 | **未实现**。现有桥接仅是调用约定，并不抓取/认证系统帧 |
| iPad App 资源库可见折射 | **未验证**，本包安装后不会产生任何视觉变化 |

## 本次实际修复

1. `GFRefractionRenderer.mm` 原 `GFUniforms` 使用 C++20 风格指定成员初始化，在 `-std=c++17` 编译下属于扩展；已换成标准 C++17 初始化赋值。
2. Metal 编码前额外拒绝**跨 GPU 设备的 command buffer、已提交的 command buffer、memoryless 输入/输出纹理**；保留原先的格式、用法、几何、坐标范围验证。
3. `GFBackboardLiveFrame` 新增必须由真实显示路径报告的 `screenPixelsPerPoint`；拒绝 0、NaN 或不合理的 scale。将 16pt 目标圆角、8.5pt 物理边缘等参数转换为像素。原版 18px 被误当成 15–17pt，尤其在 2x iPad 上不准确。
4. `encodeLiveFrame` 用 `@synchronized(self)` 序列化单一 bridge 内的帧序号验证和编码；仅成功编码后更新最后接受的帧序号。**调用方仍须保证 frame 对象及 command buffer 在编码期间不被并发修改。**
5. 添加 Apple 真实 `.metal -> .air -> .metallib`、iOS ObjC++/dylib 编译校验脚本，macOS GPU smoke 编译与可选执行，Theos ARM64 GitHub Actions 任务。
6. 从原有 7 个测试扩充到 **14 个离线/合同测试**。GPU smoke 在有 GPU 的主机上比较**有位移 vs 无位移**两次真实计算输出，不只测试是否有非零像素；仅使用人工合成背景。

## Git Bash：安全添加到当前独立 worktree

把 ZIP 解压后，在**已有**的 GlassFolders 工作树执行（切勿切到原始主工作目录）：

```bash
cd "/g/AITEST/GlassFolders 1.0/GlassFolders-v7-2-work" || exit 1
export GIT_PAGER=cat
bash "$HOME/Downloads/GlassFolders-RefractionCore-v8.0.2/install-GitBash.sh"
```

此脚本先运行 14 项测试，然后复制到 `development/RefractionCore-v8`，并 `git add`。**目标目录如果已经存在会停止，不覆盖，也不自动升级已有 v8。** 不创建/切换工作树或分支、不 stash/reset、不修改 `control`、`Tweak.xm`、Dock、App 资源库、设置、issuer 授权、测试源文件；也不会 commit/push。**v8.0.2 修复了本地缺少 NumPy 时无法安装的问题**：安装脚本会先检查当前 Python 是否具备 `numpy` 和 `Pillow`；如果缺少，会自动在系统临时目录创建隔离虚拟环境，安装二者的二进制发行包，执行完整测试后删除临时环境（需要网络，不修改你的 Python 全局或用户包，也不会把虚拟环境复制进仓库）。若不允许脚本联网，可先安装依赖，或设置 `GF_TEST_SETUP=never` 让它明确报错并停止。工作树源代码只会在 14 项测试通过后复制。

如果要让 GitHub Actions 在推送后执行独立真实编译检查，再显式执行第二步：

```bash
bash development/RefractionCore-v8/ci/install-workflow-GitBash.sh
```

它仅在 `.github/workflows/gf-refractioncore-v8.yml` **不存在时**创建并暂存；存在则停止，不覆盖其他 CI。然后先检查 `git --no-pager diff --cached --stat` 和 `git -c core.whitespace=cr-at-eol diff --cached --check`，由用户决定是否提交/推送。这些步骤**不会在本地安装或修改运行中的插件**。

## GitHub Actions：两条独立编译关卡

工作流是 `ci/gf-refractioncore-v8.yml`（需用上述第二步放到仓库根 `.github/workflows` 才会被 GitHub 识别）。支持手动运行 `workflow_dispatch`；源码/工作流路径变更的 push 或 PR 也可触发。

- **Apple 编译**：macOS 15 runner / Xcode，运行 CPU 测试；用 Apple `metal` 编译 `.metal` 并链接 `.metallib`；用 iPhoneOS SDK 编译 Objective-C++ C++17 两个 `.mm` 文件并链接独立 ARM64 dylib；再编译独立 macOS GPU smoke 工具，但**不会在没有确认 Metal GPU 的 runner 上声称已经执行 GPU smoke**。
- **Theos 编译**：macOS 15 runner，拉取官方 Theos，`make -C development/RefractionCore-v8 ARCHS=arm64` 构建独立 dylib；不安装 RootHide scheme、不制作 `.deb`、不注入系统进程。RootHide、arm64e 与 iPadOS 具体 ABI 仍需要另行验证。

独立在具备 Xcode 的 Mac 上可运行：

```bash
bash tools/verify-apple-build.sh
bash tools/verify-macos-smoke-build.sh
GF_RUN_GPU_SMOKE=1 bash tools/verify-macos-smoke-build.sh
```

第三行会真正执行 macOS GPU smoke；若无可用 GPU，程序退出码为 77，代表**未测**而非通过。可选 `GF_VERIFY_ARM64E=1 bash tools/verify-apple-build.sh` 仅检查目标工具链对 arm64e 链接的支持，不能证明 RootHide 运行兼容。

**Xcode 26 及更新环境可能缺少独立 Metal Toolchain**；若 Metal 编译提示缺失，可以在 macOS 用 Apple 官方命令 `xcodebuild -downloadComponent metalToolchain` 安装，随后重跑。这个动作不会在 Linux 上自动伪装成功。

## 独立 GPU smoke（合成输入，不是系统采样）

`tools/gpu-smoke.mm` 从 Metal 设备创建 400×300 RGBA 渐变纹理，计算 128×96 透明边缘输出，检查命令缓冲完成、中心/外角透明、边缘非透明、预乘 Alpha，并对比有折射位移与无位移输出的像素差异。在 macOS Metal 设备或单独构建的 iPad 调试工具上执行，才可记录真实 GPU 证据。`Makefile.smoke` 提供独立 Theos 测试命令行目标，但绝不注入系统；**只编译不算已运行**。

## 真正实时折射仍然缺少的输入

当前 `GFBackboardLiveFrameBridge` 要求可信 adapter 提供：

- 不依靠系统视图截图的**实际合成器背景 MTLTexture**，可以证明帧来自实时合成路径；
- 输出到目标 App 资源库左上角单张卡片的可显示、可合成的纹理和负责提交的 Metal command buffer；
- `cardRectInScreenPixels`，真实 `screenPixelsPerPoint`，屏幕到纹理映射仿射矩阵与平移量，以及严格递增的 `liveFrameSequence`；
- 确认输入与输出是同一 Metal 设备，且在采样期间纹理没有被重用/释放。

目前没有用户固件版本、RootHide 渲染接口、已验证的纹理采集链路或 CARenderServer 滤镜注册证据。`verifiedCompositorBackdrop=YES` **只是可信调用方的声明，不是本类能够认证系统帧的证据**。不要猜测 Hook 地址、注入 `backboardd` 或拷贝第三方闭源代码。待确认真实合成帧渠道后，先仅测试 App 资源库**左上角第一张卡片 15–17pt 圆角**，提供卡片静态与背景动态的视频/帧日志及关闭后恢复的证据，再考虑扩展其他卡片、搜索框。

## 具体验收顺序

1. 工作流两个 job 分别绿灯且提供编译 log（这是编译验证，不是视觉验收）。
2. 在实际 Apple Metal 设备的合成纹理上跑 GPU smoke，确认有位移/无位移出现真实像素差异。
3. 找到**经 iPadOS/RootHide 固件与安全回退验证**的实时 compositor MTLTexture 来源，记录动态背景内容与帧序号。
4. 第一张卡片经过固定 16pt 圆角边缘与实时背景验证后，才修改生产插件和制作 `.deb`；绝不能仅靠边缘发白或模糊判定折射成功。

## v8.0.2 针对 Windows Git Bash 报错的复盘

用户运行旧版 `install-GitBash.sh` 时，`test_render` 在 `import numpy` 处失败，旧版的 `set -e` 直接终止，因此 `development/RefractionCore-v8` 并未创建，接着执行 workflow 安装自然出现 `No such file or directory`。本版仅修复**测试依赖/安装体验**，未声称产生任何设备端视觉提升。

**Windows 命令（使用新的 ZIP 解压目录）**：

```bash
cd "/g/AITEST/GlassFolders 1.0/GlassFolders-v7-2-work" || exit 1
bash "$HOME/Downloads/GlassFolders-RefractionCore-v8.0.2/install-GitBash.sh" && \
  bash development/RefractionCore-v8/ci/install-workflow-GitBash.sh
git --no-pager diff --cached --stat
```

在 Git Bash 中若 `python3` 映射到错误的解释器，可运行 `python3 --version` 和 `python --version` 检查。已保留旧版安全规则：存在 `development/RefractionCore-v8` 时会明确停止，不覆盖现有源码。若是旧 ZIP 的第一次测试失败，该目录一般尚未生成。
