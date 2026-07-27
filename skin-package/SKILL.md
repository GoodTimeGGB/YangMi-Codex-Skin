---
name: yang-mi-codex-skins
description: "应用、切换、列出、验证、恢复或修复四款杨幂 Codex 桌面皮肤：花漾复古、白衣林间、婚纱月光、雅黑银灰。用户要求杨幂主题、切换主题、Windows/macOS 皮肤命令或恢复默认外观时使用。"
---

# 杨幂 Codex 皮肤

根据当前操作系统使用对应的平台适配器。主题必须从 `themes.json` 解析；支持的 ID 为 `floral-retro`、`woodland-white`、`bridal-moonlight` 和 `noir-silver`。

## Windows

每个需要皮肤的 Codex 会话都由用户手动双击对应的 `windows/Apply-*.cmd` 启动器一次。启动器是唯一启用入口：它不会创建计划任务、HKCU `Run` 值、登录启动器或其他系统启动项。

Codex 尚未运行时，启动器使用仅监听 `127.0.0.1` 的 CDP 端口启动 Codex。Codex 已运行但没有 CDP 时，启动器带有用户明确触发的 `-RestartExisting`，因此可能重启 Codex；操作前必须提醒用户保存草稿。后台 watcher 只维护这一次手动建立的会话，不得启动、停止或重启 Codex；Codex 关闭后 watcher 必须结束。

自动化应用命令为 `windows/apply-yang-mi-skin.ps1 -ThemeId <id> -RestartExisting`，只有用户明确授权重启当前 Codex 时才能使用 `-RestartExisting`。应用后可运行 `windows/verify-yang-mi-skin.ps1`；验证通过要求计划任务和 HKCU `Run` 两种旧自启后端都不存在。运行 `windows/restore-yang-mi-skin.ps1` 可移除当前皮肤层和身份完整匹配的会话进程，同时安全清理经过验证的旧版自启遗留及孤立 `watcher-launch.ps1`。

## macOS

实时应用前先运行 `macos/apply-yang-mi-skin.zsh --theme-id <id> --dry-run`。只有提醒用户保存草稿后才可使用 `--restart-existing`。应用后使用 `macos/verify-yang-mi-skin.zsh` 验证，使用 `macos/restore-yang-mi-skin.zsh` 清理状态。

## 安全约束

- 所有渲染装饰必须不可交互，不得替换 Codex 原生按钮或编辑器。
- 不得修改应用包、`WindowsApps`、`app.asar`、签名、线程、宠物、插件或认证。
- 实时注入必须使用 Node.js 22+ 和仅限回环地址的调试端点。
- 拒绝未知主题 ID。排查注入失败或跨平台切换前先执行恢复。
- 不得依据身份不完整或 `identity-mismatch` 归档中的 PID 终止进程。
