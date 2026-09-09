# 图览 ImageBrowser

原生 iOS 图片浏览 App（SwiftUI，无任何网页壳）。

## 功能

- **相册**：浏览系统相册（按拍摄时间倒序），网格缩略图 + 全屏查看
- **全屏查看**：左右滑动翻页、双指缩放、双击放大/还原、分享、保存回相册
- **我的图片**：从系统相册导入图片到 App 沙盒（Documents/Images），本地网格浏览、全屏查看、长按删除
- **文件夹（正规本地挂载映射）**：通过系统文件选择器挂载用户本地文件夹，以安全作用域（security-scoped resource）直接映射访问真实目录——**文件不复制**，浏览的是原文件；支持进入子目录、返回上级、手动刷新；挂载记录用 bookmark 持久化，App 重启后自动恢复访问权限
- 相册内容变化自动刷新；权限被拒绝时提供跳转设置引导

> 说明：iOS 出于沙盒机制，App 无法像桌面系统那样“全局挂载”任意路径，而是通过系统文件选择器授予对所选文件夹的安全作用域访问——这就是 iOS 上的正规挂载映射方式，权限由系统管理、可持久化。

## 目录结构

```
ImageBrowser/
├── ImageBrowser.xcodeproj/          # Xcode 工程（含共享 scheme）
├── ImageBrowser/                    # 源码
│   ├── ImageBrowserApp.swift        # 入口
│   ├── ContentView.swift            # 主界面（Tab）
│   ├── LibraryViewModel.swift       # 相册数据层（权限/加载/图片请求/保存）
│   ├── LibraryView.swift            # 相册网格
│   ├── ImageDetailView.swift        # 全屏翻页查看
│   ├── ZoomableImageView.swift      # 缩放图片视图
│   ├── MyImagesView.swift           # 我的图片（导入/删除/查看）
│   ├── FolderViewModel.swift        # 文件夹挂载（security-scoped bookmark 持久化）
│   ├── FolderView.swift             # 文件夹挂载管理 + 目录浏览
│   ├── ActivityView.swift           # 系统分享面板
│   ├── SharedViews.swift            # 权限引导视图
│   └── Info.plist
├── codemagic.yaml                   # Codemagic 未签名 IPA 构建配置
└── README.md
```

## 环境要求

- iOS 16.0+
- Xcode 14+（工程以 Xcode 15 格式创建，objectVersion 56，兼容 14+）

## 在 Codemagic 构建未签名 IPA

1. 把本目录推送到 Git 仓库（GitHub / GitLab / Bitbucket）。
2. 在 Codemagic 添加应用并选择该仓库。
3. 构建方式二选一：
   - **推荐**：使用仓库自带的 `codemagic.yaml`，工作流名为 `unsigned-ipa`，直接产出未签名 IPA 产物 `ImageBrowser-unsigned.ipa`。
   - 或在 Codemagic 界面新建 iOS 工作流时把「Code signing」设为 **None**，构建后产物即为未签名 IPA。
4. 产物在 Artifacts 中下载。

> 说明：未签名 IPA 无法直接安装到普通 iPhone。可用于越狱设备侧载、交给签名工具（如 Apple Configurator、TrollStore、企业分发重签）做后续签名，或用于内部测试工具。

## 本地 Xcode 构建（可选）

```bash
open ImageBrowser.xcodeproj
```

真机调试需要选择自己的 Team 并签名；模拟器直接 Run 即可（模拟器不需要签名）。

## 常见调整

- **Bundle ID**：`ImageBrowser.xcodeproj` → target `ImageBrowser` → Build Settings 中修改 `PRODUCT_BUNDLE_IDENTIFIER`（当前为 `com.example.ImageBrowser`）。
- **版本号**：修改 `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`。
- **应用图标**：暂未配置 AppIcon，需要时在 Xcode 中新建 Asset Catalog 并拖入图标。
