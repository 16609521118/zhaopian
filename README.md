# 挂载播放器（LocalMountPlayer）

一个与 **SenPlayer「本地文件夹挂载」相同机制**的 iOS 视频播放器示例工程：
使用系统文件选择器选中文件夹 → 保存安全作用域书签（挂载）→ 之后免授权直接浏览、播放文件夹里的视频。

> 注意：iOS 沙盒不允许第三方 App 做真正的"文件系统级挂载"，SenPlayer 与本品都是
> **"系统授权 + 书签持久化"** 的方式，本质是 iOS 提供的安全作用域访问（security-scoped access）。

## 功能

- 右上角 **+** 调起系统文件选择器（文件夹模式），可挂载 iCloud Drive / 我的 iPhone / 外接存储中的任意文件夹
- 挂载列表持久化保存（存于 App 沙盒 Documents/mounted_folders.json），App 重启后仍有效
- 进入文件夹浏览子目录与文件，点击视频用系统播放器（AVPlayerViewController）直接播放
- 书签失效（重启设备 / 文件被移动改名等）时给出提示，删除后重新挂载即可

## 目录结构

```
LocalMountPlayer/
├── codemagic.yaml                     # Codemagic 不签名构建配置
├── LocalMountPlayer.xcodeproj/        # Xcode 工程（含共享 scheme）
├── LocalMountPlayer/
│   ├── AppDelegate.swift              # 程序入口（纯代码 UI，无 storyboard）
│   ├── MountedFolder.swift            # 挂载模型 + 书签持久化 + 安全作用域工具
│   ├── MountListViewController.swift  # 挂载列表 + 系统文件夹选择器
│   ├── FolderBrowserViewController.swift # 文件夹浏览 + 视频播放
│   ├── Info.plist
│   └── Assets.xcassets/
└── tools/gen_icon.py                  # 图标生成脚本（纯 Python，可重新生成）
```

## 挂载机制（与 SenPlayer 相同）

1. `UIDocumentPickerViewController(forOpeningContentTypes: [.folder])` 调起系统文件选择器
2. 选中文件夹后调用 `url.startAccessingSecurityScopedResource()` 建立访问权
3. 在访问权有效期内用 `bookmarkData(options: .minimalBookmark, ...)` 生成书签并持久化
4. 之后每次访问前解析书签 → 再次 `startAccessingSecurityScopedResource()` → 枚举目录读取文件
5. 离开时 `stopAccessingSecurityScopedResource()` 释放

## 本地构建（macOS）

```bash
xcodebuild \
  -project LocalMountPlayer.xcodeproj \
  -scheme LocalMountPlayer \
  -configuration Release \
  -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build
```

## 使用 Codemagic 不签名构建

1. 把本目录推送到 Git 仓库（GitHub / GitLab / Bitbucket 均可）
2. 在 [codemagic.io](https://codemagic.io) 登录并 **Add application**，选择你的仓库
3. 首次添加时选择项目类型为 **iOS App**（或直接触发 workflow）
4. 构建会自动使用 `codemagic.yaml` 中的 `ios-unsigned` workflow，产物为
   `LocalMountPlayer-unsigned.ipa`（未签名，可在构建日志的 Artifacts 中下载）
5. 之后每次 push 自动触发构建；也可在 Codemagic 界面上手动 **Start new build**

## 关于"不签名 IPA"的安装说明

未签名的 `.ipa` **不能直接在未越狱的 iPhone 上安装**，需要以下方式之一：

- **自签安装**：Sideloadly / AltStore / 爱思助手等工具，用你的 Apple ID 对 IPA 重新签名后安装（免费，7 天需重签）
- **越狱设备**：直接安装（无需签名）
- **企业证书 / 开发者证书**：若有，可在 Codemagic 配置正式签名后发布

如需改为签名构建，把 `codemagic.yaml` 中的 `ios_signing` 配置补上（或在 Codemagic 界面配置 Apple Developer 账号）即可。

## 常见问题

- **挂载的文件夹打不开 / 提示"挂载已失效"**：这是安全作用域书签被系统回收的典型表现
  （重启设备、文件提供商重新登录、文件夹被移动或改名、iCloud 同步变动等），
  删除后重新挂载即可 —— 这与 SenPlayer 更新日志中"修复-挂载本地文件夹不定期失效"是同一现象。
- **改 App 名字 / Bundle ID**：修改 `LocalMountPlayer.xcodeproj/project.pbxproj` 中
  `PRODUCT_BUNDLE_IDENTIFIER`（当前为 `com.example.LocalMountPlayer`）与
  `LocalMountPlayer/Info.plist` 中的 `CFBundleDisplayName`。
- **更多视频格式**：系统 AVPlayer 原生支持 mp4/mov/m4v/3gp，其它格式需自行接入第三方解码器（如 mpv/FFmpeg）。
