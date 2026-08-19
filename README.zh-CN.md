# Codex Island

[English](README.md) | **简体中文**

Codex Island 是一个 macOS 顶部悬浮状态岛。默认保持收起，鼠标移入后展开，展示 Codex 账户额度、Profile 头像与昵称、累计及近 30 天 Token 活动，以及最近三条会话各自的来源、Fast 状态和累计 Token。

账户、用量和会话索引来自本机 `codex app-server` 的只读接口；会话配置来自该会话本地 rollout 中最近一次 `thread_settings_applied`。Profile 昵称和头像通过 Codex App 当前使用的 Profile 接口按需读取，认证 token 只在请求期间保留于内存，不会写盘或输出到日志。程序不会解析会话消息正文，也不会调用消耗 reset credit 的接口。

## 界面预览

### 展开态

![Codex Island 展开态总览](docs/images/ui/dashboard.png)

> 截图由内置离屏预览生成，其中的额度、Token、套餐、日期和会话内容均为演示数据。

### 收起态

| 静默状态 | Token 消耗中 |
| :---: | :---: |
| ![Codex Island 收起态](docs/images/ui/compact.png) | ![Codex Island Token 消耗动效状态](docs/images/ui/compact-consuming.png) |

### 悬停明细

**重置次数到期时间**

![Codex Island 重置次数到期时间悬浮卡片](docs/images/ui/reset-expirations.png)

**会话 Token 明细**

![Codex Island 会话 Token 明细悬浮卡片](docs/images/ui/token-details.png)

### 设置

![Codex Island 设置面板](docs/images/ui/settings.png)

## 安装与运行

建议优先拉取最新代码并在本机自行构建；也可以直接下载最新版本安装。

> [!IMPORTANT]
> 当前项目未使用 Apple Developer ID 证书签名，也未经过 Apple 公证。直接下载 DMG 时，macOS Gatekeeper 通常会提示无法验证开发者或存在安全风险。若希望避免这类下载来源校验提示，建议采用下面的本地构建方式。

### 推荐：拉取源码并本地构建

要求：macOS 13 或更高版本、Swift 6 工具链、本机已安装并登录 Codex CLI。

首次获取代码：

```bash
git clone https://github.com/daniel-weih/codex-island.git
cd codex-island
```

如果已经克隆过仓库，请先更新到最新代码：

```bash
git pull --ff-only
```

直接运行：

```bash
swift run
```

打包成 `.app`：

```bash
./scripts/package_app.sh
open "dist/Codex Island.app"
```

打包成带 App、DMG 文件与挂载卷图标的安装包：

```bash
./scripts/package_dmg.sh
open "dist/Codex-Island.dmg"
```

### 直接下载 DMG（备选）

**[下载 Codex Island DMG](https://github.com/daniel-weih/codex-island/releases/download/v2026.07.27/Codex-Island.dmg)**

当前版本为 `v2026.07.27`，支持 macOS 13 及以上的 Apple Silicon Mac。安装包使用 ad-hoc 签名；首次启动若被 macOS 拦截，请在 Finder 中按住 Control 点按应用，选择“打开”。

### 开机启动

可在灵动岛设置中开启“开机启动”。默认关闭；开启后，应用只会在当前用户的 `~/Library/LaunchAgents/` 中写入 Codex Island 专用启动项，并从下一次 macOS 用户登录开始自动运行。启动项直接运行 Codex Island，避免 macOS 将后台项目显示为通用的 `open` 命令；旧版启动项会在新版启动时自动迁移并保持开启。该方式不要求 Apple Developer 证书或管理员权限；关闭开关只会删除 Codex Island 自己的启动项，不会影响其他登录项。

### 开发与验证

如果 `codex` 不在常见路径中，可显式指定：

```bash
CODEX_CLI_PATH=/path/to/codex swift run
```

运行解析器检查：

```bash
./scripts/test.sh
```

只读检查本机 App Server 连接（不会打印 token、邮箱和会话正文）：

```bash
swift run CodexIsland --probe
```

渲染收起/展开、悬浮卡片、窄宽、无刘海、1x/2x 与数据边界状态的离屏预览矩阵：

```bash
swift run CodexIsland --render-preview dist/previews
```

## 当前能力

- 顶部居中、全 Space 可见的无边框悬浮面板，并适配刘海屏与普通外接屏
- 鼠标进入实体刘海区域自动展开，离开刘海和展开面板后自动收起
- 收起态左侧显示本机消息触发的全部模型调用当日 Token 新增量；检测到 Token 持续消耗时，粒子从刘海侧向当日用量方向流动；有会话执行时亮绿点，否则显示灰点
- 主额度的剩余比例、估算可用 Token、下次重置时间和相对使用节奏提示
- `rateLimitResetCredits.availableCount` 显示可用 reset 次数；悬停可查看全部可用次数的到期时间
- Profile 头像、昵称、账户累计 Token，以及可切换的近 30 日每日 / 过去 48 小时每小时 Token 柱图
- 点击展开态的非会话区域可激活 Codex App；右上角截图按钮会将当前灵动岛以透明圆角 PNG 直接复制到剪切板
- 灵动岛设置支持状态动效、Token 消耗动效、品牌配色、界面语言、显示器选择与开机启动；显示位置默认自动，也可固定到内建屏或任一已连接外接屏，目标屏断开时临时回退并在重连后自动恢复；开机启动默认关闭，主动开启后随 macOS 用户登录自动运行
- Codex 账户套餐，以及最近三条 CLI/App 会话各自的来源和 Fast 状态；执行中的任务优先展示
- 最近三条会话的近实时执行状态：执行中、空闲、已中断或失败
- 最近三条会话的累计 Token；悬停数值可查看输入、缓存输入、输出与推理输出明细
- 点击会话整行可通过官方 `codex://threads/<thread-id>` 深链在 Codex App 中打开
- 会话列表与执行状态每秒刷新，额度每 30 秒刷新，账户统计每 5 分钟刷新；无菜单栏图标或手动展示入口

> 执行状态来自 CLI 与 App 共同写入的本地 rollout 生命周期事件，通常会在 1 秒内更新。若 Codex 进程异常退出、没有写入结束事件，长时间无活动的未闭合任务会降级为“状态未知”，避免一直误报为“执行中”。

## 数据边界

应用通过 stdio 启动一个本地 `codex app-server` 子进程，完成 `initialize` 后定期调用：

- `account/read`
- `account/rateLimits/read`
- `account/usage/read`
- `thread/list`

所有业务调用均为只读。为取得 App Profile 昵称和头像，程序通过本地 App Server 的 `getAuthStatus` 临时取得当前 token，然后请求 Codex App 当前使用的 `/wham/profiles/me`；网络会话使用无 Cookie、无磁盘缓存的临时配置，401 时最多刷新 token 并重试一次。该 Profile 路径不是公开契约，失败时自动回退为“Codex 用户”和昵称首字母占位，不会读取本机账户名或系统头像，也不影响额度、用量和会话状态。

程序还会在 `$CODEX_HOME/sessions` 与 `$CODEX_HOME/archived_sessions` 中只读发现本机 CLI/App 会话、Fork 与子代理，并扫描对应 `.jsonl`；最近会话通过 `thread/list` 的 `source` 标记为 `TUI` 或 `APP`，同时只提取模型设置、带时间戳的 `token_count` 累计用量及 `task_started`、`task_complete`、`turn_aborted`、`error` 生命周期事件。当日和近 48 小时分时用量按每次模型调用后累计值的正向增量计算，重复通知不会重复计数；Fork 从自己的 `session_meta` 创建时间开始计入，子代理则从首个 `inter_agent_communication_metadata` 活动边界开始计入，因此不会重复统计时间戳被重写的父会话历史。今日柱与收起态今日数值都使用该本地实时结果，之前日期仍来自账户日汇总。最近会话列表、执行状态、累计 Token 和分时用量每秒刷新，本地全量会话索引每 15 秒刷新，额度保持 30 秒刷新，账户统计使用 5 分钟缓存，Profile 身份使用 15 分钟缓存。退出应用时子进程会一并结束。
