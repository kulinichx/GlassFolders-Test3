# GlassFolders 独立离线签发器

Windows 10/11，Windows PowerShell 5.1，无需安装 Python。界面为中文。正常签发不需要联网。

本目录是公开源代码，**不含正式私钥**。本次配置好的可用工具放在仓库外的 `G:\AITEST\GlassFolders 1.0\GlassFolders-Issuer`，双击其中 `GlassFolders签发器.exe` 使用。该图形启动器直接显示签发界面，不弹出 CMD 或 PowerShell 窗口；使用同级 `GlassFolders-Issuer-Private` 数据目录，不会重复生成密钥。

安装后的状态和手机/电脑逐步激活说明见仓库 `docs/安装状态与激活指南.md`。旧 `1.0.0-fix1.deb` 没有新增授权功能；新授权候选版首次安装未激活时不会启用玻璃效果。

## 1.1.1 时间修复

修复 Windows PowerShell 5.1 在北京时间下生成的绑定码时间早了 8 小时、手机立即提示“绑定码已过期或设备时间不正确”的问题。现在使用标准 Unix 时间，不受电脑时区影响。

关闭已打开的旧签发窗口，重新双击 `GlassFolders签发器.exe`，确认标题为 **1.1.1**，重新生成并发送绑定码，再由手机生成新的回执。旧绑定码和旧回执不能继续使用。此修复只更新电脑签发器，手机现有授权版 DEB 无需重装；保留现有私钥和记录即可。

## 使用

填入授权编号（1–64 位英文字母、数字、下划线或短横线）、用户名称（必填，最多 80 个字符）、联系方式 / 备注（选填，最多 240 个字符）和用户的完整 `GF-…` 设备码，按界面顺序完成“生成绑定码 → 验证设备回执 → 签发授权”。用户名称可以填写昵称，备注可以填写 QQ、微信或订单号。具体用户端步骤见仓库 `docs/离线授权与兼容性.md`。

界面 1.1 使用可调整大小的布局。小屏幕或放大显示时，操作区可以滚动，底部历史按钮与状态提示分别排列，不会相互遮挡。

## 授权历史与用户资料

点击“查看历史授权 / 用户资料”，可按用户名称、联系方式 / 备注、授权编号或设备码搜索。列表显示中文列名和本地签发时间；选中一条记录，下方可查看完整设备码、完整授权码，并点击“复制所选授权”。较长的列表内容可以横向滚动。

用户名称和联系方式 / 备注仅保存在电脑本地 `records.json`，不会写入发给手机的授权码。旧记录仍可正常读取，原本没有用户资料的记录可以在历史窗口补填，点击“保存用户资料”即可。修改这些资料不会改变原授权码，也不需要手机重新激活。用户资料是人工备注，不是身份认证。

绑定码五分钟内有效。验证通过后也必须在到期前签发。过期重新生成绑定码。一次绑定码只能签发一次，同一设备重新生成会替换旧绑定码。每次实际签发需要重新绑定；已签发的同一授权可以在历史中复制。

正式私钥与本次构建的 `GFLicensePublicKey.h` / `GlassFolders-public.txt` 对应。不要把 RC7 的私钥放入这里，也不要用本工具为 RC7 签发。不要把本机签发器目录、私钥和用户记录上传到 GitHub。

## 私钥和备份

- `issuer-key.dpapi`：Windows DPAPI CurrentUser 加密的 P-256 私钥。只对创建密钥的当前 Windows 用户及其受保护环境可用，不能当成可跨电脑的 PEM 文件。
- `records.json`：当前绑定状态、历史授权、用户名称和联系方式 / 备注；每次更新先备份旧文件为 `.backup`，再原子替换。备份仅是上一次状态，不能随意恢复，否则可能恢复已经消费的绑定码。
- `issuer.lock`：防止同一数据目录同时运行两个签发窗口。关闭程序后锁由系统释放，文件留存是正常现象。
- 备份整个私有数据目录，并保留当前 Windows 用户配置 / 系统的可恢复备份。**仅复制 `.dpapi` 到另一台电脑或新建账户通常无法恢复私钥**。迁移电脑或重装系统前应先规划经过验证的密钥迁移方案。不要通过重新初始化“修复”，新密钥不能验证旧版本授权。
- 所有公开源码和构建包只能包含公钥。安装包、公开源码和用户设备都不需要签发私钥。

## 自建全新产品密钥

本次已配置的正式签发器无需执行初始化。只有在有意创建全新产品密钥、愿意重新构建并接受与旧授权不兼容时，才在尚无任何公钥 / 私钥文件的目录初始化：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\GlassFoldersIssuer.ps1 -NoUI -InitializeKey -DataDirectory D:\GFPrivate -PublicKeyFile D:\GFPublic.txt -PublicHeader D:\GFLicensePublicKey.h
```

然后把新公钥文件和头文件放入源码的对应位置，重新构建插件。图形启动器优先使用同级 `GlassFolders-Issuer-Private`（其中有私钥时），否则使用自身目录中的 `private`；其他自定义路径可通过脚本参数 `-DataDirectory` 使用。初始化遇到已有公钥或私钥会拒绝覆盖。

## 无控制台启动器

`Launcher.cs` 为图形启动器源码，使用 Windows 自带 .NET Framework 构建：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-Launcher.ps1
```

生成 `GlassFolders签发器.exe`。它直接启动隐藏的 PowerShell 进程来运行现有签发界面，没有 CMD 中间窗口；启动失败显示提示框。发布时应将 EXE 与 `GlassFoldersIssuer.ps1`、`GFCrypto.cs`、`GlassFolders-public.txt` 放在一起。`调试启动.cmd` 仅供排错时查看输出。

`GlassFolders签发器.exe --check` 可在不显示签发界面的情况下检查控件创建、公私钥加载和退出状态，结果写入同目录 `launcher-check.log`。EXE 只负责启动，不包含签发私钥。

## 维护检查

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\GlassFoldersIssuer.ps1 -UISmokeTest -DataDirectory D:\GFPrivate
```

该检查创建界面控件并验证公私钥匹配，然后退出；不弹出窗口、不创建授权、不修改历史。完整自动检查在仓库 `tests/Test-Issuer.ps1`，另需 Node.js，用临时测试密钥运行。1.1.1 已通过 51 项检查，包含独立时钟校验、新绑定码的手机端时间条件、签名交叉验证和历史界面检查。

绑定回执是签名持有证明，不是 Apple 远程硬件认证。实现边界详见协议说明。
