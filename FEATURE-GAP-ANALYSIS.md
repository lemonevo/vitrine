# Vitrine 功能差距分析（对照官方 Bitwarden 客户端）

> **性质**：规划文档，不含任何代码改动。
> **对比对象**：官方 Bitwarden 各客户端 —— 以**手机版**为主，桌面版作为补充（两者能力有差异，见 §1.2）。
> **现状基线**：本仓库代码通读（2026-09-20），非官方文档转述。
> **配套流程**：确定要做的项之后，按仓库既有约定在 `openspec/changes/<name>/` 下写 proposal / design / tasks，再动代码。

---

## 0. 摘要

1. **核心密码库能力已经相当完整** —— 5 类条目（登录 / 信用卡 / 身份 / 安全笔记 / SSH 密钥）全可读可写、文件夹树 + 收藏 + 回收站 + 组织与集合、附件（含批量上传与重试）、密码生成器、生物识别解锁、运行时中英切换。加密链路（KDF / EncString / org key / 附件双层密钥）全部对齐 Bitwarden 规范，工程质量高于"个人玩具"。

2. **曾发现 5 个"会出事"的 bug（不是缺功能），阶段 0 已全部修复**：2 个会丢数据（编辑条目抹掉服务端 passkey / 密码历史，文件夹操作丢 `organizationId` 与 `collectionIds`）、1 个会把 TOTP **种子**当成动态码复制进剪贴板、1 个会把每个条目的域名发往第三方图标服务。详见第 2 章。这类问题优先级高于任何新功能 —— 它们不增加能力，但决定这个客户端能不能被信任。

3. **阶段 2（数据主权与安全工具）已完成**。导出 / 导入、Vault 健康报告、强度读数与生成器历史、密码历史、主密码 re-prompt、服务器证书信任与固定、两步验证方法扩展、账户指纹短语、TOTP 种子录入都已落地。**有两项是故意不做而非没做**：健康报告的"已泄露密码"和数据泄露检查都需要把密码的一部分发给第三方，与"不把秘密送出去"冲突；这一取舍在报告界面上直接写明，而不是留白。

4. **第 4 条原样保留会误导，所以重写了。** 原文写"真正值得做的是：TOTP 动态码、手动同步、Vault 超时设置、复制条目、清空回收站" —— **这五项在阶段 1 就全部做完了**，而本文件长期没有同步。这一段是这份文档整体失准的缩影。

5. **现状（2026-09-21 逐条核实）**：阶段 0–4 已完成，阶段 5「功能全集对齐」进行中。**§3 的矩阵每一行都带了核实依据**（`[码]` 读到代码 / `[官]` 读到官方文档 / `[测]` 实测 / `[?]` 没验成），因为这份文档此前至少两次**凭空发明了官方行为**。

6. **两件事必须说在摘要里**：**(a)** 有若干被误列为"缺口"的项，官方**根本没有这个功能**（附件批量操作、条目版本历史、桌面端 2FA 管理），做它们不是对齐而是偏离 —— 见 §3 的 🚫 行与 §8；**(b)** ❓ 那几项（归档、收藏置顶的桌面端行为、搜索增强）**在拿到一手来源之前不要动工**，这次的教训正是"照二手结论开工"。

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

官方各客户端能力并不一致，本表只列对 Vitrine（macOS 桌面）有决策意义的差异：

| 能力 | 手机版 | 桌面版 | Vitrine 是否该做 |
|---|---|---|---|
| 系统级自动填充（Autofill Services） | ✅ Android/iOS 独有 | ✅ macOS 有 | ⚠️ **本行 2026-09-23 更正**：官方桌面端在 macOS 上确实接入系统 autofill（见 §4 的说明），不是"无对应物"。Vitrine 的等价物是 app 内的 macOS AutoFill 凭据提供者扩展 |
| 截图 / 录屏防护 | ✅ | ❌ | ❌ 无对应物 |
| PIN 解锁 | ✅ | ✅ | ⚠️ 可做，但与生物识别重复 |
| 生物识别解锁 | ✅ | ✅ | ✅ 已有 |
| SSH Agent | ❌ | ✅（含 macOS） | ✅ **值得做** |
| Passkey 存储与使用 | ✅ 扩展 + 手机 | ✅ 创建与使用 | ⚠️ **本行 2026-09-23 更正**：官方 macOS 桌面端是系统 passkey 提供者（`autofill_provider/README.md`），**能创建、能使用**，不只是查看/编辑。Vitrine 只能列出，差距比本行原先承认的大 |
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
> - 写入路径：`VaultItem.preserved`（`PreservedCipherFields` + `JSONValue`）承载 Vitrine 不解释的线上字段，
>   `toRawCipher` 原样回传，因此「保存」不再等于「删除」。
> - 缓存补丁：新增 `VaultItem.with(…)` 字段级复制，7 处手工重建全部改写，`organizationId` / `collectionIds` 不可能再被漏掉。
> - 组织条目：org key 缺失时**拒绝写入**（抛错），不再静默退回个人密钥。
> - TOTP：真正的 RFC 6238 动态码生成。
> - favicon：默认只从账号自己的服务器取图标，且可一键关闭。
>
> 验证：`swift build` 零警告；新增 62 条单元测试全绿；全量 544 条测试中 10 条失败均为既有的
> 「测试包缺资源」问题（`Assets.car` / EFF 词表不在 SwiftPM 测试包里），与本次改动无关。
> 另外在 `dist/Vitrine.app` 二进制里确认 `icons.bitwarden.net` 命中数为 **0**。
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

**影响**：用户如果同时在手机/浏览器上用 Bitwarden 存了 passkey，在 Vitrine 里编辑同一个登录项的任意字段（哪怕只改个备注）并保存，服务端的 `fido2Credentials` 会被清空 —— **passkey 静默消失，且没有任何提示**。

**✅ 已修复**：`RawLoginData` 增加 `fido2Credentials`，`CipherMapper.map` 把它收进 `VaultItem.preserved`，`toRawCipher` 原样回传。字段始终以 EncString / 原始 JSON 形态搬运，**从不解密**——没有界面显示它，解密只会扩大攻击面。同时发现同一根因还波及 `passwordRevisionDate`、`autofillOnPageLoad`、`archivedDate`（缺失时服务端会执行 **un-archive**），一并纳入。

> 服务端行为已对 Vaultwarden 源码逐一核对：`update_cipher_from_data` 中 `key`、`password_history`、`archived_date` 是无条件赋值，`login` 对象整体原样落库，只有 `attachments2` 有 `if let Some(..)` 保护（因此不传附件是安全的）。

### 2.3 `passwordHistory` 完全不读取 → 编辑即丢

**证据**：`RawCipher.swift` 中 `passwordHistory` 出现 **0** 次；全树无 `passwordHistory` / `password_history` 命中。

**影响**：与 2.2 同源。官方客户端有「密码历史」视图（`VaultItem` 级别的旧密码列表）；Vitrine 既不显示，也可能在保存时把服务端记录抹掉。

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

## 3. 功能对比矩阵（逐条核实，2026-09-21）

> **这一节的每个状态都是核实过的，不是转述的。**核实方式写在每行的"依据"里：
> `[码]` 读到代码 ｜ `[官]` 读到官方文档 ｜ `[测]` 本次会话实测（含单测） ｜ `[?]` **没验成**。
>
> **为什么不直接照抄官方文档的"官方"列**：本文件此前那一版给了大量 ✅，但**其中至少两次是凭空发明**（见 §8）。所以"官方"列现在只写能给出出处的东西。

图例：✅ 已实现 ｜ ⚠️ 部分实现 ｜ ❌ 缺失 ｜ 🚫 **确认不是缺口**（官方没有，或有理由不做）｜ ❓ **未验证**

### 3.1 解锁与认证

| 功能 | 官方 | Vitrine | 依据 / 说明 |
|---|---|---|---|
| 主密码登录 | ✅ | ✅ | `[码]` |
| 主密码解锁（纯本地） | ✅ | ✅ | `[码]` 解锁不发网络请求 |
| 生物识别解锁 | ✅ | ✅ | `[码]` 含嵌入式 `LAAuthenticationView` |
| **PIN 解锁** | ✅ `[官]` | ✅ | `[官]`"mobile apps, browser extensions, and **desktop apps** can be unlocked with a PIN"；`[测]` 已实现，PBKDF2(210k)+每机随机 salt 包裹金库密钥，5 次失败擦除并登出 |
| 超时 "On app restart" 模式 | ✅ | 🚫 | Vitrine **启动即无条件锁定**（有存储账号就进 `.unlock`），重启也必然销毁内存 —— **该模式的行为已经成立**，加进去只是给两个只差标签的选项 |
| 两步登录：TOTP / Email / YubiKey OTP | ✅ | ✅ | `[官]`+`[测]` 三种可完成 |
| 两步登录：Duo / FIDO2 / WebAuthn | ✅ | ❌ | `[官]` 官方有；**不是低成本**：WebAuthn/FIDO2 要实现 CTAP2 流程 |
| 两步登录：**恢复码** | ✅ | 🚫 | **有意拒绝**：Vaultwarden 接受恢复码会删掉账号上**所有** 2FA 方法（`delete_all_by_user`） |
| 记住设备 | ✅ | ✅ | `[测]` 原本 token 解码后丢弃、勾选框无效果；现已持久化并在下次登录重放（按账号匹配邮箱） |
| **登录后管理 2FA 方式** | ✅ | 🚫 | `[官]` 官方原话是"visiting the **web app** and choosing Settings → Security → Two-step login" —— **没有桌面端流程**。在 Vitrine 里做是**超出**官方 |
| 账号指纹短语 | ✅ | ✅ | `[码]` 阶段 2 已实现，测试钉官方向量 |
| 多账号 / 切换 | ✅ | ❌ | `[码]` 单个 `activeUserId` |
| 自动锁定：睡眠 / 屏保 / 锁屏 | ✅ | ✅ | `[码]` 但**硬编码一律锁定、不可配置**（比官方严；见 §4 说明） |
| 自动锁定：空闲超时 | ✅ | ✅ | `[码]` |
| 超时动作（锁定 / 登出） | ✅ | ✅ | `[码]` |
| 新设备登录验证 / Login with device | ✅ | ❓ | 未验证官方桌面端形态 |

### 3.2 条目类型与字段

| 功能 | 官方 | Vitrine | 依据 / 说明 |
|---|---|---|---|
| 5 种条目类型 | ✅ | ✅ | `[码]` login / secureNote / card / identity / sshKey |
| **安全笔记子类型（9 种）** | ✅ | ✅ | `[测]` 原本**静默丢失**（`toRawCipher` 硬编码 `type: 0`，导出也永远写 0），现已往返；用 `.unknown(Int)` 而非封闭枚举 |
| **卡品牌下拉 + 月/年选择器** | ✅ | ✅ | `[测]` 原为自由文本框；不在列表里的值保留 |
| 自定义字段 4 种类型 + `linkedId` | ✅ | ✅ | `[码]` 含 linkedId 选择器 |
| Passkey | ✅ | ⚠️ | `[码]` **只能列出**；`PasskeyCredential` 无 `keyValue`，不能创建、不能登录 |
| 密码历史 | ✅ | ✅ | `[码]` |
| **条目整体版本历史** | 🚫 | 🚫 | `[官]` 官方**只有密码历史**，没有整条版本快照 → Vitrine **已对齐** |
| 归档（Archive） | ✅ | ❌ | `[码]` **官方桌面端有**：`bitwarden/clients` 的 `apps/desktop/src/vault/app/vault-v3/vault-items/vault-cipher-row.component.ts` 里有 `archive()` 动作，`libs/common` 的 cipher 领域/视图/数据三层都有 `archivedDate`。**这是真缺口**，不是"无对应物"。Vitrine 目前只在 wire 上往返回字段、无 UI（本行先前的 ❓ 与"未验证前不做"已撤销） |

### 3.3 组织与整理

| 功能 | 官方 | Vitrine | 依据 / 说明 |
|---|---|---|---|
| 文件夹 / 集合 CRUD / 收藏 | ✅ | ✅ | `[码]` |
| **收藏置顶** | ✅ | ✅ | `[官]` **已核完，且结论与先前相反**。官方原文是一整句："Items marked as a favorite will appear at the top of your Vault view in **browser extensions and mobile apps**, and in the **Favorites filter** in your web vault and **desktop apps**." 先前只引了前半句。**桌面端是 Favorites 筛选器，不是置顶** —— 所以 Vitrine 不置顶是**对齐**，不是缺口 |
| 组织：成员 / 组 / 组授权 / 策略 / org API key / 管理员视图 | ✅ | ❌ | `[码]` 只有 collection CRUD |
| 条目移入 / 移出组织 | ✅ | ❌ | `[码]` 没有任何地方写 `draft.organizationId` |
| 集合权限往返 | ✅ | ✅ | `[测]` **原本是真 bug**：改名 PUT 送空 `groups/users`，会**清空该集合其他成员/组的授权**（`externalId` 同样被抹掉）。现已把三者**不透明地原样往返**（`PreservedCollectionFields`），含未知权限字段 |
| 回收站（软删/恢复/永久删/清空） | ✅ | ✅ | `[码]` |
| 回收站保留期提示 | ✅ | ✅ | `[测]` 已加"会被自动永久删除"，但**不写天数**——那是服务端设置，Vitrine 没有读它的端点 |
| 附件上传 / 下载 / 删除 | ✅ | ✅ | `[码]` 含 premium 402 门禁 |
| 附件批量上传 | 🚫 | ✅ | `[官]` 官方附件**全是单文件操作**（Choose File / 逐文件 Download / 逐文件 Delete）→ **Vitrine 的拖放批量上传是超出官方** |
| 附件批量下载 / 删除 / 多选 | 🚫 | ❌ | 同上：官方没有 → **不是缺口** |
| 生成器：password / passphrase | ✅ | ✅ | `[码]` |
| 生成器：username | ✅ | ✅ | `[测]` 形状 `word.word<digits>`，独立于口令的设置 |
| 生成器：转发邮箱 | ✅ | 🚫 | **有意拒绝**：需经第三方转发，与"不把秘密送出去"冲突 |

### 3.4 工具

| 功能 | 官方 | Vitrine | 依据 / 说明 |
|---|---|---|---|
| 导出：未加密 JSON | ✅ | ✅ | `[码]` 且**五类条目全导**——官方未加密格式反而**不含**卡/身份/Passkey/SSH key |
| 导出：CSV | ✅ | ✅ | `[测]` 已实现，列与编码**逐条对齐官方导入条件文档**（含官方示例行逐字节复现）；只导登录行并**报告省略数量** |
| 导出：加密 JSON / 附件 ZIP | ✅ | ❌ | `[官]` 只公开了键名，**派生方式与 `encKeyValidation_DO_NOT_EDIT` 的含义没写**。加密备份只在紧急时才会被使用，**格式靠猜的备份比没有备份更糟** |
| 导入：加密 JSON | ✅ | ❌ | 明确报错而非静默失败；需要与加密导出同一批未公开细节 |
| 健康报告：weak / reused / unsecured / 缺 2FA | ✅ | ✅ | `[码]` |
| 健康报告：密码陈旧（官方无此项） | — | ✅ | `[码]` |
| 健康报告：已泄露密码（HIBP） | ✅ | 🚫 | **有意拒绝**：需把密码材料发往第三方，界面明写 |
| 健康报告：数据泄露检查 | ✅ | 🚫 | 同上 |
| 健康报告：inactive-2FA | ✅ | ⚠️ | `[码]` 用本地启发式（有密码无 TOTP 种子）代替查 `2fa.directory` |
| TOTP 动态码 | ✅ | ✅ | `[码]` 单条目详情页，含倒计时与复制 |
| **TOTP 汇总列表** | ✅ `[官]` | ✅ | 官方有独立的 "Bitwarden Authenticator"（一屏列出所有码）。Vitrine 已加：工具栏打开，列出全库带 TOTP 密钥的登录项。**re-prompt 条目在此列表中仍需主密码**，与详情页同一道门禁 |
| SSH agent | ✅ | ✅ | `[码]` **需非沙箱构建** |
| 证书固定 / 自定义 CA | ✅ | ✅ | `[码]` |
| **Send** | ✅ | ❌ | `[码]` 端点 / 模型 / 加密 / UI **全无**；是**独立加密路径**（密钥从分享 URL fragment 派生），不是"再加个条目类型" |

### 3.5 同步与离线

| 功能 | 官方 | Vitrine | 依据 / 说明 |
|---|---|---|---|
| 解锁后自动同步 | ✅ | ✅ | `[码]` |
| 手动同步（⌘R / 按钮） | ✅ | ✅ | `[码]` |
| 后台 / 定时同步 | ✅ | ✅ | `[测]` 解锁期间每 5 分钟 + 回前台 / 唤醒；锁定即停；失败只记日志不弹横幅 |
| 离线读取 | ✅ | ✅ | `[测]` 只读缓存（密文），界面标明"离线"及数据时间 |
| 离线写入队列 | ✅ | ❌ | 需 WAL + revisionDate 校验 |
| 冲突检测 / 合并 | ✅ | ❌ | `[码]` `revisionDate: nil`，无 `If-Match`/409 处理。**注意**：这**不代表**服务端放弃了乐观锁——那是服务端行为，本仓库证不出来 |

### 3.6 界面与集成

| 功能 | 官方 | Vitrine | 依据 / 说明 |
|---|---|---|---|
| 剪贴板自动清空（可配） | ✅ | ✅ | `[码]` |
| 主密码 re-prompt | ✅ | ✅ | `[码]` 密码 / TOTP / 隐藏字段 / 密码历史 |
| 服务端 API / identity / icons URL 覆盖 | ✅ | ⚠️ | `[码]` 模型有、生产只传 `nil`、**且 client 根本不用**（直接拼 `base`），只有 `iconsURL` 被消费 |
| 界面语言 | 多语言 | ✅ | `[码]` en / zh-Hans 运行时切换，双语 key 对齐 |
| 搜索增强：高级过滤器 / 查询限定符 | ✅ | ❓ | 未验证官方桌面端形态 |
| 全局快速搜索 / Spotlight / 菜单栏驻留 | ✅ | ❓ | 同上，未验证 |

---

## 4. 缺口分级（按"确认是缺口"重排）

**P0 —— 已确认的缺口，成本低**

| 项 | 依据 | 粗估 |
|---|---|---|



**P1 —— 已确认的缺口，成本中等**

| 项 | 依据 | 粗估 |
|---|---|---|
| 账号生命周期端点（改主密码 / 邮箱 / KDF / 删号 / 设备管理 / API key） | `[码]` 端点层零实现 | 大 |
| 组织管理（成员 / 组 / 策略 / org API key） | `[码]` 只有 collection CRUD | 大 |
| 条目移入 / 移出组织 | `[码]` 无入口 | 中 |
| 离线写入队列 + 冲突处理 | `[码]` 需 WAL | 大 |
| Passkey 创建 / 使用 | `[码]` 连 `keyValue` 字段都没有 | 大（且要浏览器扩展才能在浏览器里用） |

**P2 —— 大工程 / 受外部条件阻塞**

| 项 | 说明 |
|---|---|
| **Send** | 新加密路径 + 新 API + 新 UI |
| 多账号 | 单 `activeUserId` 改账号列表，牵动钥匙串 / UI / 同步 |
| Duo / WebAuthn 2FA | CTAP2 流程 |
| **浏览器自动填充** | **阻塞于 Apple Developer Program 成员资格** —— 扩展与公证都需要真实 Team ID，本仓库当前 `DEVELOPMENT_TEAM` 为空，构建靠关签名绕 |

**先验证再排期（❓ 的项）** —— 这些**不要**在验证前动工：

搜索增强的桌面端形态、新设备登录验证、"Login with device"。

> 2026-09-23 复核后从本表移出两项：**归档（已确认为真缺口，见 §3.2 的 ❌ 行）** 与 **收藏置顶（已确认为对齐，撤销）**。
> 两项都因为拿到了 `bitwarden/clients` 的源码而不再是 ❓，而源码比 `bitwarden.com/help` 可靠——help 站点有大量页面 404
> （`/help/archive/`、`/help/advanced-search/` 都是），拿不到页面**不等于**功能不存在。这正是本表当初把归档误标为 ❓ 的原因。
>
> 顺带记下一条更重要的：**系统级自动填充与 passkey 的"官方桌面端 ❌"也是错的**。`apps/desktop/desktop_native/autofill_provider/`
> 有一个打进 app bundle `PlugIns` 的 Swift 原生扩展，接入 macOS 原生凭据/autofill API，目前提供 passkey 的注册与使用。
> 也就是说官方 macOS 桌面端**是系统级 passkey 提供者**，而 §1.2 那张表写的是"桌面端 ❌、无对应物"。

---

## 5. 建议路线图

```
阶段 0  必修（会丢数据 / 会泄露）                       ✅ 已完成
阶段 1  日常可用性补齐                                 ✅ 已完成
阶段 2  数据主权与安全工具                             ✅ 已完成
阶段 3  离线与后台
        └ 离线只读缓存 ✅ · 后台定时同步 ✅ · 离线写入 ❌

阶段 4  会话与完整性（2026-09-21 新增，均为安全/数据性质）
        └ 会话 teardown（锁定真正清空明文 + 锁/同步竞态）✅
          测试偏好域隔离 ✅
          SSH 指纹不再被抹掉 ✅
          解不出的条目不再静默消失 ✅
          安全笔记子类型不再被重置 ✅
          集合权限不再被改名清空 ✅
          记住设备 ✅ · PIN 解锁 ✅

阶段 5  功能全集对齐（进行中）
        └ CSV 导出 ✅ · 未做：加密导出 / 附件 ZIP（格式细节未公开）
          已确认缺口：组织管理
          条目移入/移出组织 · 账号生命周期 · Send · 多账号
          Passkey 创建/使用 · Duo/WebAuthn · 浏览器自动填充（受账号阻塞）
```

---

## 6. 不适用项（macOS 上不要照搬）

| 官方手机端功能 | 为什么不做 |
|---|---|
| Autofill Services（Android/iOS 系统级填充） | macOS 无对应物；等价能力需要 Safari App Extension，属独立工程 |
| 截图 / 录屏防护 | iOS/Android 专有 API |
| 导出到其他 App（FIDO CXP） | 仅 iOS 26+ / Android 10+ |
| 手机端 Send 的 100MB 限制 | 桌面端为 500MB |

---

## 7. 待决策

1. **「睡眠/锁屏时锁定」要不要变成用户可关的？** 官方把它当超时选项之一，Vitrine **硬编码一律锁定**（`PrizmApp.swift:603-621`）。那是**比官方更严的保护**，放开它意味着用户选 `Never` 之后合盖不再锁。**当前决定：不改。** 若改，需要单独一个 change + 单独的安全说明。
2. **浏览器自动填充**要不要做？它是密码管理器最核心的能力，但**需要 Apple Developer Program 成员资格**（扩展 + 公证），目前 `DEVELOPMENT_TEAM` 为空。
3. **❓ 那几项**（归档、收藏置顶的桌面端行为、搜索增强）需要先拿到一手来源再排期。

---

## 8. 这份文档自己犯过的错（2026-09-21 逐条核对时发现）

**这一节留着，是为了不再犯。**

| 原文写的 | 实情 |
|---|---|
| 类型 6/7/8（银行账户 / 证件）会静默消失 | 代码三处都写类型 1–5 对齐 Bitwarden，**6/7/8 的存在无法证实**。真问题是"任何原因解不出都无声"（已修）—— **本条的后半句在 2026-09-23 被推翻**：官方 `libs/common/src/vault/enums/cipher-type.ts` 明写 `BankAccount: 6`、`DriversLicense: 7`、`Passport: 8`。它们确实存在，而 `CipherMapper.mapContent` 对 1–5 之外直接抛 `unsupportedCipherType`，所以这类条目在 Vitrine 里读不出、导不出。**这是一个真缺口，不是"无需证实"** |
| 附件"只能批量上传，不能批量下载/删除" | 官方附件**全是单文件操作**。**把 Vitrine 的优势写成了缺陷** |
| 强度估算 `O(n²)` 导致健康报告卡死 | 实为**线性**；复用检查走哈希表 |
| SSH agent `semaphore.wait()` 会卡死 App | 只阻塞**单条连接线程**，主线程不受影响 |
| 归档"未建模" | wire 上已往返（`PreservedCipherFields.archivedDate`），**只是没 UI** |
| `revisionDate: nil` 使服务端乐观锁失效 | 送 `nil` 是事实；"服务端因此放弃乐观锁"是**服务端行为，本仓库证不出来** |
| §3.1 把 PIN / Email / YubiKey 2FA / 账号指纹 / 空闲超时 / 超时动作 / 记住设备 标为 ❌ | **全部已实现**（大部分在阶段 1/2 就做了） |
| 摘要称 i18n「479 键」 | 实际 **525 键**（此后又增加） |
| 称证书固定"握手本身未覆盖" | 握手已实现，缺的是**测试覆盖** |
| 把"登录后管理 2FA"和"条目整体版本历史"当缺口 | 官方**都不提供**（前者指向 web app，后者只有密码历史） |

**结论性教训：`缺失了什么` 这类断言错得最多 —— 既可能把已有能力看成没有，也可能凭空发明官方行为。** 每个 change 开工前先核一手来源（`bitwarden.com/help/<topic>/` 或代码），再决定做不做。

---

*本文为工作文档，用于确定 `openspec/changes/` 的范围。核实日期 2026-09-21，对应测试基线 1389 / 0。*

*2026-09-23 复核：测试基线实测 **1566 / 0**（本机 Xcode 27，`xcodebuild test`）。本次复核改了五处，全部因为拿到了
`bitwarden/clients` 的源码：归档与类型 6/7/8 由 ❓/存疑 改为**确认缺口**；收藏置顶改为**确认对齐**；
"系统级自动填充"与"Passkey"两行由"桌面端无对应物"改为**官方桌面端已具备**。
教训与 §8 同源，但方向相反：这次不是把已有能力看成没有，而是**因为拿不到 help 页面就以为功能不存在**。
核实官方行为优先读 `bitwarden/clients` 源码——help 站点的 404 不是证据。*
