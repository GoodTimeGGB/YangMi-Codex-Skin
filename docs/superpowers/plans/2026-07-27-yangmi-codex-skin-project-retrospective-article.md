# 杨幂 Codex 皮肤项目复盘文章实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 生成一篇可直接发布到博客或仓库的中文项目复盘与使用指南。

**Architecture:** 正文采用“制作故事 + 可复用操作”的双线结构。所有图片采用仓库相对路径或明确占位，外部仓库使用 GitHub、Gitee、GitCode 链接占位，避免写入尚未创建的 URL。

**Tech Stack:** Markdown、仓库已有 PNG/GIF/WebP 图片资产。

---

### Task 1: 整理文章素材引用

**Files:**
- Read: `skin-package/themes.json`
- Read: `skin-package/assets/custom-background/README.txt`
- Read: `pet-runs/yangmi-green-bee/qa/run-summary.json`
- Read: `docs/superpowers/plans/2026-07-23-launcher-race-and-pet-overlay.md`

- [ ] **Step 1: 提取主题、背景和宠物的可验证事实**

确认文章只陈述下列事实：四套主题、`background.jpg` 的 JPEG 要求、宠物已生成并安装、独立 `avatar-overlay` 窗口不应注入皮肤、启动器通过回环 CDP 连接。

- [ ] **Step 2: 确定图片引用**

正文使用以下图片位置：

```markdown
![最终宠物联系表](../pet-runs/yangmi-green-bee/qa/contact-sheet.png)
![宠物等待动画](../pet-runs/yangmi-green-bee/qa/previews/waiting.gif)
```

主题效果、最终工作区和问题修复前后的截图使用明确的待补充占位，避免引用临时剪贴板文件。

### Task 2: 编写可发布的中文正文

**Files:**
- Create: `docs/YangMi-Codex-Skin-项目复盘与使用指南.md`

- [ ] **Step 1: 写入标题、摘要和封面截图占位**

标题应为“把 Codex 变成自己的工作空间：杨幂风格皮肤与动画宠物制作复盘”。摘要说明项目提供四套主题、可替换背景和独立动画宠物。

- [ ] **Step 2: 写入制作故事与踩坑复盘**

分别描述背景层、宠物精灵图、重复注入器、`avatar-overlay` 误注入、监控器身份校验、WebP 改名 JPEG 失败。每个问题要说明症状、根因和最终的工程约束。

- [ ] **Step 3: 写入用户应用步骤**

给出 Windows 下运行 `Apply-*.cmd`、切换主题、替换 `assets/custom-background/background.jpg`、恢复默认外观的准确步骤。明确背景文件必须为真实 JPEG。

- [ ] **Step 4: 写入仓库链接与发布说明**

加入以下可替换链接：

```markdown
- GitHub: [待补充](https://github.com/<your-account>/YangMi-Codex-Skin)
- Gitee: [待补充](https://gitee.com/<your-account>/YangMi-Codex-Skin)
- GitCode: [待补充](https://gitcode.com/<your-account>/YangMi-Codex-Skin)
```

### Task 3: 校对发布内容

**Files:**
- Read: `docs/YangMi-Codex-Skin-项目复盘与使用指南.md`

- [ ] **Step 1: 检查读者路径**

确认普通用户无需理解注入实现即可完成下载、可选替换背景、双击应用和恢复默认外观。

- [ ] **Step 2: 检查技术边界**

确认正文没有声称修改 `WindowsApps`、`app.asar`、宠物内部实现或任何远程服务。

- [ ] **Step 3: 检查 Markdown 链接与占位**

运行：

```powershell
rg -n "TODO|TBD|file://|WindowsApps|app\.asar" docs\YangMi-Codex-Skin-项目复盘与使用指南.md
```

预期：仅出现说明“不修改 `WindowsApps` 或 `app.asar`”的安全边界；不出现 `TODO`、`TBD` 或 `file://`。
