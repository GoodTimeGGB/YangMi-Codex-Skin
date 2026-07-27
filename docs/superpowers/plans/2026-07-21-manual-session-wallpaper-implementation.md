# 杨幂 Codex 手动会话壁纸皮肤实施计划

> **供实施代理使用：** 必须逐项执行本计划，并使用 `superpowers:test-driven-development` 完成每个 RED → GREEN 循环；开始声称完成前必须使用 `superpowers:verification-before-completion`。

**目标：** 删除杨幂皮肤的 Windows 自启与后台 Codex 接管行为，把“白衣林间”改为右侧工作区壁纸，同时保留手动启动器的一次点击启用体验。

**架构：** Windows 手动启动器负责唯一一次显式启动或重启，并建立仅限当前会话的 CDP、注入器和 watcher。watcher 只维护已经由启动器建立且身份可验证的会话；验证程序以“无自启后端”为正确状态，恢复程序继续用严格身份校验清理当前会话及旧版遗留物。渲染器仍只创建两个不可交互的装饰节点，图片层限制在右侧工作区。

**技术栈：** PowerShell 5.1、Node.js 22+、ES Modules、Chrome DevTools Protocol、基于源码 AST/文本与真实 payload 的契约测试。

---

## 文件职责与改动范围

- `skin-package/windows/apply-yang-mi-skin.ps1`：保留用户显式启动/重启和当前会话创建，删除所有自启安装及相应事务回滚。
- `skin-package/windows/watch-yang-mi-skin.ps1`：只协调当前 CDP 会话和注入器；没有 CDP 时记录阻塞状态，不停止、启动或重启 Codex。
- `skin-package/windows/verify-yang-mi-skin.ps1`：把两个自启后端都不存在作为通过条件，不因 Scheduler API 不可用而要求建立持久化。
- `skin-package/windows/restore-yang-mi-skin.ps1`：清理严格验证的旧自启后端、当前会话进程和孤立启动器文件。
- `skin-package/shared/injector.mjs`：生成右侧工作区 `cover / no-repeat / right center` 壁纸 CSS，去除全窗 wash。
- `skin-package/tests/test-autostart-contract.ps1`：锁定 apply 不得安装自启，同时保留旧自启的安全识别与卸载测试。
- `skin-package/tests/test-watcher-contract.ps1`：锁定 watcher 不得含 Codex stop/start/takeover 路径。
- `skin-package/tests/test-verify-contract.ps1`：锁定验证语义为两种自启后端均不存在。
- `skin-package/tests/test-renderer-payload.mjs`：锁定壁纸尺寸、定位、范围和不可交互边界。
- `skin-package/SKILL.md` 与安装目录副本：更新用户说明为“每次手动点击一次、无系统自启”。

### 任务 1：禁止 apply 安装 Windows 自启

**文件：**
- 修改：`skin-package/tests/test-autostart-contract.ps1`
- 修改：`skin-package/windows/apply-yang-mi-skin.ps1`

- [ ] **步骤 1：先写失败契约**

在自启契约测试末尾读取 apply 源码，并增加以下断言：

```powershell
$applyText = [System.IO.File]::ReadAllText($applyPath)
Assert-False ($applyText -match '\$autostartInstaller') 'Manual apply must not reference the autostart installer.'
Assert-False ($applyText -match 'install-yang-mi-autostart\.ps1') 'Manual apply must not install Windows startup persistence.'
Assert-False ($applyText -match '\$autostartInstallAttempted') 'Manual apply rollback must not manage autostart installation.'
```

- [ ] **步骤 2：运行测试并确认 RED**

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skin-package/tests/test-autostart-contract.ps1
```

预期：FAIL，错误明确指出 apply 仍引用 `autostartInstaller` 或 `autostartInstallAttempted`。

- [ ] **步骤 3：完成最小实现**

从 apply 中删除 `$autostartInstaller`、`$autostartUninstaller`、`$autostartInstallAttempted`，删除安装器调用和只为自启安装服务的 catch 回滚分支。保留 settings/session 的事务快照以及本次新建 injector/watcher 的身份校验回滚。

- [ ] **步骤 4：运行测试并确认 GREEN**

重复步骤 2 的命令。预期：PASS，且旧自启身份识别/卸载测试仍通过。

### 任务 2：禁止 watcher 接管 Codex，并绑定当前会话生命周期

**文件：**
- 修改：`skin-package/tests/test-watcher-contract.ps1`
- 修改：`skin-package/windows/watch-yang-mi-skin.ps1`

- [ ] **步骤 1：先写失败契约**

新增源码 AST/文本断言，禁止 watcher 定义或调用接管函数：

```powershell
$watcherText = [System.IO.File]::ReadAllText($watcherPath)
foreach ($forbidden in @(
  'Stop-YangMiFreshCodexSnapshot',
  'Stop-YangMiCapturedCodexSnapshot',
  'Wait-YangMiLaunchedCodexSnapshot',
  'Start-DreamSkinCodex'
)) {
  Assert-False ($watcherText -match [regex]::Escape($forbidden)) "Watcher must not contain Codex takeover path: $forbidden"
}
```

另增加循环退出契约：当 `Get-DreamSkinCodexProcesses` 返回空集合时，watcher 在清理精确匹配的 injector、写入 `idle` 后结束当前 watcher，不再永久轮询。

- [ ] **步骤 2：运行测试并确认 RED**

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skin-package/tests/test-watcher-contract.ps1
```

预期：FAIL，至少命中 `Stop-YangMiFreshCodexSnapshot` 或 `Start-DreamSkinCodex`。

- [ ] **步骤 3：完成最小实现**

删除 fresh-launch、captured snapshot、等待新启动进程以及 recovery relaunch 函数和调用。`Reconcile-YangMiSkin` 在 Codex 存在但找不到已验证 CDP 时只写入：

```powershell
$session = Set-YangMiSkinSessionStatus -Session $session -Status 'blocked' -BlockedReason 'verified-loopback-cdp-unavailable'
Save-YangMiWatcherSession -Session $session
return
```

让 reconcile 返回是否继续监视；Codex 已关闭时返回 `$false`，主循环据此退出。watcher 只能停止身份完整匹配的杨幂 injector，不得对 Codex 进程调用 `Stop-Process`。

- [ ] **步骤 4：运行测试并确认 GREEN**

重复步骤 2 的命令。预期：PASS，watcher 源码中不存在任何 Codex 启停路径。

### 任务 3：验证和恢复以“无自启”为正确状态

**文件：**
- 修改：`skin-package/tests/test-verify-contract.ps1`
- 修改：`skin-package/tests/test-autostart-contract.ps1`
- 修改：`skin-package/windows/verify-yang-mi-skin.ps1`
- 检查并按需修改：`skin-package/windows/restore-yang-mi-skin.ps1`

- [ ] **步骤 1：先写 verifier 失败契约**

`-WhatIf` 输出必须明确报告：

```powershell
Assert-True ($report.autostart.scheduledTask.exists -eq $false) 'Verification requires no scheduled task.'
Assert-True ($report.autostart.hkcuRun.exists -eq $false) 'Verification requires no HKCU Run value.'
Assert-True ($report.autostart.pass -eq $true) 'Absent startup backends must pass verification.'
```

同时在源码契约中禁止 verifier 调用自启安装器，并要求 restore 仍调用严格身份校验的旧自启卸载器、删除 `$paths.WatcherLauncherPath`。

- [ ] **步骤 2：运行测试并确认 RED**

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File skin-package/tests/test-verify-contract.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File skin-package/tests/test-autostart-contract.ps1
```

预期：至少 verifier 契约 FAIL，因为旧实现仍要求选定一个已安装的自启后端。

- [ ] **步骤 3：完成最小实现**

将 verifier 的自启结果改成纯检查：精确任务不存在且精确 HKCU Run 值不存在时 `pass=true`；存在任何一个时 `pass=false` 并报告遗留后端。Scheduler 查询不可用时不得尝试安装；若无法可靠确认“缺失”，应保守地返回验证失败。restore 继续使用旧版严格身份函数删除确认归属本皮肤的注册和孤立 launcher，不扩大删除范围。

- [ ] **步骤 4：运行测试并确认 GREEN**

重复步骤 2 的两个命令。预期：两个测试均 PASS。

### 任务 4：把图片改成右侧工作区壁纸

**文件：**
- 修改：`skin-package/tests/test-renderer-payload.mjs`
- 修改：`skin-package/shared/injector.mjs`

- [ ] **步骤 1：先写失败视觉契约**

在 payload 检查中增加：

```javascript
assert.match(report.rendererCss, /background-size:cover/);
assert.match(report.rendererCss, /background-repeat:no-repeat/);
assert.match(report.rendererCss, /background-position:right center/);
assert.match(report.rendererCss, /left:max\(var\(--sidebar-width/);
assert.doesNotMatch(report.rendererCss, /\.ym-veil\{[^}]*inset:0[^}]*background:/);
assert.match(report.rendererCss, /pointer-events:none/);
```

测试仍须确认只有 `ym-veil`、`ym-portrait` 两个节点，且 hero 只引用一次。

- [ ] **步骤 2：运行测试并确认 RED**

运行：

```powershell
node skin-package/tests/test-renderer-payload.mjs
```

预期：FAIL，因为旧 CSS 使用 `auto 100%` 简写并带全窗 `.ym-veil` wash。

- [ ] **步骤 3：完成最小实现**

让 `ym-portrait` 从右侧工作区中部开始，使用独立属性 `background-image`、`background-size:cover`、`background-repeat:no-repeat`、`background-position:right center`。让 `ym-veil` 只成为壁纸左边缘的窄融合带，不再 `inset:0` 覆盖全窗；保持根层和所有装饰节点 `pointer-events:none`。

- [ ] **步骤 4：运行测试并确认 GREEN**

重复步骤 2 的命令。预期：PASS。

### 任务 5：更新中文说明、同步安装副本并完成全量验证

**文件：**
- 修改：`skin-package/SKILL.md`
- 同步到：`C:/Users/Administrator/.codex/skills/yang-mi-codex-skins/`

- [ ] **步骤 1：更新说明**

Windows 说明必须写明：主题启动器是唯一入口；每个会话手动点击一次；不会创建计划任务或 HKCU `Run`；watcher 只维持本次会话且不启停 Codex；restore 会清理可验证的旧自启遗留。

- [ ] **步骤 2：运行全部 11 项测试**

依次运行 `skin-package/tests` 下 3 个 PowerShell 测试和 8 个 Node 测试：

```powershell
$psTests = Get-ChildItem skin-package/tests/test-*.ps1 | Sort-Object Name
$nodeTests = Get-ChildItem skin-package/tests/test-*.mjs | Sort-Object Name
foreach ($test in $psTests) { & powershell -NoProfile -ExecutionPolicy Bypass -File $test.FullName; if ($LASTEXITCODE -ne 0) { throw "FAIL: $($test.Name)" } }
foreach ($test in $nodeTests) { & node $test.FullName; if ($LASTEXITCODE -ne 0) { throw "FAIL: $($test.Name)" } }
```

预期：11/11 PASS，无错误或警告。

- [ ] **步骤 3：同步安装副本并复验**

只同步 `skin-package` 中已验证的技能文件到 `C:/Users/Administrator/.codex/skills/yang-mi-codex-skins`，随后从安装目录再次运行同一组 11 项测试。不得启动或重启 Codex。

- [ ] **步骤 4：清理已验证的旧遗留**

运行 restore 的受控旧自启清理路径，仅删除身份完全匹配的计划任务/HKCU Run 和 `%LOCALAPPDATA%/YangMiCodexSkin/watcher-launch.ps1`。保留 `identity-mismatch` 归档，不依据其 PID 杀进程，也不重启 Codex。

- [ ] **步骤 5：人工验收**

用户先确认普通 Codex 可正常启动；随后保存草稿并手动点击 `Apply-白衣林间.cmd`。检查右侧图片为 `cover` 壁纸、左侧导航不被覆盖、正文和工具可交互，关闭 Codex 后 watcher 自动结束且 Codex 不会被重新拉起。
