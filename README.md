# PhotoViewer - iOS 图片/视频查看器

一个基于 WKWebView 打包本地网页应用的 iOS 原生应用，支持图片浏览、视频播放、文件夹挂载等功能。

## 功能特性

- 🖼️ **图片浏览**：网格视图、全屏查看、双指缩放、左右滑动切换
- 🎬 **视频播放**：全屏播放器、播放/暂停、进度拖动、全屏模式
- 📁 **文件夹挂载**：从 iOS「文件」App 选择文件夹，自动读取其中所有图片和视频，持久缓存
- ⭐ **收藏功能**：标记喜欢的媒体文件
- 💾 **本地保存**：保存图片/视频到系统相册
- 🎨 **iOS 原生体验**：毛玻璃导航栏、底部工具栏、启动页、App 图标

## 系统要求

- iOS 14.0+
- Xcode 14.0+
- macOS 12.0+（编译环境）

## 编译安装步骤

### 方法一：Xcode 自动签名（推荐，最简单）

1. **解压项目**：双击 `PhotoViewer.zip` 解压
2. **打开项目**：双击 `PhotoViewer.xcodeproj`，用 Xcode 打开
3. **选择开发者团队**：
   - 点击左侧项目导航栏最上方的 `PhotoViewer`（蓝色图标）
   - 选择 `Signing & Capabilities` 标签页
   - 在 `Team` 下拉菜单中选择你的 Apple ID 开发者团队
   - 如果没有，点击 `Add Account...` 登录你的 Apple ID（免费账号也可以）
4. **修改 Bundle Identifier**（可选，避免冲突）：
   - 在 `Signing & Capabilities` 页面，把 `Bundle Identifier` 改成你自己的，比如 `com.yourname.photoviewer`
5. **连接手机**：用数据线把 iPhone 连接到 Mac，在手机上点击「信任此电脑」
6. **选择目标设备**：Xcode 顶部工具栏，选择你的 iPhone（而不是模拟器）
7. **运行安装**：按 `Cmd + R` 或点击左上角的播放按钮 ▶️
8. **信任开发者**：
   - 安装完成后，手机上会出现 App 图标，但点击会提示「未受信任的企业级开发者」
   - 打开手机 `设置` → `通用` → `VPN与设备管理` → 点击你的 Apple ID → 点击「信任」
9. **完成**：现在可以正常打开 App 了

### 方法二：导出 IPA 后自签

1. 用 Xcode 打开项目
2. 菜单栏选择 `Product` → `Archive`
3. 归档完成后，在 Organizer 中选择 `Distribute App`
4. 选择 `Development` 或 `Ad Hoc`，按提示导出 IPA
5. 使用你常用的自签工具（AltStore、TrollStore、Sideloadly 等）安装 IPA

## 项目结构

```
PhotoViewer/
├── PhotoViewer.xcodeproj/     # Xcode 项目文件
│   └── project.pbxproj
├── PhotoViewer/                # 源代码目录
│   ├── AppDelegate.swift       # 应用入口
│   ├── ViewController.swift     # 主视图控制器（WKWebView）
│   ├── Info.plist              # 应用配置
│   ├── Assets.xcassets/        # 资源目录（图标等）
│   │   ├── AppIcon.appiconset/
│   │   └── Contents.json
│   ├── Base.lproj/
│   │   └── LaunchScreen.storyboard  # 启动页
│   └── web/
│       └── index.html          # 网页应用（核心功能）
└── README.md
```

## 自定义修改

### 修改 App 名称
- 打开 `Info.plist`，修改 `CFBundleDisplayName` 的值

### 修改 App 图标
- 把你的图标图片（1024x1024 PNG）拖入 `Assets.xcassets` 的 `AppIcon` 中

### 修改启动页
- 打开 `Base.lproj/LaunchScreen.storyboard`，在 Xcode 中可视化编辑

### 修改网页应用功能
- 编辑 `PhotoViewer/web/index.html`，所有功能都在这个单文件中

## 注意事项

1. **免费 Apple ID 签名有效期 7 天**：7 天后需要重新用 Xcode 安装一次（AltStore 可以自动续签）
2. **视频格式**：iOS 原生支持 mp4（H.264/H.265）和 mov，其他格式（mkv、avi 等）可能无法播放
3. **存储限制**：挂载的媒体文件存储在 App 的沙盒中，卸载 App 会清除所有数据
4. **文件夹刷新**：由于 iOS 沙盒限制，网页无法后台监控文件夹变化，新增文件需要手动点「刷新」重新选择

## 技术栈

- **原生层**：Swift 5 + UIKit + WKWebView
- **网页层**：原生 HTML/CSS/JavaScript（单文件，无框架依赖）
- **数据存储**：IndexedDB（浏览器端持久化）

## 许可证

MIT License - 自由使用、修改、分发
