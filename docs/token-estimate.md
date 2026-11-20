# 词元统计与额度点估算

词元模式显示实际 Token 用量和当前剩余额度百分比。额度点模式还显示估算的剩余 credits。

## 官方费率

内置配置为各模型保留费率与速度倍率的核验日期，旧模型继续使用历史参考费率。

- [各模型 Token / Credits 费率](https://learn.chatgpt.com/docs/pricing#token-rates)
- [ChatGPT Work / Codex credit rate card](https://help.openai.com/en/articles/11481834-chatgpt-rate-card-business-enterpriseedu-credit-based-pricing)
- [Fast 和 Ultrafast 倍率](https://learn.chatgpt.com/docs/pricing#speed-multipliers)

应用按订阅内额度估算。Standard 为 **1×**。GPT-6.2 Astra / Sol 的 Fast 倍率为 **2×**，GPT-6.1 Sol / Terra 和 GPT-6 Astra、Sol、Luna 为 **2.5×**。Ultrafast 下，GPT-6.2 Astra / Sol 为 **6×**，GPT-6 Astra 和 GPT-6.1 Sol 为 **8×**。购买的 credits、Enterprise 按量付费和 API Key 计费各有适用费率，应用的估算统一使用订阅内倍率。

每百万普通输入、缓存输入、输出 Token 的标准 credits 分别为：GPT-6.1 Terra `25 / 1.25 / 125`，GPT-6.1 Sol `50 / 2.5 / 250`，GPT-6 Astra `250 / 25 / 1,250`，GPT-6 Sol `50 / 5 / 250`，GPT-6 Luna `2.5 / 0.25 / 12.5`。GPT-6.1 Terra 的三项费率均为 GPT-6.1 Sol 的一半。GPT-6.1 Sol 的缓存输入费率是 GPT-6 Sol 的一半，其余两项相同。相同的 Fast 倍率不代表相同的基础费率。

[`Sources/CodexIsland/Resources/CodexCreditRates.json`](../Sources/CodexIsland/Resources/CodexCreditRates.json) 随应用打包，提供默认配置和历史模型参考费率。运行时优先读取 `~/Library/Application Support/CodexIsland/CodexConfiguration.json`，默认每 7 天读取官方费率和本地 Codex 模型目录，周期可配置。新增可用模型由 Codex 目录确认，官方价格页面只提供费率；只修改打包 JSON 不会替换已有的运行时配置，也不会把模型加入账号可用目录。计算、去重、调用归属和汇总仍由 Swift 代码负责。

有效更新原子写入并刷新内存计算缓存，无需重新构建或重启。新版费率页的 Fast 和 Ultrafast 表均需解析成功。失败时保留上次有效费率及其更新时间，一小时后重试。`subscriptionEstimates` 保存项目订阅估算基准，自动刷新保留手工基准。缺少适用倍率的调用显示为无法计价。

配置格式：

- `schemaVersion` 为 `1`，`unit` 固定为 `credits_per_million_tokens`；`revision` 为本次配置修订日期，`sources` 记录核验来源。
- `models` 按精确模型 ID 列出 `rate.input`、`rate.cachedInput`、`rate.output`，并用每条记录的 `verifiedOn` 区分当前核验与历史费率。日期后缀可匹配基础模型，未知变体不猜价格。
- `fastPolicies` 按 `family` 维护 `includedSubscription` 和可选的 `purchasedCredits`。家族重叠时优先最具体的条目；应用当前只使用订阅倍率计算，购买 Credits 倍率仅作已核验参考，缺失表示未核验。
- `ultrafastPolicies` 按模型 ID 维护 `includedSubscription`，日期后缀可匹配基础模型。
- `catalog` 保存当前账号可用模型及其能力，`knownCodexModelIDs` 保留曾出现的模型 ID，供历史日志计价。模型目录与费率分别记录 `catalogUpdatedAt`、`pricingUpdatedAt`，`updateIntervalDays` 控制更新周期。
- `subscriptionEstimates.plus` 保存 Plus 基准，`subscriptionMultipliers` 保存各 Pro 档位相对 Plus 的倍率；升级时将旧版独立 Pro 额度迁移为倍率并保留手工 Plus 基准。
- 加载时检查版本、单位、来源、日期、重复模型、费率及倍率。本地配置缺失或无效时回退到内置配置；两者都不可用时才无法估算额度点，不把未知消耗当作零，Token 统计照常运行。自动更新失败时保留上次有效配置。打包资源检查会拒绝缺失或无效的内置配置。

未列出的模型、无法确认的模型别名及无明细的历史记录不猜价格。例如 GPT-5.5 的 20,000 普通输入、80,000 缓存输入和 5,000 输出，参考成本为 7.25 credits。

## 会话累计 credits

会话 Token 明细弹层在累计 Token 数后显示 `(55.2 credits)`，颜色跟随用户选择的主题。用 `((Input − Cache) × 普通输入费率 + Cache × 缓存费率 + Output × 输出费率) ÷ 1,000,000` 计算 Standard 用量，再乘当次速度档位的订阅内倍率。Input 已含缓存，Output 已含推理。

按会话历史各次调用记录的模型和速度档位分别估算后求和，最后统一保留一位小数。未记录档位时按 Standard 估算并在提示中说明。

单价和速度倍率使用当前生效的配置。配置更新后，会话及图表的额度缓存失效，下次读取时按新费率重新估算历史日志。数值表示按当前费率估算的订阅内用量。

credits 与弹层中的累计 Token 使用同一范围：保留日志中属于该累计计数的历史，计数重置时同步重置。重复通知不重复计费；未知模型、第三方 provider、缺失明细或无法归属的累计跳增显示 `— credits`。每个会话首次读取历史后仅增量读取，缓存不保留对话内容。


## 图表历史 credits

30 日和 48 小时图表使用本机历史日志，按每次调用记录的模型、Token 明细和速度档位估算订阅内用量，再按天或小时汇总。

账户日 Token 可包含其他电脑的用量；credits 独立按本机日志折算，不要求两者 Token 数相等。本机调用均可计价时，词元模式在括号内显示额度数值 `(1234.6)`，跨设备差额不会添加 ≥。仅当本机调用自身缺少费率或明细时，才显示已知小计 `(≥1234.5)`，下限向下保留一位小数。悬停说明额度仅包含本机用量。完全没有本地明细的账户历史显示 `(—)`，不会按当前模型的价格套算其他电脑的历史。

## 剩余 credits 切换

额度右侧的 Tokens / Credits 切换会记住选择。`subscriptionEstimates.plus.credits` 是唯一的个人套餐额度基准，默认 1250；`subscriptionMultipliers` 保存 Pro 100 / 200 / 500 的 10 / 20 / 50 倍关系，默认对应 12500 / 25000 / 62500。剩余 credits 再乘以当前主额度剩余比例显示。这是项目指定的估算，并非账户接口返回的 credits 余额。点击设置页额度卡片中的 Plus 数值打开编辑浮层，实时预览 Pro 额度，支持点击「保存」或按回车，原子写入成功后立即更新所有估算；无效输入或写入失败会保留原值。也可退出应用后修改运行时 JSON 中的 `subscriptionEstimates.plus.credits`，再重新打开。自动刷新费率保留手工基准，包括刷新过程中保存的修改。

套餐名称与估算基准分别维护。根据 Codex CLI 0.162.1 生成的 `PlanType` 枚举，`prolite`、`pro`、`promax` 分别展示为 Pro 100、Pro 200、Pro 500；Business、Enterprise、Edu 的变体使用可读名称，悬停可查看完整名称。旧版账户接口仅返回 `pro` 时，可由额度桶里的 `prolite` 或 `promax` 补充具体档位。Pro 500 使用配置中指定的 50 倍关系。其他未配置套餐显示 `—` 额度点，剩余百分比照常展示。

估算值前显示白色 `≈ `，credits 数值按整数显示，配色与模式切换、图表、图例及会话明细一起跟随所选主题。词元模式仅显示剩余百分比，不估算剩余 Token，也不采集或缓存用于该估算的额度样本。


## 柱图的 Tokens / Credits 模式

中文标签为“词元 / 额度点”，英文为“Tokens / Credits”。顶部切换同步控制剩余额度数值和下方的 30 日 / 48 小时柱图。词元模式显示模型实际处理的词元数。额度点模式使用“标准 / ⚡实际”两组订阅内用量估算。标准按 Standard 计算，实际按调用记录的速度档位计算，两者之差为 Fast 或 Ultrafast 增加的用量。

两项同时显示时，实心柱为标准用量，空心轮廓为按记录速度估算的总用量。单独显示一项时，图表按该项重新缩放。两项均以完整精度汇总，显示时保留一位小数。

中文界面的 credits 单位统一显示为“额度点”。图表和会话消耗数值为 0 时显示“0”，其余数值保留一位小数；剩余额度点按整数显示。

会话列表也跟随词元 / 额度点模式切换，额度点模式显示本会话累计额度数值。悬浮明细统一使用“累计消耗”：词元模式显示“实际词元（额度点）”，额度点模式显示“额度点（实际词元）”，并保留两种数值的单位。
