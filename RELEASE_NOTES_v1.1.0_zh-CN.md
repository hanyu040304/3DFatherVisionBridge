# Fusion Spatial v1.1.0 更新说明

## 新增功能

- 新增 Blender Connector，可将当前 Blender 场景导出并发送到 Apple Vision Pro。
- 新增 Current Source 自动判断：Fusion 360 与 Blender 同时运行时，发送最近使用的受支持 3D 软件。
- 新增系统级全局快捷键，默认 `⌃⌥V`；主窗口关闭后仍可发送当前模型。
- 新增 Menu Bar 菜单，可查看 Fusion 360、Blender、Vision Pro 和当前来源状态。
- 新增后台运行与从 Menu Bar 重新打开主窗口。

## 界面改进

- Connector 改为可选择卡片，Fusion 与 Blender 管理操作按上下文显示。
- Sidebar 和主内容区支持滚动，改善小窗口、全屏和不同窗口尺寸下的显示。
- Hero、发送按钮和性能状态栏改为响应式布局。
- 补充中英文状态文案和 Blender Menu Bar 状态。

## 修复

- 修复快捷键录制时由不连续 Virtual Key Code 范围导致的崩溃。
- 修复 Xcode Build Script Sandbox 阻止 Connector 资源复制的问题。
- 防止发送过程中重复触发多个并行导出任务。

## 安装提示

- Fusion Connector 可在 App 内安装或修复，安装后需要重新启动 Fusion 360。
- Blender Connector 可在 App 内安装；随后在 Blender 的 Preferences → Add-ons 中启用 `Fusion Spatial Blender Connector`。
- 使用 SpatialPreview 前，请先通过 Mac Virtual Display 连接 Apple Vision Pro。

## 发布说明

本次生成的 DMG 未使用 Developer ID 签名或 Apple 公证。手动分发测试时，macOS 可能显示安全提示。
