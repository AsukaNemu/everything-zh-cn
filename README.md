# Everything 简体中文一键汉化

为 [voidtools Everything](https://www.voidtools.com/) 便携版和安装版提供可回滚的简体中文部署脚本。

本项目不会修改 `Everything.exe`，只安装官方 `Everything.lng` 多语言包并将界面语言切换为简体中文（LCID `2052`）。安装前会记录原语言设置、备份已有语言包；卸载脚本可恢复原状。

## 支持范围

- Everything 1.4.1（已在 `1.4.1.1026 x64` 验证）
- Everything 1.5 Alpha
- Windows PowerShell 5.1 或 PowerShell 7+
- 安装版、便携版

## 使用方法

以 PowerShell 运行：

```powershell
git clone https://github.com/AsukaNemu/everything-zh-cn.git
cd everything-zh-cn
powershell -ExecutionPolicy Bypass -File .\scripts\Install-EverythingZhCn.ps1
```

脚本会依次从正在运行的 Everything、卸载信息和常见目录中寻找程序。便携版位置特殊时可显式指定：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-EverythingZhCn.ps1 -EverythingDir "D:\Tools\Everything"
```

恢复安装前状态：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Uninstall-EverythingZhCn.ps1 -EverythingDir "D:\Tools\Everything"
```

## 安全与隐私

- 不读取、上传或修改 `Everything.db`、搜索历史和运行历史。
- 不替换或修补可执行文件。
- 首次安装状态保存在 Everything 目录下的 `.everything-zh-cn` 中。
- 重复运行安装脚本是安全的，不会覆盖首次安装备份。
- 使用官方 Everything SDK 请求客户端保存设置并正常退出，避免管理员模式下卡在 UAC 提示。

## 项目结构

```text
assets/Everything.lng              官方多语言包
assets/sdk/                        官方 SDK（跨权限安全退出客户端）
scripts/Install-EverythingZhCn.ps1 安装与切换简中
scripts/Uninstall-EverythingZhCn.ps1 恢复原状态
scripts/Test-Package.ps1           离线自测
```

## 翻译与授权

简体中文翻译由 WanderMax 与 xbeta 维护，本项目只负责部署。Everything 及其语言包版权归原作者/贡献者所有，详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。本项目脚本使用 MIT License。

官方资源：

- [支持的语言](https://www.voidtools.com/support/everything/supported_languages/)
- [翻译说明](https://www.voidtools.com/support/everything/translating/)
- [Everything 下载](https://www.voidtools.com/downloads/)
