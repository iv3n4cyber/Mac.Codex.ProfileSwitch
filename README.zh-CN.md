# Mac.Codex.ProfileSwitch

[English](README.md) | [中文](README.zh-CN.md)

Mac.Codex.ProfileSwitch 是一个轻量级 macOS 菜单栏工具，用于管理多个 Codex Desktop Profile。

它可以在 OpenAI OAuth 账号和 OpenAI 兼容 Provider 配置之间切换，同时保持同一份 Codex 会话历史池，也就是继续使用 `~/.codex` 下的 sessions。

程序只会替换：

```text
~/.codex/auth.json
~/.codex/config.toml
```

程序不会移动或拆分：

```text
~/.codex/sessions
~/.codex/archived_sessions
```

## 功能

- macOS 菜单栏应用，支持快速切换 Profile
- 管理窗口，包含通用设置、Profile、备份和关于页面
- 首次运行时，可根据当前 `~/.codex/auth.json` 和 `~/.codex/config.toml` 自动登记第一个 Profile
- 支持 OpenAI OAuth 账号登录，并通过本地 callback 捕获授权结果
- OAuth 账号按 `account_id` 去重，重复登录会更新 token，不会重复创建 Profile
- 支持创建和编辑 OpenAI 兼容 Provider Profile
- 切换 Profile 时会自动备份原本正在使用的 `auth.json` 和 `config.toml`
- 所有 Profile 共享同一个 session 池，切换账号后仍可保留历史对话
- 菜单栏弹窗内支持刷新 OAuth 用量
- 菜单栏图标可显示紧凑的用量状态
- 支持统计本地 token 用量：今天、30 天、总量
- 鼠标悬停在用量摘要上时显示详细数据和 14 天 token 用量图表
- 支持英文和中文界面切换
- 提供 Codex 客户端重启快捷入口
- Backup 页面支持将 sessions、profiles、当前 auth/config 导出为 zip 备份

## 工作方式

Profile 以文件夹形式保存在：

```text
~/.codex/profiles/
```

每个 Profile 包含：

```text
auth.json
config.toml
```

切换 Profile 时，程序会：

1. 备份当前正在使用的 `auth.json` 和 `config.toml`。
2. 将所选 Profile 的 `auth.json` 和 `config.toml` 复制到 `~/.codex`。
3. 保持 `sessions` 和 `archived_sessions` 不变。
4. 在程序状态文件中记录当前 active profile。

程序自身的状态、备份和缓存保存在：

```text
~/.codex/mac-codex-profile-switch/
```

## 基本用法

### 启动

运行程序后，macOS 状态栏会出现一个菜单栏图标。

点击图标即可打开快速切换弹窗。

### 首次运行

如果还没有任何 Profile，并且程序检测到：

```text
~/.codex/auth.json
~/.codex/config.toml
```

它会自动将当前 Codex 配置登记为第一个 Profile。

OpenAI OAuth Profile 默认使用邮箱前缀命名。

Provider Profile 默认使用 provider host 命名。

### 添加 OAuth 账号

可以在菜单栏弹窗中点击 OAuth 按钮，或在管理窗口的 OAuth 分类旁点击绿色加号。

程序会在浏览器中打开 OpenAI OAuth 授权流程，捕获本地 callback，保存 token，并根据 `account_id` 自动去重。

### 添加 Provider

点击 Provider 添加按钮后，需要填写：

- Profile 名称
- Base URL
- API Key

添加 Provider 时不要求填写 model，model 可以在 Codex 中单独管理。

### 切换 Profile

菜单栏弹窗适合快速切换。

管理窗口中点击 Profile 时，会先弹出确认框，再执行切换。

### 查看用量

OAuth Profile 可以在菜单栏弹窗里显示当前 quota 用量。

程序也会扫描本地 Codex session 日志，统计 token 用量：

- 今天
- 最近 30 天
- 总量

鼠标悬停在 token 摘要上时，会显示详细 token 数据和 14 天用量图表。

### 备份数据

打开管理窗口，进入 Backup 页面。

先点击扫描，页面会预览：

- Sessions
- Profiles
- 当前 `auth.json` 和 `config.toml`

之后可以将任意一组导出为 zip 文件。程序会先让你选择保存位置，再创建压缩包。

## 数据位置

Codex 当前 active 文件：

```text
~/.codex/auth.json
~/.codex/config.toml
```

Profile 存储目录：

```text
~/.codex/profiles/
```

共享会话历史：

```text
~/.codex/sessions
~/.codex/archived_sessions
```

程序状态、备份和本地缓存：

```text
~/.codex/mac-codex-profile-switch/
```

## 隐私说明

本项目只处理你本机的 Codex 文件。

不要提交或公开：

- `auth.json`
- `config.toml`
- OAuth token
- API key
- `~/.codex/sessions`
- `~/.codex/archived_sessions`
- 生成的备份 zip

仓库中应只包含源代码和项目元数据。

## 运行要求

- macOS 14 或更高版本
- Swift 6 toolchain
- Codex Desktop 使用标准的 `~/.codex` 目录结构

## 技术栈

- Swift
- SwiftUI
- AppKit
- Swift Package Manager
- macOS 菜单栏 Status Item API
- 本地文件式 Profile 存储
- macOS 原生保存面板和文件打开能力
- 使用 `/usr/bin/ditto` 创建 zip 压缩包

项目不需要第三方 Swift package 依赖。

## 构建

构建 release 版本：

```sh
swift build -c release
```

从源码运行：

```sh
swift run Mac.Codex.ProfileSwitch
```

release 可执行文件生成在：

```text
.build/release/Mac.Codex.ProfileSwitch
```

## 打开程序

如果 macOS 下载后阻止打开程序，可以尝试：

1. 打开 dmg。
2. 将 `Mac.Codex.ProfileSwitch.app` 拖到 Applications。
3. 右键点击 app，选择 `Open`。
4. 在确认弹窗中再次点击 `Open`。

如果仍然无法打开，可以执行：

```sh
xattr -dr com.apple.quarantine /Applications/Mac.Codex.ProfileSwitch.app
```

然后重新打开程序。

## 项目结构

```text
Package.swift
Packaging/
  Info.plist
Sources/
  MacCodexProfileSwitch/
    AppDelegate.swift
    AppText.swift
    BackupService.swift
    CodexPaths.swift
    LocalTokenUsageService.swift
    MenuBarController.swift
    MenuBarPopoverView.swift
    OpenAIOAuthLoginService.swift
    OpenAIQuotaService.swift
    ProfileManagerView.swift
    ProfileSwitcherService.swift
    ProviderProfileService.swift
    ...
```

## 发布说明

公开发布时，仓库中只应包含源代码和项目元数据。

不要包含：

- `.build/`
- `.swiftpm/`
- `dist/`
- `.DS_Store`
- 个人 Codex 配置
- 本地 session 历史
- 生成的备份压缩包

## Reference

- [codexbar](https://github.com/steipete/codexbar)
