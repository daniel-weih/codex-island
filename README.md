# Codex Island

Codex Island 是一个 macOS 顶部悬浮状态岛。默认保持收起，鼠标移入后展开，展示 Codex 账户额度、Profile 头像与昵称、累计及近 30 天 Token 活动，以及最近五条会话各自的模型、推理强度、Fast 状态和累计 Token。

账户、用量和会话索引来自本机 `codex app-server` 的只读接口；会话配置来自该会话本地 rollout 中最近一次 `thread_settings_applied`。Profile 昵称和头像通过 Codex App 当前使用的 Profile 接口按需读取，认证 token 只在请求期间保留于内存，不会写盘或输出到日志。程序不会解析会话消息正文，也不会调用消耗 reset credit 的接口。

## 当前能力

- 顶部居中、全 Space 可见的无边框悬浮面板，并适配刘海屏与普通外接屏
- 鼠标进入实体刘海区域自动展开，离开刘海和展开面板后自动收起
- 收起态左侧显示本机根会话的当日 Token 新增量；检测到 Token 持续消耗时，粒子从刘海侧向当日用量方向流动；有会话执行时亮绿点，否则显示灰点
- 主额度的剩余比例和下次重置时间
- `rateLimitResetCredits.availableCount` 显示可用 reset 次数；悬停可查看全部可用次数的到期时间
- Profile 头像、昵称、账户累计 Token，以及近 30 个完整日历日的每日 Token 柱图
- 点击展开态的非会话区域可激活 Codex App；右上角齿轮通过官方深链打开设置
- 灵动岛设置支持状态动效、Token 消耗动效、界面语言与开机启动；开机启动默认关闭，主动开启后随 macOS 用户登录自动运行
- Codex 账户套餐，以及最近五条 CLI/App 会话各自的模型、推理强度和 Fast 状态
- 最近五条会话的近实时执行状态：执行中、空闲、已中断或失败
- 最近五条会话的累计 Token；悬停数值可查看输入、缓存输入、输出与推理输出明细
- 点击会话整行可通过官方 `codex://threads/<thread-id>` 深链在 Codex App 中打开
- 会话列表与执行状态每秒刷新，额度每 30 秒刷新，账户统计每 5 分钟刷新；无菜单栏图标或手动展示入口

> 执行状态来自 CLI 与 App 共同写入的本地 rollout 生命周期事件，通常会在 1 秒内更新。若 Codex 进程异常退出、没有写入结束事件，长时间无活动的未闭合任务会降级为“状态未知”，避免一直误报为“执行中”。

## 运行

要求：macOS 13 或更高版本、Swift 6 工具链、本机已安装并登录 Codex CLI。

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

可在灵动岛设置中开启“开机启动”。默认关闭；开启后，应用只会写入当前用户的 `~/Library/LaunchAgents/com.codexisland.app.login-item.plist`，并从下一次 macOS 用户登录开始自动运行。该启动项直接运行 Codex Island 并关联 `com.codexisland.app`，避免 macOS 将后台项目显示为通用的 `open` 命令；上一版已开启的 `open` 格式会在新版启动时自动迁移并保持开启。该方式不要求 Apple Developer 证书或管理员权限；关闭开关会删除上述专用 plist，不会影响其他登录项。

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

## 数据边界

应用通过 stdio 启动一个本地 `codex app-server` 子进程，完成 `initialize` 后定期调用：

- `account/read`
- `account/rateLimits/read`
- `account/usage/read`
- `thread/list`

所有业务调用均为只读。为取得 App Profile 昵称和头像，程序通过本地 App Server 的 `getAuthStatus` 临时取得当前 token，然后请求 Codex App 当前使用的 `/wham/profiles/me`；网络会话使用无 Cookie、无磁盘缓存的临时配置，401 时最多刷新 token 并重试一次。该 Profile 路径不是公开契约，失败时自动回退为“Codex 用户”和昵称首字母占位，不会读取本机账户名或系统头像，也不影响额度、用量和会话状态。

程序还会在 `$CODEX_HOME/sessions` 与 `$CODEX_HOME/archived_sessions` 中只读发现本机根 CLI/App 会话，并扫描对应 `.jsonl`；最近会话通过 `thread/list` 的 `source` 标记为 `TUI` 或 `APP`，同时只提取模型设置、带时间戳的 `token_count` 累计用量及 `task_started`、`task_complete`、`turn_aborted`、`error` 生命周期事件。当日用量按累计值的正向增量计算，重复通知不会重复计数；Fork/子代理会复制父会话历史，暂不纳入该汇总。最近会话列表、执行状态与累计 Token 每秒刷新，本地全量会话索引每 15 秒刷新，额度保持 30 秒刷新，账户统计使用 5 分钟缓存，Profile 身份使用 15 分钟缓存。退出应用时子进程会一并结束。
