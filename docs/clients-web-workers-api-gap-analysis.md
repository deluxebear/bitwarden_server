# Clients Web 与 Workers API 功能差距分析

生成日期：2026-07-08

本文从 `clients` 最新 Web 端页面能力出发，对照当前 `workers` API 实现，判断官方 Web 页面中哪些能力已经可用、哪些只是部分可用、哪些会因为 API 缺失或 stub 行为而不完整。

相关背景文档：

- [`docs/workers-server-api-comparison.md`](./workers-server-api-comparison.md)：Workers 与上游 server API 的端点级覆盖对比。
- [`docs/workers-api-implementation-priority.md`](./workers-api-implementation-priority.md)：按上游 API 缺口整理的实施优先级。

## 基准与方法

代码基准：

- `clients`：`b59038c200`，Web 底部版本显示为 `2026.6.4`。
- `workers`：`fd75b2d` 加当前工作区未提交改动。
- 本地手测环境：Web `https://localhost:8082/`，Workers `http://localhost:8787`。

分析方法：

- 读取 Web 路由：`clients/apps/web/src/app/oss-routing.module.ts` 及组织、设置、Billing、Reports、Vault 子路由。
- 读取 Web API service：Billing、Organization、Domain/SSO、Devices、TwoFactor、Emergency Access、Secrets Manager landing。
- 读取 Workers 入口和路由：`workers/src/index.ts`、`workers/src/routes/*`。
- 结合已手测结果：注册、登录、同步、创建 Free 组织、基础组织管理路径。

状态定义：

- **可用**：页面主流程和 API 语义基本闭环，可继续做边界测试。
- **部分可用**：主路径或读路径可用，但存在缺失端点、stub、权限/计费/同步语义不完整。
- **占位**：路由存在但返回空列表、固定值或明确未实现。
- **缺失**：clients 会请求或页面天然需要，但 workers 没有对应 API。

## 总体结论

当前 Workers 已经能支撑 Web 端的个人密码库基础流程：注册/登录、`/api/sync`、Vault Cipher CRUD、Folder、基础 Send、附件访问 token、基础组织创建、组织成员/集合/组管理的一部分、事件记录的一部分、TOTP/WebAuthn 2FA 的一部分。

Web 页面中仍明显不完整的区域主要是：

1. **Billing/订阅/支付**：Free 组织创建可用；个人 Premium、付费组织购买/升级/席位/存储/发票/付款方式多数为 stub 或缺失。
2. **SSO/OIDC**：组织域名和 SSO 配置有路由，但启用 SSO 登录会被拒绝；OIDC/SAML 登录运行时和 discovery/login flow 不完整。
3. **Secrets Manager**：Web 有入口和请求访问页，但 Workers 无完整 SM API；组织订阅 SM 的端点也缺失。
4. **高级组织能力**：Directory Connector/SCIM、赞助 Families、自动确认、账号恢复、邀请链接默认不可用或语义不完整。
5. **报表和事件**：个人报表多为客户端本地计算可用；组织报表/事件依赖付费 feature flag，Workers 只有部分 DIRT/report 端点。
6. **2FA 商业提供商**：TOTP、WebAuthn 基本可用；Duo、YubiKey、组织 Duo 明确未完整实现。
7. **Emergency Access**：路由结构存在，但多处返回空或简化数据，真实应急访问密钥托管流程不完整。
8. **Provider/MSP/Public API**：clients 中 Billing 和组织购买流程仍会引用 provider 相关 API；Workers 当前没有 provider 管理面。

## 页面功能矩阵

| Web 页面/入口 | clients 主要需求 | Workers 当前状态 | 差距与风险 | 优先级 |
|---|---|---|---|---|
| 注册 `/signup`、`/finish-signup` | `/identity/accounts/register/send-verification-email`、`/identity/accounts/register/finish`、`/identity/connect/token` | **可用** | 已兼容新版注册 finish payload；邮件验证本地为兼容/简化，不是真实邮件闭环。 | P0 |
| 登录 `/login` | prelogin、token password grant、2FA challenge、sync | **可用/部分** | 普通密码登录可用；SSO、设备登录、Passkey 登录需要单独验证。 | P0 |
| WebAuthn 登录 `/login-with-passkey` | `/identity/accounts/webauthn/assertion-options`、`/identity/connect/token` webauthn | **部分可用** | assertion options 和 token 逻辑存在，但浏览器 Passkey 端到端未全量验证。 | P1 |
| 设备登录 `/login-with-device`、`/login-initiated` | `/api/auth-requests/*`、`/api/devices/*`、通知 Hub | **部分可用** | auth requests、devices trust 路由存在；设备信任、密钥取回、通知一致性仍需端到端验证。 | P1 |
| 新设备验证 `/new-device-verification` | known device、email verification、device token | **部分可用** | `/devices/knowndevice`、device token 路由存在；真实邮件投递和验证语义偏简化。 | P1 |
| 锁定/解锁 `/lock` | 本地解密 + sync/token refresh | **可用** | 主要依赖客户端本地状态；服务端风险较低。 | P0 |
| 密码提示 `/password-hint` | `/api/accounts/password-hint` | **部分可用** | 端点存在；邮件发送语义通常为本地/日志兼容。 | P2 |
| 删除账号恢复 `/recover-delete`、`/verify-recover-delete` | 删除恢复 token、验证删除 | **缺失/部分** | accounts 有直接删除账号；recover-delete token flow 未完整覆盖。 | P2 |
| 个人 Vault `/vault` | `/api/sync`、`/api/ciphers/*`、`/api/folders/*`、icons | **可用/部分** | CRUD、归档、删除、恢复、导入、附件已较完整；仍需全量验证 Cipher 类型、字段、事件、推送一致性。 | P0 |
| 个人附件 | R2 上传下载、短期 access token、renew、delete | **部分可用** | Workers 已补 access token/匿名下载入口；需验证多客户端、过期、权限、组织附件分享。 | P0 |
| Send `/sends` | `/api/sends/*`、公开 `/send/:sendId/:key` | **部分可用** | 文本 Send 和基础访问可用；文件 Send、密码/过期/访问次数完整语义仍需测试。 | P0 |
| Tools Import | `/api/ciphers/import`、`/api/ciphers/import-organization` | **部分可用** | 个人/组织导入端点存在；组织导入对 `maxCollections` 有检查，但 Free 组织限制语义不完整。 | P1 |
| Tools Export | 主要本地 sync 数据导出 | **可用/部分** | 个人导出多依赖本地数据；组织导出取决于组织权限和 sync 内容，需验证。 | P2 |
| Password Generator | 本地功能 | **可用** | 基本不依赖 Workers。 | P3 |
| 个人 Reports `/reports/*` | breach check、sync 中 ciphers、Premium guard | **部分可用** | 重用/弱密码等多为本地计算；Premium guard 取决于 `/accounts/subscription`/profile premium；真实 HIBP 数据泄露检查未确认。 | P2 |
| Account Settings `/settings/account` | profile、avatar、email token、delete | **部分可用** | profile/avatar/email/password 端点存在；邮箱 token 不是真实邮件闭环，删除恢复流程不完整。 | P1 |
| Appearance | 本地设置 | **可用** | 不依赖 Workers。 | P3 |
| Security: password | `/api/accounts/password`、verify password | **可用/部分** | 改主密码端点存在；密钥轮换、组织 reset password 联动需验证。 | P1 |
| Security: 2FA | `/api/two-factor/*` | **部分可用** | TOTP、Email、WebAuthn、恢复码基础存在；Duo/YubiKey 明确未实现或返回错误。 | P1 |
| Security: security keys | `/api/webauthn/*` | **部分可用** | 管理 Passkey/security key 路由存在；需浏览器端到端验证 attestation/assertion。 | P1 |
| Security: devices | `/api/devices/*` | **部分可用** | 列表、deactivate、trust keys/token/web-push-auth 路由存在；新设备信任和 web push 仍需验证。 | P1 |
| Data Recovery | 组织账号恢复相关 API | **部分/缺失** | Workers 有 reset-password enrollment 和 recover-account 部分端点；密钥材料语义高风险，不能视为完整。 | P1 |
| Domain Rules | `/api/settings/domains` | **可用** | GET/PUT/POST 已实现。 | P2 |
| Emergency Access | `/api/emergency-access/*` | **占位/部分** | 路由齐，但 trusted/granted 默认空，真实 invite/accept/confirm/initiate/takeover 密钥流程需深测。 | P2 |
| Sponsored Families | 组织 sponsorship/billing API | **缺失** | Web 页面存在；Workers 没有完整 sponsorship API。 | P3 |
| Create Organization `/create-organization` | `/api/plans`、setup-intent、billing preview、`/api/organizations` | **Free 可用，付费部分占位** | Free 组织已手测成功；Teams/Enterprise/Families 购买依赖 fake setup intent 和 billing stub，真实支付不可用。 | P0/P2 |
| 组织 Vault `/organizations/:id/vault` | org ciphers、collections、permissions、sync | **部分可用** | 组织 cipher/collection 基础可用；权限矩阵、admin 全量访问、事件/推送一致性需验证。 | P0 |
| 组织 Members | users invite/accept/confirm/revoke/restore/remove | **部分可用** | 核心成员流程存在；席位限制未强制，自动确认、账号恢复、SM enable、delete-account 高级路径不完整。 | P1 |
| 组织 Groups | `/organizations/:id/groups/*` | **部分可用** | Teams/Enterprise plan flag 才应可用；Workers 有 CRUD，但 Free 组织 UI 通常隐藏，后端有 useGroups 校验。 | P1 |
| 组织 Collections | `/organizations/:id/collections/*` | **部分可用** | CRUD、details、bulk access 存在；需要校验 readOnly/hidePasswords/manage 与 sync 一致。 | P1 |
| 组织 Settings: account | org get/update/delete/license | **部分可用** | 基础信息可更新；license/self-host 部分路径存在；delete-recover-token 缺失。 | P1 |
| 组织 Settings: two-factor | org 2FA/Duo | **部分可用/缺失** | provider 列表和 Duo 配置部分存在，组织 2FA disable 有路由；真实 Duo 登录不可用。 | P2 |
| 组织 Policies | `/organizations/:id/policies/*` | **部分可用** | list/get/put/vnext/token/master-password 等存在；策略实际执行面需逐项验证。 | P1 |
| 组织 Tools Import/Export | org import/export | **部分/缺失** | import-organization 存在；组织导出依赖 sync，本身没有独立 server export API。 | P2 |
| 组织 Reporting: events | `/organizations/:id/events`、`/api/events` | **部分可用** | useEvents 仅 paid org 开启；Free org 默认不可见。事件写入和查询范围需验证。 | P2 |
| 组织 Reporting: reports | `/api/reports/*` | **部分可用** | password health report applications、organization report file/data 有部分实现；前端付费报表全链路未验证。 | P2 |
| 组织 Billing subscription/payment/history | `/organizations/:id/subscription`、billing vnext、invoices/transactions、upgrade/seat/storage | **占位/缺失** | `/subscription` 和若干 vnext stub 存在；`/billing`、`/billing/history`、`/upgrade`、`/seat`、`/storage`、`/billing/invoices`、`/billing/transactions` 缺失。 | P2 |
| 个人 Billing premium/payment/history | `/plans/premium`、`/account/billing/vnext/*`、`/accounts/billing/*`、checkout | **占位/缺失** | plans 和 history 空列表可读；premium checkout、cancel、真实付款方式缺失。 | P2 |
| Secrets Manager landing `/sm-landing`、`/request-sm-access` | `/request-access/request-sm-access`、组织 SM subscription | **缺失** | Web 有入口；Workers 无 `/request-access/request-sm-access`，无完整 projects/secrets/service-accounts/access-policies API。 | P2 |

## 功能域详解

### 1. 认证、注册、登录

Workers 已实现：

- `/identity/accounts/prelogin`
- `/identity/accounts/prelogin/password`
- `/identity/accounts/register`
- `/identity/accounts/register/send-verification-email`
- `/identity/accounts/register/verification-email-clicked`
- `/identity/accounts/register/finish`
- `/identity/accounts/webauthn/assertion-options`
- `/identity/connect/token`
- `/api/accounts/register`

当前状态：

- 新版 Web 注册 finish payload 已兼容，避免 “Email and master password hash are required.”。
- 普通登录、refresh token、sync 基础链路可用。
- 2FA challenge 在 token route 中有实现，但不同 provider 语义不完全一致。

差距：

- 真实邮件验证、密码提示邮件、新设备验证邮件仍是兼容实现，不是完整邮件服务。
- SSO/OIDC 登录运行时缺失，见 SSO 小节。
- Passkey 登录和新设备登录虽然有端点，但需要端到端验证浏览器 WebAuthn/设备信任数据。

### 2. Sync 与基础 Vault

Workers 已实现 `/api/sync`，聚合：

- profile、account keys、KDF/user decryption。
- folders、ciphers、sends。
- organizations、organization users、collections、groups、policies。
- equivalent domains。

当前状态：

- 个人 Vault 基础使用可用。
- 组织 Vault 能通过 sync 获得组织、集合、权限和组织 cipher。

差距：

- 需要全量验证所有 Cipher 类型字段：Login、Secure Note、Card、Identity、SSH Key、TOTP、FIDO2 credential、reprompt、favorite、archive、trash。
- 组织权限需要验证：只读、隐藏密码、manage、admin all access、custom permissions。
- 每次写操作后的 `revisionDate`、事件、push notification、sync 刷新需要端到端验证。

### 3. Cipher、附件、分享

Workers 已覆盖大部分 Cipher API：

- CRUD、批量 delete/restore、archive/unarchive、purge。
- org admin variant、partial update、collections update。
- import、import-organization。
- attachment upload/download/renew/delete/share。
- 匿名附件下载：`/api/ciphers/attachment/download` 和 `/attachments/:cipherId/:attachmentId`。

当前状态：

- 基础 Cipher 和附件链路已是 Workers 当前最完整的区域之一。

差距：

- 附件 access token 需要验证过期、cipher/org 权限、删除后失效、跨用户拒绝。
- 分享到组织、组织集合迁移、bulk-collections 对 sync 和事件的一致性需要压测。
- 组织导入中有 `maxCollections` 检查，但 Free 组织的用户数/集合数限制并未整体后端强制。

### 4. Send

Workers 已实现：

- `/api/sends` 基础列表、创建、详情、更新、删除。
- `/api/sends/access`、`/api/sends/access/:id`、公开访问。
- 文件相关路径存在，包括 `/file/v2`、`/:id/file/:fileId`、公开下载。

当前状态：

- 文本 Send 基础链路应可用。
- 文件 Send 有 R2 逻辑，但还应作为重点手测对象。

差距：

- 密码保护、过期、删除时间、最大访问次数、访问计数、隐藏邮箱等服务端强制语义需验证。
- 公开文件下载 token 与过期/权限的一致性需要验证。

### 5. 个人设置与安全

Workers 已实现：

- `/api/accounts/profile`、avatar、email-token、email、password、verify-password、security-stamp。
- `/api/accounts/keys`、`/api/accounts/key-management/rotate-user-account-keys`。
- `/api/settings/domains`。
- `/api/devices/*`。
- `/api/webauthn/*`。
- `/api/two-factor/*`。

当前状态：

- 个人资料、改名、头像、改密码、TOTP、WebAuthn security key、设备列表具备基础 API。

差距：

- Email 2FA 与新设备验证依赖邮件，当前不是完整生产语义。
- Duo、YubiKey 在 `two-factor.ts` 中明确返回未实现错误。
- 设备信任、retrieve keys、web-push-auth 路由存在，但需要和登录/device auth request 联动验证。
- 账号删除恢复 token flow 不完整。

### 6. 组织创建与 Free 组织限制

Workers 已实现：

- `/api/plans`、`/api/plans/premium`。
- `/api/setup-intent/card`、`/api/setup-intent/bank-account`。
- `/api/billing/preview-invoice/*`。
- `/api/organizations` 创建。
- `/api/organizations/:id/subscription` 和部分 billing vnext stub。

已手测：

- Free 组织创建成功。
- 创建后 `/api/sync` 可返回组织。

当前 Free 组织限制：

- `buildOrgDefaults(0)` 中 Free 组织默认关闭 `useSso`、`useGroups`、`useDirectory`、`useEvents`、`use2fa`、`useApi`、`useResetPassword`、`useInviteLinks`。
- 数据库 `organizations.seats` 默认是 `5`。
- 后端邀请用户当前没有强制 seats 上限。
- 后端集合创建没有统一强制 `maxCollections`，但组织导入路径会检查 `maxCollections`。

结论：

- Free 组织在当前 Workers 中主要靠 feature flags 影响 Web UI 展示和部分后端校验。
- “用户数限制”目前不是完整后端强制规则。即使 UI 显示 Free 限制，API invite 路径仍可能允许超过默认 seats。

### 7. 组织成员、集合、组、策略

Workers 已覆盖：

- 成员：invite、accept、confirm、public-keys、reinvite、update、remove、revoke、restore。
- 集合：create、details、update、delete、users、bulk-access。
- 组：list/details/create/update/delete/users、delete-user。
- 策略：list、get、put、vnext、token、invited-user、master-password。

当前状态：

- 组织 admin console 的 Members、Vault、Collections、Groups、Policies 页面有较多基础 API 支撑。

差距：

- 高级成员路径不完整：auto-confirm、bulk auto-confirm、account recovery details、recover account、delete account、enable Secrets Manager 等需要逐项验证。
- 组功能依赖 `useGroups`，Free 组织默认不可用；Teams/Enterprise planType 创建和升级当前又依赖不完整 Billing。
- 策略“保存成功”不代表 enforcement 完整，需要逐策略验证在 Cipher、Send、注册、成员邀请、主密码等路径是否真正执行。

### 8. 组织 SSO/OIDC、域名、Directory/SCIM

Workers 已实现：

- `/api/organizations/domain/sso/verified`
- `/api/organizations/:id/domain`
- `/api/organizations/:id/domain/:domainId`
- `/api/organizations/:id/domain/:domainId/verify`
- `/api/organizations/:id/sso`

当前状态：

- 组织域名 CRUD 和验证形状存在。
- SSO 配置可保存为 disabled。

明确缺口：

- `POST /api/organizations/:id/sso` 中如果 `enabled=true`，会返回 “SSO login runtime is not implemented for this Workers deployment.”。
- OIDC/SAML discovery、authorize、callback、login runtime 未完成。
- Key Connector、SCIM、Directory Connector 页面/能力没有完整 workers API。

影响：

- Web `/sso` 登录页、组织 SSO 设置页无法完成真实登录。
- 组织域名发现 SSO 只能作为 UI/配置辅助，不能作为企业登录闭环。

### 9. Billing、订阅、支付

Workers 已实现或 stub：

- `/api/plans`、`/api/plans/premium`。
- `/api/account/billing/vnext/subscription|credit|address|payment-method|discounts`。
- `/api/accounts/billing/invoices`、`/api/accounts/billing/transactions` 返回空。
- `/api/organizations/:id/billing/vnext/self-host/metadata|warnings|address|payment-method|credit`。
- `/api/billing/preview-invoice/*`。
- `/api/setup-intent/card|bank-account` 返回 fake secret。

clients 仍会请求但 Workers 缺失的重要端点：

- `/api/account/billing/vnext/premium/checkout`
- `/api/accounts/cancel`
- `/api/organizations/:id/billing`
- `/api/organizations/:id/billing/history`
- `/api/organizations/:id/billing/invoices`
- `/api/organizations/:id/billing/transactions`
- `/api/organizations/:id/billing/vnext/metadata`
- `/api/organizations/:id/upgrade`
- `/api/organizations/:id/seat`
- `/api/organizations/:id/storage`
- `/api/organizations/:id/sm-subscription`
- `/api/organizations/:id/subscribe-secrets-manager`
- `/api/organizations/:id/billing/restart-subscription`
- `/api/organizations/:id/billing/change-frequency`
- `/api/organizations/:id/billing/setup-business-unit`
- `/api/providers/*/billing/*`

当前状态：

- Free 组织创建路径可用。
- 付费组织创建/升级路径会绕过 404 的一部分，但不能完成真实 Stripe/付款语义。
- Billing 页面可能能打开一部分，但显示空或在进一步操作时失败。

### 10. Reports、Events、Notifications

Workers 已实现：

- `/api/events`、`/api/events/collect`、`/events` 挂载。
- `/api/organizations/:id/events`。
- `/api/reports/password-health-report-applications/:orgId` 等 password health application 路径。
- `/api/reports/organizations/:orgId/*` 一批 organization report lifecycle/file/data 路径。
- `/notifications/hub`、`/hub`、`/api/push/*`、`/api/notifications/*`。

当前状态：

- 个人本地报表依赖 sync 数据，基础可用。
- 组织事件和组织报表是部分实现。
- SignalR/WebSocket 通知 Hub 有 Durable Object 支撑。

差距：

- Free 组织 `useEvents=false`，组织 Events 页面一般不可见。
- 组织报表依赖 paid org guard 和 report 数据生成流程，需完整手测。
- Notification Center 与 Push 注册/推送对多设备实时刷新仍需验证。

### 11. Emergency Access

Workers 路由覆盖：

- trusted/granted 列表。
- invite、reinvite、accept、confirm、initiate、approve、reject、takeover、password、view。
- emergency attachment view。

当前状态：

- 路由形状基本存在。
- trusted/granted 默认空，真实数据和密钥托管语义需要验证。

风险：

- Emergency Access 是高风险加密功能，不能以“路由存在”视为完成。
- 必须验证：邀请邮件/token、accept/confirm 后密钥材料、等待期、approve/reject、takeover 后 vault view、附件访问权限。

### 12. Secrets Manager

Web 入口：

- `/sm-landing`
- `/request-sm-access`
- 组织中存在 enable Secrets Manager、subscribe Secrets Manager 相关调用。

Workers 当前状态：

- 无 `/request-access/request-sm-access`。
- 无 Projects、Secrets、Service Accounts、Access Policies、SM events/counts、SM import/export 等完整 API。
- `/api/organizations/:id/users/enable-secrets-manager` 路由存在，但不代表 SM 功能闭环。
- `/api/organizations/:id/subscribe-secrets-manager`、`/sm-subscription` 缺失。

结论：

- Web 端 Secrets Manager 当前只能视为入口/广告/请求页，不是可用功能。

## 建议实施顺序

### P0：保证 Web 基础闭环

1. 全量验证并修正 Cipher：所有类型、附件 access token、分享到组织、组织集合权限、删除/恢复/归档、事件和 sync。
2. 全量验证 Send：文本和文件 Send、公开访问、密码、过期、访问次数、删除后失效。
3. 补齐 Free 组织创建后的基础组织管理：成员邀请/确认、集合、组 feature flag、组织 vault 权限。
4. 明确 Free 组织限制：如果要模拟官方 Free 限制，后端应强制 seats、collections、feature flags；否则文档/API 响应要标明自托管宽松策略。

### P1：补组织和安全高级路径

1. 设备信任、auth requests、new device verification 全链路。
2. WebAuthn/Passkey 登录和 2FA WebAuthn 端到端。
3. 组织策略 enforcement：每个 policy 保存后要在对应业务路径生效。
4. Account Recovery/Data Recovery：密钥材料不能 stub。
5. Notification Hub/Push 多设备刷新一致性。

### P2：补企业和付费页面

1. SSO/OIDC discovery/login flow：至少明确支持 OIDC 或明确隐藏/禁用 SSO 页面。
2. Billing 页面可读：`/billing`、history、invoices、transactions、metadata。
3. 付费操作要么真实接支付，要么在 UI/API 层明确不可用，避免 fake setup intent 导致前端进入 Stripe 错误。
4. Reports/Events 完整组织报表和事件审计。

### P3：后续能力

1. Secrets Manager 全模块。
2. Provider/MSP。
3. Sponsorship/Families。
4. Public API。
5. SCIM/Directory Connector/Key Connector。

## 手动验证清单

基础账号：

- 注册新用户，完成 finish signup，登录。
- 登出后用 password grant 登录。
- 刷新页面后 `/api/sync` 成功。
- 改 profile、avatar、master password、password hint。

个人 Vault：

- 新增/编辑/删除/恢复/永久删除 Login、Card、Identity、Secure Note。
- 上传、下载、删除附件；确认 token 过期和跨用户访问失败。
- 导入个人 vault，导出个人 vault。
- 创建文本 Send、文件 Send，匿名访问、密码访问、过期访问。

组织 Free：

- 创建 Free 组织。
- 邀请第二个用户，accept/confirm。
- 创建集合，分配成员权限。
- 新建组织 cipher，移动到集合。
- 验证第二个用户 sync 后权限正确。
- 尝试超过 seats 邀请，确认当前是否允许；如允许，记录为当前 Workers 行为。

组织高级：

- Teams/Enterprise 创建或升级路径：记录失败点，重点看 setup-intent、preview invoice、upgrade/seat/storage。
- 组织 groups 页面是否由 feature flag 控制。
- policies 保存后是否在对应业务路径生效。
- events/reporting 页面在 paid org 下是否能读写。

安全：

- 开启/关闭 TOTP。
- 开启/删除 WebAuthn 2FA。
- 尝试 Duo/YubiKey，确认返回明确未实现错误。
- 设备列表、deactivate、untrust、new device verification。

SSO/OIDC：

- 添加组织域名并验证。
- 保存 SSO disabled 配置。
- 尝试 enabled=true，确认当前返回未实现错误。
- `/sso` 登录页输入 identifier，记录 discovery/login 缺口。

Billing/SM：

- 打开个人 subscription、premium、payment details、billing history。
- 打开组织 billing subscription、payment details、history。
- 点击付费升级/购买，记录缺失 endpoint 或 Stripe fake secret 错误。
- 打开 `/sm-landing`、`/request-sm-access`，确认 `/request-access/request-sm-access` 缺失。

## 当前最需要修正文档/代码认知的点

- Workers 不是完整上游 Bitwarden Server API；它目前更接近“官方 Web 基础自托管兼容层”。
- Free 组织在当前 Workers 中没有完整后端席位限制，主要是 feature flag 和 UI 控制。
- Billing stubs 只能解除页面加载 404，不能代表支付/订阅功能完成。
- SSO 配置和 SSO 登录是两回事：当前只能保存 disabled 配置，不能启用登录。
- Emergency Access、Data Recovery、SSO、Billing、Secrets Manager 都涉及安全或商业关键语义，不能用空返回或假成功结束实现。
