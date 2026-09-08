# PhotoViewer - iOS 图片/视频查看器

一个基于 WKWebView 打包本地网页应用的 iOS 原生应用，支持图片浏览、视频播放、文件夹挂载等功能。

## 功能特性

- 🖼️ **图片浏览**：网格视图、全屏查看、双指缩放、左右滑动切换
- 🎬 **视频播放**：原生 AVPlayer 全屏播放（iOS 26 兼容）
- 📁 **文件夹挂载**：从 iOS「文件」App 选择文件夹，**安全作用域书签持久挂载，不复制文件、原位访问**（支持 iCloud 云盘按需下载）
- ⭐ **收藏功能**：标记喜欢的媒体文件
- 💾 **本地保存**：保存图片/视频到系统相册
- 🎨 **iOS 原生体验**：毛玻璃导航栏、底部工具栏、启动页、App 图标

## 系统要求

- iOS 14.0+（在 iOS 26 上经过针对性适配）
- Xcode 15.0+
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
│   ├── ViewController.swift    # 主视图控制器（WKWebView + 原生桥接 + AVPlayer）
│   ├── LocalHTTPServer.swift   # 本地回环 HTTP 服务（页面与媒体资源、Range 支持）
│   ├── MountedFolderStore.swift# 挂载书签持久化（安全作用域 Bookmark）
│   ├── NativeMountViewController.swift # "添加 本地"挂载配置页
│   ├── Info.plist              # 应用配置（ATS 本地网络）
│   ├── Assets.xcassets/        # 资源目录（图标等）
│   │   ├── AppIcon.appiconset/
│   │   └── Contents.json
│   ├── Base.lproj/
│   │   └── LaunchScreen.storyboard  # 启动页
│   └── web/
│       └── index.html          # 网页应用（核心功能）
└── README.md
```

## 本地挂载的实现原理（v3 / iOS 26）

| 环节 | 方案 |
| --- | --- |
| 选择文件夹 | 系统文件选择器 `UIDocumentPickerViewController`（.folder） |
| 持久授权 | 安全作用域书签（iOS 现行文档：`bookmarkData(options: .minimalBookmark)`），先 `startAccessing` 再生成书签；重启后 `resolvingBookmarkData` 还原 |
| 文件提供 | 本地回环 HTTP 服务（127.0.0.1:8765），支持 Range；**不复制文件、原位访问**，iCloud 文件按需下载 |
| 页面加载 | 网页从本地 HTTP 服务加载（与媒体同源，规避 iOS 26 自定义 scheme 兼容问题） |
| 视频播放 | 原生 `AVPlayerViewController`（点击查看器中的视频占位图唤起） |
| 视频缩略图 | 原生 `AVAssetImageGenerator` 生成，经 HTTP 提供给网页 |
| 导入文件 | 复制到 App 沙盒 `Documents/Imported/`，路径前缀 `__imports__/` |

> iOS 26 说明：自定义 URL Scheme（如 localapp://）配合 HTML5 视频在 iOS 26 存在兼容问题（媒体元素加载失败、含脚本页面触发 WebKit 终止），v3 已全部改为本地 HTTP + 原生播放，无需自定义 scheme。

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
2. **视频格式**：iOS 原生支持 mp4（H.264/H.265）和 mov，其他格式（mkv、avi 等）可能无法原生播放
3. **挂载不复制文件**：书签挂载的文件夹（我的 iPhone / iCloud）中的文件仍属于用户，卸载 App 只清除书签记录，不会删除用户文件
4. **删除媒体**：书签挂载目录内的文件归用户所有，App 不会删除；只有「导入」到 App 内的文件可以删除
5. **文件夹刷新**：由于 iOS 沙盒限制，网页无法后台监控文件夹变化，重新打开文件夹即可看到新增文件

## 技术栈

- **原生层**：Swift 5 + UIKit + WKWebView + Network.framework（本地 HTTP）+ AVKit（原生播放）
- **网页层**：原生 HTML/CSS/JavaScript（单文件，无框架依赖）
- **数据存储**：IndexedDB（网页层文件夹列表）+ UserDefaults（原生书签）

## 许可证

MIT License - 自由使用、修改、分发
