# 图览 ImageBrowser

原生 iOS 图片浏览 App（SwiftUI，无任何网页壳）。

## 功能

- **相册**：浏览系统相册（按拍摄时间倒序），网格缩略图 + 全屏查看
- **全屏查看**：左右滑动翻页、双指缩放、双击放大/还原；底部「详情 + 分享」
- **超详细详情**：文件名 / 类型 / 尺寸与百万像素 / 宽高比 / 大小 / 拍摄时间 / 修改时间 / 所在相册 / 拍摄位置 / 资源类型；图片含 Exif（设备型号、光圈、快门、ISO、焦距、曝光补偿、色彩配置），视频含时长；读取中显示加载态
- **视频查看**：我的图片、文件夹映射中的视频（mp4/mov/m4v/3gp）缩略图 + 播放角标，点击 AVPlayer 全屏播放
- **我的图片**：右上角文件夹按钮 → 系统文档选择器（原生 UIDocumentPicker，稳定不跳 Tab）导入图片/视频到 App 沙盒（Documents/Images），网格浏览、全屏查看、长按删除
- **文件夹（正规本地挂载映射）**：右上角 + → 系统文档选择器选择本地文件夹（真正支持选文件夹），安全作用域（security-scoped resource）直接映射访问真实目录——**文件不复制**；进入子目录、返回上级、手动刷新；bookmark 持久化，重启自动恢复
- **局域网映射（IP 访问）**：App 内启动局域网 HTTP 服务，显示 `http://127.0.0.1:端口` 与手机局域网 IP；电脑浏览器浏览/下载/上传（PUT）「我的图片」
- **App 图标**：内置蓝紫渐变 + 照片卡片 + 放大镜图标（Assets.xcassets）
- 相册内容变化自动刷新；权限被拒绝时跳转设置引导

> 说明一：iOS 出于沙盒机制，App 无法像桌面系统那样“全局挂载”任意路径，而是通过系统文件选择器授予对所选文件夹的安全作用域访问——这就是 iOS 上的正规挂载映射方式，权限由系统管理、可持久化。
>
> 说明二：“IP 映射”在 iOS 上的正规形态是 App 内置局域网服务（如本项目的局域网映射），127.0.0.1 为本机回环地址，电脑访问需使用手机局域网 IP（同一 Wi-Fi 下）。

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
│   ├── FolderView.swift             # 文件夹挂载管理 + 目录浏览（含视频）
│   ├── LocalServer.swift            # 局域网 HTTP 服务（IP 映射）
│   ├── DocumentPicker.swift         # 系统文档选择器包装（选文件/选文件夹）
│   ├── Assets.xcassets              # App 图标资源
│   ├── ActivityView.swift           # 系统分享面板
│   ├── SharedViews.swift            # 权限引导 / 视频缩略图与播放 / 超详细详情
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
