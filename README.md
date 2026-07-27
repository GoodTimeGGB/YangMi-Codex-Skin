# YangMi Codex Skin

一套 Codex 桌面端本地皮肤包，以及一只带状态动画的绿色小蜜蜂宠物。

![Codex 工作区最终效果](docs/assets/yangmi-codex-skin-article/final-codex-workspace.png)

## 功能

- 四套主题：花漾复古、白衣林间、婚纱月光、雅黑银灰。
- Windows 和 macOS 的应用、验证、恢复脚本。
- 可直接覆盖的自定义背景入口。
- 杨幂风格绿色小蜜蜂宠物的精灵图、动画帧与 GIF 预览。

## Windows 快速使用

1. 下载并解压本仓库。
2. 打开 `skin-package/windows/`。
3. 双击一个 `Apply-*.cmd`，例如 `Apply-白衣林间.cmd`。
4. 恢复默认外观时，双击 `Restore-默认外观.cmd`。

皮肤不会修改 `WindowsApps`、`app.asar` 或 Codex 安装包。

## 换自己的背景

1. 准备一张真实的 JPEG 图片。
2. 覆盖 `skin-package/assets/custom-background/background.jpg`。
3. 文件名保持为 `background.jpg`。
4. 再运行一次想使用的 `Apply-*.cmd`。

不要只把 WebP 或 PNG 改名为 `.jpg`，图片实际格式必须是 JPEG。

## 宠物资源

`pet-runs/yangmi-green-bee/` 中保留了完整制作过程：

- `final/`：最终精灵图和校验结果。
- `frames/`：按状态拆分的动画帧。
- `qa/previews/`：左右拖动、悬停、等待和任务执行等 GIF 预览。
- `prompts/` 和 `pet_request.json`：制作参数及状态语义。

| 向左拖动 | 执行任务中 |
| --- | --- |
| ![向左拖动](docs/assets/yangmi-codex-skin-article/pet-drag-left.gif) | ![执行任务中](docs/assets/yangmi-codex-skin-article/pet-processing.gif) |

## 项目结构

```text
assets/         有语义命名的原始参考图
docs/           项目复盘文章、设计与效果图
pet-runs/       宠物精灵图、动画帧、预览与制作参数
site/           可部署到 Cloudflare Pages 的静态介绍页
skin-package/   可应用的皮肤包、主题素材与测试
```

## 相关链接

- [项目复盘与使用指南](docs/YangMi-Codex-Skin-项目复盘与使用指南.md)
- [在线介绍页](https://goodtimeggb.github.io/YangMi-Codex-Skin/)（GitHub Pages 部署完成后生效）

## 资源说明

仓库包含用于主题与宠物制作的图片参考。发布、转载或二次分发前，请自行确认人物肖像、图片素材和平台规则的授权范围。
