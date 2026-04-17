# 鸿笺 / Folio

[Linkwarden](https://github.com/linkwarden/linkwarden) 的**非官方 HarmonyOS Next 第三方客户端**。使用 ArkTS + ArkUI（Stage 模型）编写，通过 Linkwarden 公开 REST API 与任意服务端（云端或自部署）通信。

> **与 Linkwarden 官方无任何从属关系**。本项目是独立客户端，所有服务端逻辑、API 设计以及 "Linkwarden" 名称均归上游项目所有 — 服务端相关问题请到上游仓库提，不要在这里提。

> 📖 English README: [`README.md`](./README.md)

<p>
  <img alt="Platform" src="https://img.shields.io/badge/platform-HarmonyOS%20Next-1F6FEB">
  <img alt="Language" src="https://img.shields.io/badge/lang-ArkTS-3178C6">
  <img alt="Upstream" src="https://img.shields.io/badge/upstream-Linkwarden-0F172A">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
  <img alt="Status" src="https://img.shields.io/badge/status-early%20MVP-orange">
</p>

## 致谢与上游

这个 App 的所有核心能力都来自 Linkwarden 团队 — **请先去给他们点 Star**：

- **Linkwarden（真正的服务端）**：<https://github.com/linkwarden/linkwarden>
- 官网：<https://linkwarden.app>
- 官方云端实例：<https://cloud.linkwarden.app>
- 官方移动端（React Native，本项目的参考实现）：[`linkwarden/apps/mobile`](https://github.com/linkwarden/linkwarden/tree/main/apps/mobile)

本客户端中的计数/聚合行为、dashboard v2 接口用法、标签分页处理都参考了官方 mobile App，目的是尽量贴近其功能。

精神上还要感谢 [`JGeek00/MyLinks`](https://github.com/JGeek00/my-links) — 正是那个 iOS 客户端让我想做一个 HarmonyOS 版本。

## 当前功能（MVP）

- 登录任意 Linkwarden 实例（`/api/v1/session`）
- 首页显示服务端精确计数（Links / Collections / Pinned / Tags），走 `/api/v2/dashboard`
- 带游标分页的链接列表，支持搜索、按集合过滤、按 Pinned 过滤
- 新建 / 编辑 / 删除链接，含集合与标签选择器
- Pin / Unpin
- 新建集合（名称、描述、颜色、父集合）
- 分享意图（Share Intent）— 从系统分享菜单接收 URL 并预填新增对话框
- 主题切换（浅色 / 深色 / 跟随系统）
- 多语言：简体中文 / English

暂未覆盖：RSS、归档下载、批量操作、导入导出。

## 下载安装

每次推送 `v*` tag 都会触发 [`.github/workflows/release.yml`](./.github/workflows/release.yml)，在公开的 GitHub runner 上（通过社区镜像 [`harmony-next-pipeline-docker`](https://github.com/sanchuanhehe/harmony-next-pipeline-docker)）构建**未签名 HAP**，并自动发布到 GitHub Release。

最新版本请到 [Releases 页面](../../releases/latest) 下载。

### 为什么是未签名？

HarmonyOS 的签名证书绑定在开发者个人 AppGallery Connect 账号下的 bundle ID 上，我没法分发一个能直接装进别人设备的已签名包。所以 CI 只产出未签名 HAP，你自己侧载安装即可。

### 安装未签名 HAP

**方式一：[auto-installer](https://github.com/likuai2010/auto-installer)（推荐，图形界面）**

1. 下载最新的 [auto-installer release](https://github.com/likuai2010/auto-installer/releases)。
2. 手机上：设置 → 关于本机 → 软件版本，连续点击版本号 7 次开启**开发者模式**，再开启 **USB 调试**。
3. USB 连接，把 `.hap` 文件拖进 auto-installer，点击安装。

**方式二：`hdc` 命令行（需要安装 HarmonyOS SDK）**

```bash
hdc install -r link-my-harmony-vX.Y.Z.hap
```

### 发布新版本

```bash
# 先把版本号写进 harmony/AppScope/app.json5 的 versionName
git tag v0.2.0
git push origin v0.2.0
# GitHub Actions 会自动构建 HAP 并挂到 v0.2.0 的 Release 上
```

也可以在 Actions 页面手动触发（`workflow_dispatch`）做一次 dry run — 只上传构建 artifact，不会创建 Release。

## 环境要求

- **DevEco Studio** ≥ 5.0（2024 版本或更新）
- **HarmonyOS SDK** `6.0.0(20)` — `harmony/build-profile.json5` 中的 `compatibleSdkVersion` 和 `targetSdkVersion`
- 一台真实的 HarmonyOS Next 设备或 DevEco 模拟器
- 一个可访问的 Linkwarden 服务端（云端或自部署）

## 开始使用

### 1. 克隆

```bash
git clone https://github.com/<you>/link-my-harmony.git
cd link-my-harmony
```

### 2. 创建本地签名配置

仓库里**不包含**任何签名材料 — 每个开发者都要自己生成 HarmonyOS 证书。

推荐方式（图形界面）：

1. 在 DevEco Studio 中打开 `harmony/`。
2. `File → Project Structure → Signing Configs → Automatically generate signing`。
3. DevEco 会在 `~/.ohos/config/` 下生成 `.cer`、`.p12`、`.p7b`，并把完整 `material` 块填到 `build-profile.json5` 中。

手动方式（CLI / CI / AppGallery Connect 发布证书）：

```bash
cp harmony/build-profile.template.json5 harmony/build-profile.json5
# 然后编辑 harmony/build-profile.json5，填入：
#   certpath      .cer 的绝对路径
#   profile       .p7b 的绝对路径
#   storeFile     .p12 的绝对路径
#   storePassword DevEco 加密后的字符串（本地调试可以用明文）
#   keyAlias      生成证书时设置的别名
#   keyPassword   DevEco 加密后的字符串
```

`harmony/build-profile.json5` 已被 git 忽略，你填进去的签名材料不会被提交。只有 `harmony/build-profile.template.json5` 进仓库。

### 3. 构建与运行

图形界面：

- 在 DevEco 选设备/模拟器，在 `entry` 模块上点 **Run**。

命令行：

```bash
cd harmony
# hvigorw 的路径取决于你安装 HarmonyOS CLI 工具的位置。常见路径：
/opt/command-line-tools/bin/hvigorw assembleApp
```

产物位置：

```
harmony/build/outputs/default/harmony-default-unsigned.app
harmony/entry/build/default/outputs/default/app/entry-default.hap
harmony/entry/build/default/outputs/default/entry-default-unsigned.hap
```

把签名后的 HAP 安装到连接的设备上：

```bash
# 调整为你的 HarmonyOS SDK 路径
"$HOME/Library/OpenHarmony/Sdk/12/toolchains/hdc" list targets
"$HOME/Library/OpenHarmony/Sdk/12/toolchains/hdc" install -r \
  harmony/entry/build/default/outputs/default/app/entry-default.hap
```

### 4. 指向你的 Linkwarden 服务端

App 默认写死的实例 URL 是 `https://cloud.linkwarden.app`。首次启动：

1. 在登录页输入用户名和密码。
2. 如果是自部署，打开 **菜单 → Server**，粘贴实例 URL 后点 **Apply Server** — 会话会重置，然后再登录。

源码里没有硬编码任何私人服务端地址 — 每个开发者/用户自己选。

### 5.（可选）跑辅助测试

`harmony/tooling/` 下的纯 JS 工具函数带了一个小测试集：

```bash
cd harmony
node --test tooling/session-state.test.mjs
```

## 项目结构

```
harmony/
├── AppScope/app.json5                  应用元信息（bundleName、版本号）
├── build-profile.template.json5        进仓库的模板 — 复制为 build-profile.json5
├── build-profile.ci.json5              CI 用的无签名配置（release.yml 构建 HAP 时使用）
├── build-profile.json5                 仅本地使用、git 忽略，包含你的签名路径
├── entry/src/main/
│   ├── ets/
│   │   ├── common/                     Models / Query / SessionState / ShareIntent / UI 设计 tokens
│   │   ├── services/                   LinkwardenApi + SessionStorage
│   │   ├── pages/Index.ets             整个 UI（MVP 阶段有意单页）
│   │   ├── entryability/               Stage 模型的 entry ability
│   │   └── shareability/               分享菜单扩展
│   └── resources/                      i18n 字符串、图片
└── tooling/                            小型 Node 工具（查询/会话逻辑共享，带测试）
```

## 修改 Bundle ID

如果要发布到自己的 AppGallery，请把 `harmony/AppScope/app.json5` 里的 `bundleName` 换成你自己持有的（比如 `com.yourname.linkmyharmony`）。AppGallery Connect 不会接受不属于你的 bundle ID。

## 参与贡献

欢迎提 Bug 和 PR，但请注意：

- **Linkwarden 服务端或 API** 相关问题请到 [上游仓库](https://github.com/linkwarden/linkwarden/issues) 提，不要在这里提。
- 本仓库只负责 HarmonyOS 客户端 UI、ArkTS 代码和打包。

## 许可证

以 [MIT License](./LICENSE) 发布。

本仓库**不**包含任何 Linkwarden 服务端的源码 — 它是一个独立客户端，通过 Linkwarden 实例的公开 HTTP API 通信。Linkwarden 自身采用 AGPL‑3.0，其名称、Logo、服务端源码归 [Linkwarden 项目](https://github.com/linkwarden/linkwarden) 及其贡献者所有。

## 致谢

- **Linkwarden 团队** — 做出了我真正在用的自部署书签管理器。
- **JGeek00** — `MyLinks` 的作者，启发了这个 HarmonyOS 客户端。
- HarmonyOS ArkUI / ArkTS 团队 — Stage 模型和 6.x 工具链。
- **[harmony-next-pipeline-docker](https://github.com/sanchuanhehe/harmony-next-pipeline-docker)** — 让 HarmonyOS Next 在公开 GitHub runner 上 CI 成为可能。
