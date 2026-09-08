# 文件夹挂载 FolderMount（iOS）

一款通过**局域网 IP 直连**把远程文件服务器映射为本地文件夹的 iOS 应用。

受 iOS 沙盒机制限制，iOS 无法像桌面系统那样把网络共享"挂载"到系统文件系统；本应用的做法与 Documents、FE File Explorer 等一致——在应用内为每个服务器创建**挂载点**，连接后即可像本地文件夹一样浏览、下载、上传、重命名、删除远程共享中的文件。

## 功能

- **SMB 挂载**：连接 Windows 共享 / NAS（群晖、威联通、OpenMediaVault 等）/ macOS 共享，支持匿名与账号认证
- **WebDAV 挂载**：连接群晖 WebDAV、Nextcloud、坚果云、自建服务器
- **映射管理**：多个挂载点独立管理，状态一目了然（未连接 / 已挂载 / 连接中）
- **文件浏览器**：目录导航、面包屑、刷新、排序、文件大小与修改时间
- **文件操作**：下载到本地、上传、新建文件夹、重命名、删除、移动
- **传输队列**：串行下载 / 上传，实时进度，历史记录
- **安全**：密码保存在本机钥匙串（Keychain），映射配置仅存本机，凭据不随 iCloud 备份

## 技术栈

- SwiftUI，iOS 16.0+，iPhone / iPad
- 依赖：[AMSMB2](https://github.com/amosavian/AMSMB2)（Swift Package Manager 自动解析）
- WebDAV 客户端基于 URLSession 自实现（PROPFIND / GET / PUT / MKCOL / MOVE / DELETE）
- CI/CD：Codemagic（`codemagic.yaml`）

## 本地运行

```bash
open FolderMount.xcodeproj
```

在 Xcode 中选择 `FolderMount` scheme 与真机（SMB/局域网访问需要真机调试；模拟器无法访问宿主局域网共享时请用真机）。首次打开会自动解析 AMSMB2 依赖。

> 局域网 HTTP（非 TLS）访问依赖 Info.plist 中 `NSAllowsLocalNetworking`；首次访问局域网会触发系统本地网络权限弹窗，请允许。

## GitHub 推送

```bash
git init
git add .
git commit -m "Initial commit: FolderMount iOS"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

## Codemagic 构建（无签名直接打包）

1. 在 [codemagic.io](https://codemagic.io/start) 用 GitHub 登录并添加本仓库
2. 推送代码触发构建（workflow：`ios-unsigned-build`），**无需配置任何 Apple 证书**
3. 构建产物（在 Codemagic 构建页的 Artifacts 中下载）：
   - `FolderMount-unsigned.ipa`：无签名 IPA（Payload 结构）
   - `FolderMount.app`：无签名应用包
4. 说明：无签名产物不能直接安装到未越狱 iPhone（iOS 要求签名）。可用于：
   - 后续手动签名（自签工具 / 企业证书 / Ad Hoc）
   - 模拟器与调试用途
   - 需要签名安装包时，把 `ios_signing` 配置加回 `codemagic.yaml` 即可

## 项目结构

```
FolderMount/
├── FolderMount.xcodeproj        # Xcode 工程（含 AMSMB2 SPM 依赖）
├── FolderMount/
│   ├── FolderMountApp.swift     # 应用入口
│   ├── Models/                  # Mount / RemoteItem / TransferTask
│   ├── Services/                # SMB / WebDAV / Keychain / 本地文件 / 持久化
│   ├── ViewModels/              # 挂载列表 / 文件浏览 / 传输队列
│   ├── Views/                   # 挂载列表 / 编辑表单 / 文件浏览器 / 传输 / 设置
│   └── Support/
├── codemagic.yaml               # Codemagic CI/CD 配置
└── README.md
```

## 已知限制

- 传输队列为串行执行（单会话），适合常规文件管理场景
- SMB 协议基于 libsmb2（AMSMB2），SMB1 服务器不受支持
- 密码修改后需在编辑界面重新输入保存，否则沿用旧密码
