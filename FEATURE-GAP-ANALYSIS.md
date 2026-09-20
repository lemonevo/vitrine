# Prizm 功能差距分析（对照官方 Bitwarden 客户端）

> **性质**：规划文档，不含任何代码改动。
> **对比对象**：官方 Bitwarden 各客户端 —— 以**手机版**为主，桌面版作为补充（两者能力有差异，见 §1.2）。
> **现状基线**：本仓库代码通读（2026-09-20），非官方文档转述。
> **配套流程**：确定要做的项之后，按仓库既有约定在 `openspec/changes/<name>/` 下写 proposal / design / tasks，再动代码。

---

## 0. 摘要

1. **核心密码库能力已经相当完整** —— 5 类条目（登录 / 信用卡 / 身份 / 安全笔记 / SSH 密钥）全可读可写、文件夹树 + 收藏 + 回收站 + 组织与集合、附件（含批量上传与重试）、密码生成器、生物识别解锁、运行时中英切换。加密链路（KDF / EncString / org key / 附件双层密钥）全部对齐 Bitwarden 规范，工程质量高于"个人玩具"。

2. **曾发现 5 个"会出事"的 bug（不是缺功能），阶段 0 已全部修复**：2 个会丢数据（编辑条目抹掉服务端 passkey / 密码历史，文件夹操作丢 `organizationId` 与 `collectionIds`）、1 个会把 TOTP **种子**当成动态码复制进剪贴板、1 个会把每个条目的域名发往第三方图标服务。详见第 2 章。这类问题优先级高于任何新功能 —— 它们不增加能力，但决定这个客户端能不能被信任。

3. **阶段 2（数据主权与安全工具）已完成**。导出 / 导入、Vault 健康报告、强度读数与生成器历史、密码历史、主密码 re-prompt、服务器证书信任与固定、两步验证方法扩展、账户指纹短语、TOTP 种子录入都已落地。**有两项是故意不做而非没做**：健康报告的"已泄露密码"和数据泄露检查都需要把密码的一部分发给第三方，与"不把秘密送出去"冲突；这一取舍在报告界面上直接写明，而不是留白。

4. **性价比最高的补齐项不是"照抄手机版"**。手机版有大量 macOS 上**没有对应物**的能力（系统级自动填充服务、截图防护、iOS 26 CXP 导出）。真正值得做的是几个桌面端也能做、成本很低的项：TOTP 动态码、手动同步、Vault 超时设置、复制条目、清空回收站。

---

## 1. 方法与范围

### 1.1 官方功能来源

| 主题 | 来源 |
|---|---|
| 手机版入门与基础流程 | `bitwarden.com/help/getting-started-mobile/` |
| 两步登录全部方式 | `bitwarden.com/help/setup-two-step-login/` |
| 超时与超时动作 | `bitwarden.com/help/vault-timeout/` |
| 密码库健康报告 | `bitwarden.com/help/reports/` |
| Send | `bitwarden.com/help/send/` |
| PIN 解锁 | `bitwarden.com/help/unlock-with-pin/` |
| 导入 / 导出 | `bitwarden.com/help/import-data/`、`/help/export-your-data/` |
| Passkey | `bitwarden.com/help/storing-passkeys/` |
| SSH Agent | `bitwarden.com/help/ssh-agent/` |

### 1.2 手机版 ≠ 桌面版，别照搬

官方各客户端能力并不一致，本表只列对 Prizm（macOS 桌面）有决策意义的差异：

| 能力 | 手机版 | 桌面版 | Prizm 是否该做 |
|---|---|---|---|
| 系统级自动填充（Autofill Services） | ✅ Android/iOS 独有 | ❌ | ❌ 无对应物 |
| 截图 / 录屏防护 | ✅ | ❌ | ❌ 无对应物 |
| PIN 解锁 | ✅ | ✅ | ⚠️ 可做，但与生物识别重复 |
| 生物识别解锁 | ✅ | ✅ | ✅ 已有 |
| SSH Agent | ❌ | ✅（含 macOS） | ✅ **值得做** |
| Passkey 存储与使用 | ✅ 扩展 + 手机 | ✅ 仅查看/编辑 | ⚠️ 至少不能丢数据 |
| 导入 / 导出 | ✅ | ✅ | ✅ **值得做** |
| 多账号（最多 5 个） | ✅ | ✅ | ✅ 值得做 |
| Send | ✅ | ✅ | ⚠️ 成本较高 |
| Emergency Access | ✅ | ⚠️ 以网页端为主 | ⚠️ 低优先级 |
| 导出到其他 App（CXP） | ✅ iOS 26+ / Android 10+ | ❌ | ❌ 无对应物 |

---

## 2. 必须先修：会丢数据 / 会泄露的 5 个问题

> **状态：5 项全部已修复（阶段 0）**，变更记录见 `openspec/changes/critical-integrity-fixes/`。
>
> 实现思路：
> - 写入路径：`VaultItem.preserved`（`PreservedCipherFields` + `JSONValue`）承载 Prizm 不解释的线上字段，
>   `toRawCipher` 原样回传，因此「保存」不再等于「删除」。
> - 缓存补丁：新增 `VaultItem.with(…)` 字段级复制，7 处手工重建全部改写，`organizationId` / `collectionIds` 不可能再被漏掉。
> - 组织条目：org key 缺失时**拒绝写入**（抛错），不再静默退回个人密钥。
> - TOTP：真正的 RFC 6238 动态码生成。
> - favicon：默认只从账号自己的服务器取图标，且可一键关闭。
>
> 验证：`swift build` 零警告；新增 62 条单元测试全绿；全量 544 条测试中 10 条失败均为既有的
> 「测试包缺资源」问题（`Assets.car` / EFF 词表不在 SwiftPM 测试包里），与本次改动无关。
> 另外在 `dist/Prizm.app` 二进制里确认 `icons.bitwarden.net` 命中数为 **0**。
>
> 这些改动不增加任何用户可见功能，但决定这个客户端能不能被信任。

### 2.1 ⌃⌘C「Copy Code」复制的是 TOTP **种子**，不是动态码 —— 安全缺陷

**证据**

- `Prizm/App/PrizmApp.swift:537` → `case .totp: return login.totp`
- `Prizm/Domain/Entities/VaultItem.swift:73` 的注释原文：`/// Stored TOTP seed.`

**影响**：菜单项名为 `Copy Code`（⌃⌘C）。在 Bitwarden 的语境里 "Code" 指 6 位动态码，任何用户都会这样理解。但实际行为是把**长期有效的共享密钥**写进剪贴板并保留 30 秒。两个后果：

1. **钓鱼/误操作面**：用户会把种子粘到网站的"验证码"输入框里，等于主动交出 2FA 密钥。
2. **剪贴板泄露**：剪贴板是全局可读的，剪贴板管理器、其他 App 都能拿到。

**修法**：实现真正的 TOTP 生成（解析 `otpauth://`、HMAC-SHA1/256/512、周期与位数），菜单复制**动态码**；种子的复制入口单独命名（如 `Copy TOTP Seed`）并加二次确认，或干脆不提供。

**这是本次分析里唯一一个"当前行为就有害"的项。**

**✅ 已修复**：新增 `TOTPGenerator`（Domain 协议）+ `TOTPGeneratorImpl`（Data 实现），支持 `otpauth://` 与裸 Base32、HMAC-SHA1/256/512、URI 中 `algorithm`/`digits`/`period` 覆盖；`selectedFieldValue(.totp)` 现在返回**生成的动态码**，`selectedFieldAvailable(.totp)` 随之在没有可用种子时自动置灰。种子的复制入口按「干脆不提供」处理 —— 菜单里没有任何一项会复制它。测试用 RFC 6238 附录 B 的全部 18 组向量逐一钉死，并含一条「生成结果永远不等于种子」的回归断言。

### 2.2 编辑含 passkey 的条目会抹掉服务端的 passkey

**证据**

- `Prizm/Data/Network/Models/RawCipher.swift` 中 `fido2` 出现 **0** 次 —— 模型里根本没有这个字段。
- `CipherMapper.toRawCipher` 重新构造 `RawCipher`，自然也不含该字段。
- 保存走 `PUT /api/ciphers/{id}`，是**全量替换**语义。

**影响**：用户如果同时在手机/浏览器上用 Bitwarden 存了 passkey，在 Prizm 里编辑同一个登录项的任意字段（哪怕只改个备注）并保存，服务端的 `fido2Credentials` 会被清空 —— **passkey 静默消失，且没有任何提示**。

**✅ 已修复**：`RawLoginData` 增加 `fido2Credentials`，`CipherMapper.map` 把它收进 `VaultItem.preserved`，`toRawCipher` 原样回传。字段始终以 EncString / 原始 JSON 形态搬运，**从不解密**——没有界面显示它，解密只会扩大攻击面。同时发现同一根因还波及 `passwordRevisionDate`、`autofillOnPageLoad`、`archivedDate`（缺失时服务端会执行 **un-archive**），一并纳入。

> 服务端行为已对 Vaultwarden 源码逐一核对：`update_cipher_from_data` 中 `key`、`password_history`、`archived_date` 是无条件赋值，`login` 对象整体原样落库，只有 `attachments2` 有 `if let Some(..)` 保护（因此不传附件是安全的）。

### 2.3 `passwordHistory` 完全不读取 → 编辑即丢

**证据**：`RawCipher.swift` 中 `passwordHistory` 出现 **0** 次；全树无 `passwordHistory` / `password_history` 命中。

**影响**：与 2.2 同源。官方客户端有「密码历史」视图（`VaultItem` 级别的旧密码列表）；Prizm 既不显示，也可能在保存时把服务端记录抹掉。

**修法**：至少把字段纳入模型并原样回传（保证不丢），再考虑做展示。

**✅ 已修复**：`RawCipher` 增加 `passwordHistory`，进 `preserved` 后原样回传 —— 按「先保证不丢」处理，展示留到后续阶段。测试断言的是**序列化后的 JSON** 而非仅结构体，确保字段真的出现在请求体里。

### 2.4 文件夹删除 / 移动会丢 `organizationId` / `collectionIds`

**证据**

- `Prizm/Data/Repositories/VaultRepositoryImpl.swift:443-457`（`deleteFolder`）
- `Prizm/Data/Repositories/VaultRepositoryImpl.swift:508-519`（`moveItemToFolder`）
- 两处在重建 `VaultItem` 时**未保留** `organizationId` / `collectionIds`（而 `updateAttachments` 保留了）。

**影响**：操作后本地缓存里的组织条目"看起来"变成了个人条目。此时若用户接着编辑并保存，`toRawCipher` 会按丢失后的状态构造请求 —— **组织归属真的被写没**。

**修法**：重建 `VaultItem` 时透传这两个字段；顺带排查所有手工重建 `VaultItem` 的位置，避免同类遗漏。

**✅ 已修复，且实际情况比上面写的更严重。** 排查后共 **7 处**手工重建（不止这 2 处；`restoreItem`、`updateAttachments` 同样在丢 `preserved`）。全部改用新增的 `VaultItem.with(…)` 字段级复制，调用点只声明"我要改什么"，以后新增字段也不可能被旧调用点漏掉。

比文档更严重的地方在于后果：`organizationId` 一旦丢失，`update` 会走 `encryptionKeys = vaultKeys` 分支，**用个人金库密钥去重新加密一个组织条目** —— 这不是元数据丢失，而是产出一个任何其他组织成员都读不了的条目。因此顺带加了防线：组织条目在 org key 未解包时**直接抛错拒绝写入**，不再静默退回个人密钥。`moveItemToFolder` 走的 `PUT /api/ciphers/{id}/partial` 是真正的局部更新（只带 `favorite`/`folderId`），服务端数据本身是安全的，问题只在本地缓存。

### 2.5 favicon 默认把每个登录项的域名发给 `icons.bitwarden.net`

**证据**

- `Prizm/Presentation/.../FaviconLoader.swift:36` 硬编码 `https://icons.bitwarden.net`。
- 领域模型**已支持**覆盖（`ServerURLOverrides`，`Account.swift:31-37`），但登录时硬编码 `overrides: nil`（`LoginUseCaseImpl.swift:33`），且**没有 UI** 可设置。

**影响**：自建 Vaultwarden 的用户，动机通常正是"不想让第三方看到我的数据"。但每打开一个登录项，它的域名就被发给 Bitwarden 的图标服务。这与自建的初衷直接冲突。

**修法**：优先用自托管实例的 `/icons/{domain}/icon.png`；再加一个设置项允许关闭 favicon 或指定图标服务地址。

**✅ 已修复**：硬编码默认值已删除 —— `FaviconLoader` 的 `iconsBase` 现在是 `URL?`，默认 `nil`（不配置就不发任何请求）。新增 `AppContainer.refreshWebsiteIcons()`，在进入金库时把地址解析为账号自己服务器的 `{base}/icons`；设置里新增「隐私」分区 + 「显示网站图标」开关（默认开），关闭后**立刻**停止请求（开关检查在缓存之前，所以已缓存的域名也不会再发请求）。测试用 `URLProtocol` 子类直接观测网络层来断言「没有请求发生」，并单独断言 `icons.bitwarden.net` 永远不会被访问。

---

## 3. 功能对比矩阵

图例：✅ 已实现 ｜ ⚠️ 部分实现 ｜ ❌ 缺失 ｜ — 不适用

### 3.1 解锁与认证

| 功能 | 官方 | Prizm | 说明 |
|---|---|---|---|
| 主密码登录 | ✅ | ✅ | Prizm 额外强制 HTTPS |
| 主密码解锁（纯本地） | ✅ | ✅ | Prizm 解锁不发网络请求，正确 |
| 生物识别解锁 | ✅ | ✅ | 含嵌入式 `LAAuthenticationView`，无系统模态框 |
| PIN 解锁 | ✅ | ❌ | 与生物识别功能重叠，低优先级 |
| 两步登录：TOTP | ✅ | ✅ | |
| 两步登录：Email | ✅ | ❌ | |
| 两步登录：YubiKey OTP | ✅（付费） | ❌ | |
| 两步登录：Duo | ✅（付费） | ❌ | |
| 两步登录：FIDO2/WebAuthn | ✅ | ❌ | |
| 「使用其他方式」切换 2FA | ✅ | ❌ | 官方有多方式时的降级入口 |
| 记住设备 | ✅ | ⚠️ | 只透传 `twoFactorRemember`，不持久化 token |
| 新设备登录验证 | ✅ | ❌ | 官方 2025 起默认启用 |
| 登录设备（Login with device / 可信设备） | ✅ | ❌ | |
| 账号指纹短语（fingerprint phrase） | ✅ | ❌ | 用于校验服务端身份，自建场景很有用 |
| 多账号 / 账号切换（最多 5 个） | ✅ | ❌ | 单账号；README 已列为 Now |
| 自动锁定：睡眠 / 屏保 / 锁屏 | ✅ | ✅ | |
| 自动锁定：空闲超时 | ✅ | ❌ | 见 3.6 |
| 超时动作（锁定 / 登出） | ✅ | ❌ | 见 3.6 |

### 3.2 条目类型与字段

| 功能 | 官方 | Prizm | 说明 |
|---|---|---|---|
| 登录 | ✅ | ✅ | |
| 安全笔记 | ✅ | ✅ | 无 note 子类型选择（官方有） |
| 信用卡 | ✅ | ✅ | 编辑态无品牌下拉 / 月年选择器 |
| 身份 | ✅ | ✅ | 18 字段全覆盖 |
| SSH 密钥 | ✅ | ✅ | fingerprint 只读（服务端权威，合理） |
| **TOTP 动态码生成与显示** | ✅ | ❌ | **仅存种子；见 2.1** |
| 密码历史 | ✅ | ❌ | 见 2.3 |
| **Passkey 存储** | ✅ | ❌ | 见 2.2 |
| 自定义字段：读 | ✅ | ✅ | 四种类型全部渲染 |
| 自定义字段：**增 / 删 / 改名 / 改类型 / 排序** | ✅ | ❌ | 仅 `value` 可编辑；`linked` 类型编辑态完全只读 |
| 主密码 re-prompt（条目级二次验证） | ✅ | ⚠️ | 字段透传但**无 UI 门控**，等于不生效 |
| URI 匹配规则 | ✅ | ✅ | 7 种 matchType 可编辑 |
| 条目复制（Duplicate） | ✅ | ❌ | |
| 条目时间戳 | ✅ | ⚠️ | 只显示日期，无时间 |
| 附件 | ✅ | ✅ | 含批量上传、重试、500MB 限制、临时文件零填充删除 |
| 附件批量下载 / 批量删除 | ✅ | ❌ | 仅批量上传 |

### 3.3 组织与整理

| 功能 | 官方 | Prizm | 说明 |
|---|---|---|---|
| 文件夹 CRUD + 嵌套树 | ✅ | ✅ | 用 `/` 表达层级 |
| 收藏夹 | ✅ | ✅ | |
| 按类型筛选 + 计数 | ✅ | ✅ | |
| 回收站：软删除 / 恢复 / 永久删除 | ✅ | ✅ | |
| **清空回收站** | ✅ | ❌ | 只能逐条删 |
| 回收站保留期提示 | ✅ | ❌ | |
| 集合 CRUD + 树 + 权限门控 | ✅ | ✅ | 名称用 org key 加密，正确 |
| 组织与 org key 解包 | ✅ | ✅ | RSA-OAEP-SHA1 链路完整 |
| **把条目移入 / 移出组织** | ✅ | ❌ | 无 org picker；只能在集合内新建 |
| 搜索范围 | ✅ 含备注、自定义字段、文件夹 | ⚠️ | 仅名称 + 登录用户名/URI + 卡持卡人 + 身份邮箱/公司 |
| 排序选项 | ✅ | ❌ | 仅按名称字母序 |
| 拖拽移动条目 | ✅ | ✅ | 但仅单条（列表无多选） |

### 3.4 工具

| 功能 | 官方 | Prizm | 说明 |
|---|---|---|---|
| 密码生成器（密码 / 口令短语） | ✅ | ✅ | 参数完整，EFF 大词表 |
| 生成器历史 | ✅ | ✅ | 仅内存，锁定即清除 |
| 密码强度计 | ✅ | ⚠️ | 自研估算器，**不是 zxcvbn**；局限见 SECURITY.md |
| **导入** | ✅ | ⚠️ | 仅 Bitwarden 未加密 JSON；加密导出会**明确报错**而非静默失败 |
| **导出** | ✅ | ⚠️ | 仅未加密 JSON —— 无 CSV / 加密 JSON / ZIP |
| **TOTP 种子录入** | ✅ | ✅ | 编辑表单可填；解析不了的值只警告，不拒绝保存 |
| Vault 健康报告：重复使用的密码 | ✅（付费） | ✅ | 纯本地 |
| Vault 健康报告：弱密码 | ✅（付费） | ✅ | 纯本地 |
| Vault 健康报告：不安全网站 | ✅（付费） | ✅ | 纯本地，只看 `http://` |
| Vault 健康报告：未启用 2FA | ✅（付费） | ✅ | 本地判定「有密码但无 TOTP 种子」，**不查 2fa.directory** |
| Vault 健康报告：长期未更换 | ✅（付费） | ✅ | 两年；`passwordRevisionDate` 缺失也算入 |
| Vault 健康报告：暴露的密码 | ✅（付费） | ❌ | **故意不做** —— 需把密码的一部分发给第三方 |
| Vault 健康报告：数据泄露（HIBP） | ✅（免费） | ❌ | **故意不做** —— 同上；且自建场景需自购 key |
| Send | ✅ | ❌ | |
| SSH Agent | ✅ 桌面端 | ❌ | SSH 密钥条目已有，但无 agent（已列入 Wave E） |

### 3.5 同步与离线

| 功能 | 官方 | Prizm | 说明 |
|---|---|---|---|
| 解锁后自动同步 | ✅ | ✅ | |
| **手动同步（按钮 / 快捷键）** | ✅ | ❌ | 只有只读状态标签 |
| 后台 / 定时同步 | ✅ | ❌ | README 列为 Now |
| 离线读取（本地缓存） | ✅ | ❌ | vault 仅在内存，进程退出即丢 |
| 离线写入队列 | ✅ | ❌ | 写操作必须联网 |
| 冲突检测 / 合并 | ✅ | ❌ | last-write-wins，无 revisionDate 校验 |

### 3.6 安全与设置

| 功能 | 官方 | Prizm | 说明 |
|---|---|---|---|
| 剪贴板自动清空 | ✅ 可配置 | ✅ | 间隔可配 |
| Vault 超时时长设置 | ✅ | ✅ | |
| 超时动作（锁定 / 登出） | ✅ | ✅ | |
| 主密码 re-prompt 强制执行 | ✅ | ✅ | 密码 / TOTP / 隐藏自定义字段 / 密码历史；**每条目每次解锁问一次** |
| 证书固定 / 自定义 CA | ✅ | ✅ | 固定默认关闭、指纹可看、可忘记；**握手本身未覆盖**，见 SECURITY.md |
| 登录两步验证方法 | ✅ | ⚠️ | 验证器 / 邮件 / YubiKey 可完成；恢复码**不完成**（接受它会清空账号上所有 2FA） |
| 账户指纹短语 | ✅ | ✅ | 与官方同源算法，测试钉住官方发布的向量 |
| 服务端 API / identity / icons 覆盖 | ✅ | ⚠️ | 模型支持，无 UI，且硬编码 nil |
| 截图防护 | ✅ 手机 | — | macOS 无对应物 |
| 设置项总数 | 数十项 | 少，且每项都可撤销 | 语言 / 网站图标 / 剪贴板 / 超时时长 / 超时动作 / 生物识别 / 证书固定 / 信任证书 / 忘记固定 |
| 界面语言 | 多语言 | ✅ en / zh-Hans | 运行时切换，479 键对齐 |

---

## 4. 缺口分级

### P0 — 低成本、高价值（建议紧跟阶段 0 做）

| 项 | 为什么排 P0 | 粗估 |
|---|---|---|
| TOTP 动态码生成 + 倒计时 + 复制 | 2.1 的正解，桌面端日常刚需 | 中 |
| 手动同步（按钮 + ⌘R） | 协议注释明确"无手动同步"，用户最直观的缺失 | 低 |
| Vault 超时设置（时长 + 动作） | 官方桌面端也有；当前只有事件驱动锁定 | 低 |
| 剪贴板超时可配置 / 可关闭 | 已有实现，只差一个设置项 | 低 |
| 条目复制（Duplicate） | 官方标配，实现成本极低 | 低 |
| 清空回收站 | 已有单条永久删除，批量只是聚合 | 低 |
| 排序选项 + 搜索范围扩展 | 86 条时已开始难找 | 低 |
| 自定义字段增删改类型 | 编辑态最大的一处功能残缺 | 中 |

### P1 — 中等成本、明确价值

| 项 | 说明 | 粗估 |
|---|---|---|
| 主密码 re-prompt 强制执行 | 字段已在，补 UI 门控 + 开关 | 中 |
| 导入 / 导出 | 迁移与备份的硬需求；导出建议先做 | 中大 |
| Vault 健康报告（本地 5 项） | 纯本地计算，无服务端依赖，可先做 4 项 | 中 |
| 密码强度计（zxcvbn） | 生成器与编辑态都用得上 | 中 |
| 生成器历史 | 官方有，实现简单 | 低 |
| 密码历史展示 | 2.3 的完整解 | 低中 |
| 2FA 方式扩展（Email / YubiKey / Duo / WebAuthn） | 覆盖面问题，按需做 | 中 |
| 账号指纹短语 | 自建场景校验服务端身份 | 低 |
| 把条目移入 / 移出组织 | 组织功能目前是半截 | 中 |
| 证书固定 / 自定义 CA | 自建自签证书必需 | 中 |

### P2 — 大工程

| 项 | 说明 |
|---|---|
| 多账号 / 账号切换 | 数据结构要从"单 userId"改成账号列表，牵动钥匙串、UI、同步 |
| 离线读写 + 冲突处理 | 需要本地持久化 + WAL + revisionDate 校验，架构级改动 |
| Send | 新 API + 新 UI + 独立加密路径 |
| Passkey 完整支持 | 需要浏览器扩展才能 autofill；纯 macOS App 只能做到"查看/不丢" |
| SSH Agent | 桌面端可行，需实现 ssh-agent 协议 socket |
| 浏览器自动填充扩展 | 独立工程，README 列为 Later |

---

## 5. 建议路线图

```
阶段 0  必修（先做，不含新功能）                        ✅ 已完成
        └ 2.1 TOTP 种子泄露 · 2.2 passkey 丢失 · 2.3 密码历史丢失
          2.4 org 归属丢失 · 2.5 favicon 外泄
        └ 实现与验证见 openspec/changes/critical-integrity-fixes/
          （额外修掉一个：带 per-item key 的条目字段解密用错密钥，导致这类条目读不出来）

阶段 1  日常可用性补齐                                  ✅ 已完成
        └ ~~TOTP 动态码~~（已在阶段 0 完成）· 手动同步 · 超时设置 · 剪贴板超时可配
          复制条目 · 清空回收站 · 排序/搜索 · 自定义字段增删改
        └ 实现与验证见 openspec/changes/phase-1-daily-usability/
          （额外修掉一个：⌘R「立即同步」在解锁后一直处于禁用状态 ——
            菜单项的启用条件只在同步状态变化时重算，而快捷键本身就是启动同步的方式之一）

阶段 2  数据主权与安全工具                              ✅ 已完成
        └ 导出 / 导入 · 健康报告 · 强度读数与生成器历史 · 密码历史
          re-prompt 门禁 · 服务器证书信任与固定 · 两步验证方法扩展
          账户指纹短语 · TOTP 种子录入
        └ 实现与验证见 openspec/changes/phase-2-data-sovereignty/
        └ **故意丢弃的两项**（不是漏做，写在报告界面上）：
            · 已泄露密码检查 —— 需把密码的一部分发给第三方
            · 数据泄露检查（HIBP）—— 同上，且自建场景需自购 key
        └ **有意缩小的两项**：
            · 健康报告"未启用 2FA"用本地判定（有密码无 TOTP 种子），不查 2fa.directory
            · 导出 / 导入只支持未加密 JSON，不支持 CSV / 加密 JSON / ZIP
        └ 额外修掉两个真 bug：
            · `identityToken` 硬编码 `twoFactorProvider: 0` —— 用邮件 / YubiKey 的账号
              会被要求输验证器码，然后以错误的 provider 提交
            · 30 处 `data.resetBytes(in: 0..<count)` 是**堆越界写**（切出来的 Data 保留
              来源 buffer 的索引），一次清零写到了 32 字节分配之外 32 字节

阶段 3  架构级
        └ 多账号 · 离线读写 + 冲突处理 · Send · SSH Agent · Passkey
```

**为什么这个顺序**：阶段 0 不产生新功能，但它决定了"能不能放心把密码交给这个 App"。阶段 1 全是低成本高感知项，能最快让日常使用不别扭。阶段 2 解决"数据拿得出来、看得清风险"。阶段 3 每一项都会牵动架构，不适合和新功能混在一起做。

---

## 6. 不适用项（macOS 上不要照搬）

| 官方手机版功能 | 为什么不做 |
|---|---|
| Autofill Services（Android/iOS 系统级填充） | macOS 无对应物；等价能力需要 Safari App Extension，属独立工程 |
| 截图 / 录屏防护 | iOS/Android 专有 API；macOS 无公开等价物 |
| 导出到其他 App（FIDO CXP） | 仅 iOS 26+ / Android 10+ |
| 手机端 Send 的 100MB 限制 | 桌面端为 500MB，沿用桌面限制即可 |

---

## 7. 待决策

1. **阶段 0 是否先做？** 我建议先做 —— 尤其 2.1 是"当前行为就有害"，2.2/2.3 是静默丢数据。
2. **阶段 1 里哪几项优先？** 若只能挑三项：TOTP 动态码、手动同步、超时设置。
3. **要不要做多账号 / 离线**？这两项是 README 自己列的 Now，但都是架构级改动，建议单独立项。
4. **导出优先于导入？** 建议先做导出（备份/逃生通道），再做导入。
5. **自建场景要不要把 favicon 默认关掉？** 这与 2.5 相关，也涉及默认值取向。

---

*本文为工作文档，用于确定 `openspec/changes/` 的范围。*
