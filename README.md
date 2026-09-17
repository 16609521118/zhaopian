# BookmarkMediaPlayer

与 **SenPlayer** 同款的 iOS 本地文件夹挂载实现：`UIDocumentPickerViewController` + Security-Scoped Bookmark。
播放器内核替换为 **MobileVLCKit**，支持 MP4 / MKV / AVI / TS / RMVB / WebM 等几乎所有常见编码。

## 功能
- 挂载「文件」App 中的本机 / iCloud Drive 任意文件夹（书签持久化，重启 App 仍可访问）
- 递归枚举目录下的视频文件
- VLC 内核播放，含进度条 / 播放暂停 / 时间显示
- 左滑删除挂载目录
- 与 SenPlayer 一样：**挂载目录仅在本 App 内可见**，不会出现在系统「文件」App 侧边栏（那是 Lumenic 的 FileProvider 方案）

## 目录结构
```
.
├── BookmarkMediaPlayer/
│   ├── BookmarkMediaPlayerApp.swift
│   ├── BookmarkManager.swift      # 核心：UIDocumentPicker + Bookmark
│   ├── ContentView.swift
│   ├── VLCPlayerView.swift         # MobileVLCKit 封装
│   └── Info.plist
├── Podfile                        # MobileVLCKit
├── project.yml                    # XcodeGen 工程定义
├── codemagic.yaml                 # CI：xcodegen → pod install → 无签名 archive
└── .gitignore
```

## 推送到 Git
```bash
git init
git add .
git commit -m "init: SenPlayer-style bookmark mount + VLC player"
git remote add origin <你的仓库地址>
git push -u origin main
```

## Codemagic 配置
1. 绑定 GitHub 仓库
2. 选择 workflow：`ios-unsigned-build`
3. 触发构建（约 15–25 分钟，主要耗时在下载 MobileVLCKit）
4. 产物：`build/BookmarkMediaPlayer-unsigned.ipa`

## 侧载安装
用 Sideloadly / AltStore / TrollStore 将无签名 IPA 安装到 iOS 设备。
- AltStore / Sideloadly：需要 Apple ID，7 天重新签名
- TrollStore（支持设备）：永久签名

## 本地开发（可选）
```bash
brew install xcodegen
xcodegen generate
pod install
open BookmarkMediaPlayer.xcworkspace
```

## 技术要点
- **挂载**：用户选目录 → 拿 `security-scoped URL` → 序列化成 `bookmarkData` 存 `UserDefaults` → 下次启动 `URL(resolvingBookmarkData:)` 恢复访问
- **播放**：MobileVLCKit 的 `VLCMediaPlayer`，`drawable` 绑定到一个普通 `UIView`
- **无签名**：archive 时传 `CODE_SIGNING_ALLOWED=NO`，手动打包 `Payload/` 为 IPA

## 已知限制
- iOS 15+
- 书签在被挂载文件夹移动 / 改名 / 被 iCloud 回收后会失效，需要重新挂载
- MobileVLCKit 体积较大（~600MB+），首次 CI 构建较慢
