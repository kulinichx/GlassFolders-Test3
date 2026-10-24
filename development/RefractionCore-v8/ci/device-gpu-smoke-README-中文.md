# GlassFolders v8.0.4：iPad 真机 Metal GPU 验证

这是 **独立命令行测试程序**，不是 GlassFolders 插件、.deb、SpringBoard 注入器或实时系统背景捕获器。

## 当前所能证明的程度

1. GitHub Actions 绿灯：验证 Apple Metal 源码编译、iOS ARM64 可执行文件构建和 `ldid` 签名。
2. 在真实 iPad 上运行 `GFMetalSmoke` 并输出 `PASS: real GPU synthetic backdrop refracted`：验证 GPU 确实执行了 shader；测试背景是程序合成的图案，并非系统实时背景。
3. 只有另行获得合成器可信的实时背景纹理、关联坐标与输出呈现时，才可能验证 App 资源库的实时折射。此补丁不实现这些能力。

## 获取测试程序

GitHub → Actions → **GF v8 independent Metal compile gate** → 最新运行 → **Artifacts** → `gf-v8-ios-arm64-gpu-smoke`。

下载 artifact 压缩包并解出 `GFMetalSmoke-ios-arm64.zip`，然后解出其中唯一的 `GFMetalSmoke` 二进制文件。不要将它当作 `.deb` 安装，也不要放进 SpringBoard、backboardd 的注入配置中。

## 在越狱 iPad 上运行（只在你已经有终端/SSH 和可执行目录时操作）

通过现有的文件传输方式将 `GFMetalSmoke` 复制到 iPad 上有执行权限的用户目录（不同 RootHide 设备路径可能不同）。在 iPad 的终端进入该目录后执行：

```sh
chmod 755 ./GFMetalSmoke
./GFMetalSmoke
```

如出现 `PASS: real GPU synthetic backdrop refracted; changed_pixels=...; no compositor.`，才说明真机 GPU 的合成纹理折射测试成功。

若出现 `SKIP: Metal GPU unavailable`、`FAIL:`、`killed`、`Operation not permitted` 或 `not found`，请保留完整终端信息和设备 iPadOS/RootHide 版本。越狱环境的签名/执行权限问题与 shader 渲染错误须分开处理；不要因为 CI 成功就宣称真机已通过。

**安全性**：不修改 Tweak.xm、control、设置页、App 资源库卡片、原有授权文件；不请求系统实时合成纹理，不读取屏幕，不提交 iOS 安装包。
