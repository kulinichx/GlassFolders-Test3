# GlassFolders iOS 16 — Optics Lab 02

本包基于你上传的 `feat/applibrary-native-backdrop-v7-2` **1.3.0 开发工作树**，不是 GitHub `main` 的 1.0.0 版本。

## 新内容

- 沿用 Optics Lab 01 的边缘微色散实验（默认关闭）。
- 添加 **边缘色散强度** 0–100% 独立滑块，仅 Liquid Glass 显示；默认 100%，与 Lab01 强度一致。
- **0% = 无色散**、**100% = 原 Lab01 色散**。注意仍然被已有的 Liquid Glass 强度共同缩放。
- 桌面文件夹和打开面板的缓存键包含色散强度，避免旧边缘图纹理不刷新。
- 单元测试增加无色散、部分色散、NaN 安全检查；独立 CI 验证算法与偏好结构。
- 现有 `build.yml` 也允许实验分支触发 Theos `.deb` 构建，无需合并到 `main` 就能检查真实编译。
- 不接入 Metal、`backboardd` 或第三方滤镜，暂不实现真实背景折射。

## 使用约束

- 先对比本地提交、未提交改动与 GitHub 分支，再决定如何应用补丁；**不要整包覆盖 `main`**。
- 补丁 `Lab01+02-from-uploaded-source.patch` 以最初上传的本地工作树为基准。
- 如果你的本地源码之后有过修改，先执行 `git apply --check`，失败就不要强行应用。
- 设置开关默认关闭，因而正常情况下两套材质的既有外观不变。

## 本地验证

```bash
cc -std=c11 -O2 -Wall -Wextra -Werror tests/test_prism_rim.c -lm -o /tmp/gf-prism-rim-tests
/tmp/gf-prism-rim-tests
```

> 源码静态/算法检查不等于 Theos 编译或 iOS 16 真机验证。这个版本仍需实验分支 GitHub Actions 编译验证后再设备测试。
