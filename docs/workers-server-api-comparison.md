# Workers 与主库 Server API 功能对比

生成日期：2026-07-07

后续实施优先级见：[`docs/workers-api-implementation-priority.md`](./workers-api-implementation-priority.md)。

本文档基于当前仓库静态代码扫描和人工归类，对 `workers` 目录中的 Cloudflare Workers 实现与主库 Bitwarden Server API 进行功能面盘点。对比范围包括：

- Workers：`workers/src/index.ts`、`workers/src/routes/*`、相关 service/schema。
- 主库基准：`src/Api`、`src/Identity`、`src/Icons`、`src/Events`、`src/Notifications`、`src/Billing`、`src/EventsProcessor` 中的 Controller/Startup 映射，以及 IdentityServer 的核心 token/discovery 端点。

路径说明：

- 主库 `src/Api` Controller 的相对路由按 `/api/...` 归一。
- 主库 `src/Identity` 按 `/identity/...` 归一。
- `~/...` 根路径端点按实际根路径记录。
- `src/Billing` 是独立 Billing 服务，本文在统计时用 `/billing/...` 作为归类命名空间，不代表上游真实 URL 前缀。
- Workers 中存在一些兼容性重复挂载，例如 `/organizations/licenses/...` 与 `/api/organizations/licenses/...`，以及 `/hub` 与 `/notifications/hub`。
- `src/Admin` 是后台管理 Web/MVC 应用，很多 action 依赖默认 MVC route，不属于官方客户端/API 复刻主线；本轮统计未把它计入 648 个 API 端点基数。
- IdentityServer 会在运行时生成更多 OIDC/OAuth 框架端点；本轮静态统计只手动计入 `/identity/connect/token` 和 discovery 核心端点。若目标是完整 SSO/OIDC 兼容，需要以运行时 discovery document 再做一次补充核实。

## 深度核实结果

远端上游已核实到 `upstream/main`：

- upstream remote：`https://github.com/bitwarden/server.git`
- upstream/main：`7f4872b5f43046b2be9ef4eaf247168d7f51a33d`
- 本地工作分支：`9320f525f0c662c39642f098ff210eaa7e201448`

静态抽取结果：

| 口径 | 数量 | 说明 |
|---|---:|---|
| Workers Hono 路由 | 235 | 包含重复兼容挂载，如 `/hub` 与 `/notifications/hub`。 |
| 上游 API 端点 | 648 | 包含 Api/Identity/Icons/Events/Notifications/Billing/EventsProcessor，不含 Admin MVC 后台。 |
| 方法+路径精确匹配 | 179 | 参数名、路径前缀必须完全一致。 |
| 精确未匹配 | 469 | 包含 `{orgId}` vs `{id}` 这种参数名差异。 |
| 参数名归一后匹配 | 227 | 把 `{orgId}`、`{id}`、`:id` 统一视为同一种路径占位符。 |
| 参数名归一后仍未覆盖 | 421 | 这是更接近真实“端点形状缺口”的数量。 |

按上游服务划分的缺口：

| 上游服务 | 上游端点数 | 参数名归一后未覆盖 |
|---|---:|---:|
| `src/Api` | 604 | 406 |
| `src/Billing` 独立服务 | 9 | 6 |
| `src/Events` | 4 | 1 |
| `src/Icons` | 7 | 3 |
| `src/Identity` | 13 | 3 |
| `src/Notifications` | 8 | 2 |
| `src/EventsProcessor` | 3 | 0 |

结论：Workers 不包含所有上游 API。当前更准确的定位是“覆盖官方客户端个人/家庭自托管核心路径的一部分兼容实现”，不是完整上游 API 面复刻。

## 总体结论

Workers 当前已覆盖官方客户端最核心的个人密码库链路：注册/登录、同步、Cipher CRUD、Folder CRUD、基础 Send、组织/集合/成员/群组/策略的主要管理、TOTP/WebAuthn、设备 token、图标、实时通知 Hub、部分报表和自建组织 License。

但它还不是主库 Server API 的完整复刻。缺口主要集中在：

- Billing/支付/发票/订阅/计划/供应商账单。
- Secrets Manager 全模块。
- Public API 全模块。
- Provider/MSP 管理全模块。
- Send 文件传输完整链路。
- 设备信任、Web Push、设备 CRUD 完整链路。
- 邮箱/YubiKey/Duo 等完整 2FA 和组织 2FA 禁用。
- 高级 Cipher 兼容别名、partial update、admin variant、附件验证/下载/分享。
- 组织高级能力：邀请链接、域名验证、Slack/Teams 集成、组织 auth requests、组织导入导出、赞助。
- Notification Center、Push 注册/删除、安装实例、SSO cookie vendor、HIBP。

## 覆盖矩阵

| 功能域 | Workers 状态 | 主库对应范围 | 备注 |
|---|---:|---|---|
| 健康检查/版本 | 已实现 | `/alive`、`/now`、`/version` | Workers 返回固定 `2025.1.0` 版本。 |
| Identity 登录注册 | 部分实现 | `src/Identity`、IdentityServer | 有 prelogin、register、token；缺 SSO flow、trial verification、OIDC discovery 细节。 |
| Accounts 基础账户 | 部分实现 | `src/Api/Auth/Controllers/AccountsController.cs` | profile、keys、password、avatar、email token 等已覆盖；高级验证/删除恢复/SSO/TDE/KDF/API key 缺失。 |
| Account Key Management | 部分实现 | `src/Api/KeyManagement` | 仅覆盖 rotate-user-account-keys；缺 key connector、key rotation data、regenerate/rotate user keys。 |
| Sync | 已实现 | `Vault/SyncController` | 已聚合用户数据、组织、集合、组、策略、send/cipher/folder 等。语义仍需客户端全量验证。 |
| Ciphers | 部分实现 | `Vault/CiphersController`、`Tools/ImportCiphersController` | CRUD、批量、归档/删除/恢复、附件、导入、分享/移动部分已做；缺若干 admin/partial/附件兼容端点。 |
| Folders | 部分实现 | `Vault/FoldersController` | CRUD 已做；缺 `POST /delete` alias 和 delete-all。 |
| Sends | 部分实现 | `Tools/SendsController` | 基础 Send CRUD/access 已做；文件 Send 链路未完整实现。 |
| Organizations 核心 | 部分实现 | `AdminConsole/OrganizationsController`、`Billing/OrganizationsController` | 创建/读取/更新/删除/leave、key、api-key、订阅最小响应已做；账单、赞助、域名、邀请链接等缺失。 |
| Organization Members | 部分实现 | `OrganizationUsersController` | 邀请、接受、确认、重发、更新、移除、revoke/restore 已做；缺 auto-confirm、delete-account、account recovery、enable SM、invite-link accept 等。 |
| Organization Collections | 部分实现 | `CollectionsController` | 组织内集合 CRUD/details 已做；缺公共 API 版本和部分用户集合路由。 |
| Organization Groups | 部分实现 | `GroupsController` | 组 CRUD/details/users 已做；缺删除用户 alias、公共 API 版本等。 |
| Policies | 部分实现 | `PoliciesController` | org policy list/get/put/vnext/token/master-password 已做；缺公共 API policy。 |
| Collections 用户视角 | 部分实现 | `AdminConsole/CollectionsController.GetUser` | `/api/collections`、`/:id` 已做。 |
| Two-Factor | 部分实现 | `TwoFactorController` | TOTP、WebAuthn、disable、recover 已做；缺 Duo/YubiKey/Email/device verification settings，组织 disable。 |
| WebAuthn | 已实现 | `WebAuthnController` | 凭据列表、注册、更新、删除、attestation/assertion options 已做。 |
| Auth Requests | 部分实现 | `AuthRequestsController` | 创建、列表、pending、response、put 已做；缺 admin-request。 |
| Devices | 部分实现 | `DevicesController` | known device、列表、identifier、token、clear-token 已做；缺设备 CRUD、keys、trust、web-push、deactivate。 |
| Events | 部分实现 | `Dirt/EventsController`、`src/Events` | Workers 有 `/api/events` 和 `/api/events/collect`；缺 cipher/org/provider/SM 范围事件查询，`/events/collect` 根路径未对齐。 |
| Reports/DIRT | 部分实现 | `Dirt/ReportsController`、`OrganizationReportsController` | 仅 password-health apps 查询、latest、create、member-cipher-details；缺 member-access、report lifecycle/file/data。 |
| Emergency Access | 占位实现 | `EmergencyAccessController` | 路由结构存在，但代码注释说明不做真实应急访问数据存储和密钥托管。 |
| Settings | 已实现 | `SettingsController` | equivalent domains GET/PUT/POST 已做。 |
| Icons | 部分实现 | `src/Icons` | `/:hostname/icon.png` 和 `/icons/:hostname/icon.png` 已做；缺 `/config`、`/change-password-uri`。 |
| Notifications/Hub | 部分实现 | `src/Notifications`、SignalR Hub | WebSocket Hub/negotiate 已做；缺 `/send`、Notification Center API、Push 注册类 API。 |
| Tasks | 占位/部分实现 | `SecurityTaskController` | list/organization/metrics 返回空或简化；缺 complete、bulk-create。 |
| Self-host org license | 部分实现 | `SelfHostedOrganizationLicensesController` | upload/update/sync 路径存在；sync 为 204，license 更新为最小实现。 |
| Billing | 基本未实现 | `src/Api/Billing` | 仅少量订阅/metadata/license 最小响应；支付、发票、订阅变更、预览税费、provider billing 均缺。 |
| Secrets Manager | 未实现 | `src/Api/SecretsManager` | projects/secrets/service accounts/access policies/counts/trash/versions/import-export/events 全缺。 |
| Public API | 未实现 | `src/Api/AdminConsole/Public`、`Dirt/Public` | public collections/groups/members/policies/organization/events 全缺。 |
| Providers/MSP | 未实现 | `AdminConsole/Provider*`、`Billing/Provider*` | provider、provider users/orgs/clients/billing 全缺。 |
| Platform extras | 未实现 | Push、Installations、SSO cookie vendor、HIBP | 均未复刻。 |

## Workers 已实现功能清单

### 基础与平台

- `GET /`：健康 JSON。
- `GET /alive`、`GET /now`、`GET /version`。
- CORS、尾部斜杠归一、统一错误响应。
- Cron scheduled cleanup：清理过期 Send、Cipher trash、refresh token 等，部分实现为 Workers 简化删除。

### Identity

- `POST /identity/accounts/prelogin`
- `POST /identity/accounts/prelogin/password`
- `POST /identity/accounts/register`
- `POST /identity/accounts/register/send-verification-email`
- `POST /identity/accounts/register/verification-email-clicked`
- `POST /identity/accounts/register/finish`
- `GET /identity/accounts/webauthn/assertion-options`
- `POST /identity/connect/token`

已覆盖的功能：邮箱注册、prelogin KDF 参数、密码 grant/refresh token、WebAuthn 登录断言选项。  
注意：邮件验证相关端点偏兼容/简化。

### Accounts

- 注册兼容：`POST /api/accounts/register`
- 用户资料：`GET/PUT/POST /api/accounts/profile`
- 修订时间：`GET /api/accounts/revision-date`
- 订阅最小响应：`GET /api/accounts/subscription`
- 密钥：`GET/POST /api/accounts/keys`
- 密码：`POST /api/accounts/password`、`POST /api/accounts/password-hint`
- 头像：`PUT /api/accounts/avatar`
- 密码校验与安全戳：`POST /api/accounts/verify-password`、`POST /api/accounts/security-stamp`
- 邮箱变更：`POST /api/accounts/email-token`、`PUT /api/accounts/email`
- 删除账号：`DELETE /api/accounts`
- 密钥轮换：`POST /api/accounts/key-management/rotate-user-account-keys`

简化点：邮箱 token 不真正发邮件；订阅返回自托管最小兼容结构。

### Sync

- `GET /api/sync`

同步响应聚合：

- 用户 profile/security stamp/revision。
- folders。
- ciphers、attachments、collections 映射。
- sends。
- organizations、organization users、collections、groups、policies。
- domains/equivalent domains。

### Ciphers

已覆盖：

- 查询：`GET /api/ciphers`、`GET /api/ciphers/:id`、`GET /api/ciphers/:id/details`、`GET /api/ciphers/:id/admin`
- 组织视图：`GET /api/ciphers/organization-details`、`GET /api/ciphers/organization-details/assigned`
- 事件兼容：`GET /api/ciphers/:id/events`
- 创建/更新：`POST /api/ciphers`、`POST /api/ciphers/create`、`PUT/POST /api/ciphers/:id`
- 归档/取消归档：`PUT /api/ciphers/:id/archive`、`PUT /api/ciphers/archive`、`PUT /api/ciphers/:id/unarchive`、`PUT /api/ciphers/unarchive`
- 软删除/恢复/硬删除：`PUT/POST /api/ciphers/delete`、`PUT/POST /api/ciphers/delete-admin`、`PUT /api/ciphers/:id/delete`、`PUT /api/ciphers/:id/restore`、`PUT /api/ciphers/restore`、`PUT /api/ciphers/restore-admin`、`DELETE /api/ciphers`、`DELETE /api/ciphers/:id`、`DELETE /api/ciphers/admin`、`POST /api/ciphers/purge`
- 集合和分享：`PUT /api/ciphers/:id/collections-admin`、`POST /api/ciphers/bulk-collections`、`PUT/POST /api/ciphers/share`、`PUT /api/ciphers/move`
- 导入：`POST /api/ciphers/import`、`POST /api/ciphers/import-organization`
- 附件：`POST /api/ciphers/:id/attachment`、`POST /api/ciphers/:id/attachment-admin`、`POST /api/ciphers/:id/attachment/v2`、`POST /api/ciphers/:id/attachment/:attachmentId`、`GET /api/ciphers/:id/attachment/:attachmentId`、`GET /api/ciphers/:id/attachment/:attachmentId/renew`、`DELETE /api/ciphers/:id/attachment/:attachmentId`、`DELETE /api/ciphers/:id/attachment/:attachmentId/admin`
- 公开附件下载：`GET /attachments/:cipherId/:attachmentId`

### Folders

- `GET /api/folders`
- `GET /api/folders/:id`
- `POST /api/folders`
- `PUT/POST /api/folders/:id`
- `DELETE /api/folders/:id`

### Sends

- 访问：`POST /api/sends/access/:id`
- 列表/详情：`GET /api/sends`、`GET /api/sends/:id`
- 创建/更新：`POST /api/sends`、`PUT /api/sends/:id`
- 删除：`DELETE /api/sends/:id`
- 移除密码：`PUT /api/sends/:id/remove-password`

当前主要是基础 Send，文件 Send 传输链路未完整对齐。

### Organizations/Admin Console

已覆盖的组织核心：

- `POST /api/organizations`
- `GET/PUT/POST/DELETE /api/organizations/:id`
- `POST /api/organizations/:id/delete`
- `POST /api/organizations/:id/leave`
- `POST /api/organizations/:id/keys`
- `GET /api/organizations/:id/public-key`
- `GET /api/organizations/:id/keys`
- `POST /api/organizations/:id/api-key`
- `POST /api/organizations/:id/rotate-api-key`
- `GET /api/organizations/:id/api-key-information/:type?`
- `GET /api/organizations/:id/subscription`
- `GET /api/organizations/:id/billing/vnext/self-host/metadata`
- `GET /api/organizations/:id/plan-type`
- `GET /api/organizations/:id/auto-enroll-status`
- `GET /api/organizations/connections/enabled`

成员管理：

- `GET /api/organizations/:id/users`
- `GET /api/organizations/:id/users/mini-details`
- `GET /api/organizations/:id/users/:orgUserId`
- `POST /api/organizations/:id/users/invite`
- `POST /api/organizations/:id/users/:orgUserId/accept`
- `POST /api/organizations/:id/users/:orgUserId/confirm`
- `POST /api/organizations/:id/users/confirm`
- `POST /api/organizations/:id/users/public-keys`
- `PUT/PATCH /api/organizations/:id/users/:orgUserId/revoke`
- `PUT/PATCH /api/organizations/:id/users/revoke`
- `PUT/PATCH /api/organizations/:id/users/:orgUserId/restore`
- `PUT /api/organizations/:id/users/:orgUserId/restore/vnext`
- `PUT/PATCH /api/organizations/:id/users/restore`
- `PUT /api/organizations/:id/users/:orgUserId`
- `POST /api/organizations/:id/users/:orgUserId/reinvite`
- `DELETE /api/organizations/:id/users/:orgUserId`
- `POST /api/organizations/:id/users/:orgUserId/remove`
- `PUT /api/organizations/:id/users/:orgUserId/reset-password-enrollment`

集合管理：

- `GET /api/organizations/:id/collections`
- `GET /api/organizations/:id/collections/details`
- `GET /api/organizations/:id/collections/:collectionId/details`
- `POST /api/organizations/:id/collections`
- `PUT /api/organizations/:id/collections/:collectionId`
- `DELETE /api/organizations/:id/collections/:collectionId`
- `DELETE /api/organizations/:id/collections`
- `POST /api/organizations/:id/collections/delete`
- `PUT /api/organizations/:id/collection-management`

群组管理：

- `GET /api/organizations/:id/groups`
- `GET /api/organizations/:id/groups/details`
- `GET /api/organizations/:id/groups/:groupId/details`
- `GET /api/organizations/:id/groups/:groupId/users`
- `POST /api/organizations/:id/groups`
- `PUT /api/organizations/:id/groups/:groupId`
- `DELETE /api/organizations/:id/groups/:groupId`

策略：

- `GET /api/organizations/:id/policies`
- `GET /api/organizations/:id/policies/token`
- `GET /api/organizations/:id/policies/invited-user`
- `GET /api/organizations/:id/policies/master-password`
- `GET /api/organizations/:id/policies/:type`
- `PUT /api/organizations/:id/policies/:type`
- `PUT /api/organizations/:id/policies/:type/vnext`

组织 2FA Duo：

- `GET /api/organizations/:id/two-factor`
- `POST /api/organizations/:id/two-factor/get-duo`
- `PUT/POST /api/organizations/:id/two-factor/duo`

### Collections 用户视角

- `GET /api/collections`
- `GET /api/collections/:id`

### Auth Requests

- `POST /api/auth-requests`
- `GET /api/auth-requests/:id/response`
- `GET /api/auth-requests`
- `GET /api/auth-requests/pending`
- `GET /api/auth-requests/:id`
- `PUT /api/auth-requests/:id`

### Two-Factor 与 WebAuthn

Two-Factor：

- `GET /api/two-factor`
- `POST /api/two-factor/get-authenticator`
- `PUT/POST /api/two-factor/authenticator`
- `DELETE /api/two-factor/authenticator`
- `PUT/POST /api/two-factor/disable`
- `POST /api/two-factor/get-recover`
- `GET/POST /api/two-factor/recover`
- `POST /api/two-factor/get-webauthn`
- `POST /api/two-factor/get-webauthn-challenge`
- `PUT/POST /api/two-factor/webauthn`
- `DELETE /api/two-factor/webauthn`

WebAuthn：

- `GET /api/webauthn`
- `POST /api/webauthn/attestation-options`
- `POST /api/webauthn`
- `POST /api/webauthn/assertion-options`
- `PUT /api/webauthn`
- `POST /api/webauthn/:id/delete`

### Devices

- `GET /api/devices/knowndevice`
- `GET /api/devices`
- `GET /api/devices/identifier/:identifier`
- `PUT /api/devices/identifier/:identifier/token`
- `PUT /api/devices/identifier/:identifier/clear-token`

### Events/Reports/Tasks

Events：

- `GET /api/events`
- `POST /api/events/collect`
- `GET /api/organizations/:id/events`

Reports：

- `GET /api/reports/password-health-report-applications/:orgId`
- `GET /api/reports/organizations/:orgId/latest`
- `POST /api/reports/organizations/:orgId`
- `GET /api/reports/member-cipher-details/:orgId`

Tasks：

- `GET /api/tasks`
- `GET /api/tasks/organization`
- `GET /api/tasks/:orgId/metrics`

### Emergency Access

Workers 提供了完整路由外形，但代码注释说明为自托管占位实现：

- trusted/granted/detail/policies。
- invite/reinvite/accept/confirm/initiate/approve/reject/takeover/password/view。
- update/delete aliases。
- attachment read。

这些端点不做真实托管密钥和应急访问状态机。

### Settings/Users/Icons/Notifications/License

Settings：

- `GET/PUT/POST /api/settings/domains`

Users：

- `GET /api/users/:id/public-key`

Icons：

- `GET /:hostname/icon.png`
- `GET /icons/:hostname/icon.png`

Notifications Hub：

- `GET /hub`
- `GET /anonymous-hub`
- `POST /hub/negotiate`
- `GET /notifications/hub`
- `GET /notifications/anonymous-hub`
- `POST /notifications/hub/negotiate`

Self-host organization license：

- `POST /organizations/licenses/self-hosted`
- `POST /organizations/licenses/self-hosted/:id`
- `POST /organizations/licenses/self-hosted/:id/sync/`
- 同时支持 `/api/organizations/licenses/...` 兼容路径。

## 已覆盖但需要标记为“部分/简化”的功能

- `workers/src/routes/emergency-access.ts`：明确是占位实现，不存储真实应急访问数据，不托管密钥。
- `workers/src/routes/tasks.ts`：自建暂无安全任务表，返回空列表，避免客户端 404。
- `workers/src/routes/accounts.ts`：订阅为最小兼容响应；邮箱变更验证码不真实发送。
- `workers/src/routes/organization-licenses.ts`：上传/更新 license 为最小兼容；sync 仅返回 204。
- `workers/src/routes/reports.ts`：password health applications 返回空数组；组织报表只实现 latest/create/member-cipher-details 子集。
- `workers/src/routes/organizations.ts`：组织 API key、Duo、删除组织密码校验、订阅等多处为自托管简化实现。
- `workers/src/services/scheduled.ts`：过期数据清理使用 Workers 简化删除逻辑。
- `workers/src/routes/ciphers.ts`：部分批量/分享端点返回空对象或 204，需逐项与上游事件、revision、通知语义对齐。

## 主库存在但 Workers 未实现的功能

### Identity/SSO

未实现：

- `/identity/.well-known/openid-configuration` 及完整 IdentityServer discovery/JWKS/authorize/logout/check-session 等框架端点。
- `GET /identity/sso/Login`
- `GET /identity/sso/PreValidate`
- `GET /identity/sso/ExternalChallenge`
- `GET /identity/sso/ExternalCallback`
- `POST /identity/accounts/trial/send-verification-email`

影响：SSO 登录、企业 SSO、完整 OAuth/OIDC 兼容性不足。

### Accounts/Auth 高级功能

未实现：

- account API key：`POST /api/accounts/api-key`、`POST /api/accounts/rotate-api-key`
- 删除恢复：`POST /api/accounts/delete`、`delete-recover`、`delete-recover-token`
- 邮箱验证：`verify-email`、`verify-email-token`
- OTP/新设备验证：`request-otp`、`verify-otp`、`resend-new-device-otp`
- KDF 更新：`POST /api/accounts/kdf`
- 组织列表：`GET /api/accounts/organizations`
- SSO/TDE：`sso/user-identifier`、`DELETE /api/accounts/sso/{organizationId}`、`set-password`、`update-temp-password`、`update-tde-offboarding-password`
- 设备验证开关：`verify-devices`
- Key Connector：`set-key-connector-key`、`convert-to-key-connector`、`key-connector/enroll`、`key-connector/confirmation-details/{orgSsoIdentifier}`
- 密钥管理数据/轮换：`key-management/regenerate-keys`、`rotate-user-keys`、`key-rotation-data`
- `GET /api/users/{id}/keys`

### Billing/Payments/Plans/Licenses

基本未实现。缺口包括：

- Account billing vnext：credit、discounts、license、payment-method、portal-session、premium checkout、subscription create/update/reinstate/storage、upgrade。
- Account billing legacy：billing history、invoices、transactions、cancel、license upload。
- Organization billing：subscription purchase/update/plan-change/cancel/reinstate/storage/payment-method/portal-session/invoices 等。
- Provider billing：provider subscription/payment/portal/invoices/clients/orgs billing。
- Preview invoice：premium/organization purchase、upgrade、tax、proration。
- Stripe setup/tax：`/setup-intent/bank-account`、`/setup-intent/card`、`/tax/is-country-supported`。
- Plans/licenses：`/api/plans`、`/api/plans/premium`、`/api/licenses/user/{id}`、`/api/licenses/organization/{id}`。
- Sponsorship：cloud/self-hosted families-for-enterprise、revoke、delete、sponsored list。
- 独立 `src/Billing` 服务 webhook/IPN/recovery：Apple IAP、BitPay IPN、PayPal IPN、Stripe webhook、Stripe recovery inspect/process。

Workers 仅有：

- `GET /api/accounts/subscription` 最小响应。
- `GET /api/organizations/:id/subscription` 最小响应。
- `GET /api/organizations/:id/billing/vnext/self-host/metadata`。
- self-host organization license upload/update/sync 的最小兼容。

### Ciphers/Vault 缺口

未实现或未完整对齐：

- `PUT/POST /api/ciphers/{id}/admin`
- `GET /api/ciphers/{id}/full-details`
- `PUT/POST /api/ciphers/{id}/partial`
- `PUT/POST /api/ciphers/{id}/collections`
- `PUT/POST /api/ciphers/{id}/collections_v2`
- `POST /api/ciphers/{id}/collections-admin`
- `PUT/POST /api/ciphers/{id}/share`
- `PUT /api/ciphers/{id}/restore-admin`
- `POST /api/ciphers/{id}/delete`、`POST /api/ciphers/{id}/delete-admin`
- `POST /api/ciphers/move`
- `GET /api/ciphers/attachment/download`
- `POST /api/ciphers/attachment/validate/azure`
- `GET /api/ciphers/{id}/attachment/{attachmentId}/admin`
- `POST /api/ciphers/{id}/attachment/{attachmentId}/delete`
- `POST /api/ciphers/{id}/attachment/{attachmentId}/delete-admin`
- `POST /api/ciphers/{id}/attachment/{attachmentId}/share`

注意：Workers 已有一部分等价能力，但缺少上游兼容 alias 或 admin/v2/partial 变体；官方客户端某些版本可能会调用这些路径。

### Folders 缺口

未实现：

- `POST /api/folders/{id}/delete`
- `DELETE /api/folders/all`

### Sends 缺口

未实现：

- `POST /api/sends/{encodedSendId}/access/file/{fileId}`
- `POST /api/sends/access`
- `POST /api/sends/access/file/{fileId}`
- `POST /api/sends/file/v2`
- `POST /api/sends/file/validate/azure`
- `GET /api/sends/{id}/file/{fileId}`
- `POST /api/sends/{id}/file/{fileId}`
- `PUT /api/sends/{id}/remove-auth`

影响：Send 文件上传、续签、下载、带访问令牌文件下载、移除认证不完整。

### Devices 缺口

未实现：

- `GET/POST/PUT/DELETE /api/devices/{id}`
- `POST /api/devices`
- `POST /api/devices/{id}/deactivate`
- `PUT/POST /api/devices/{identifier}/keys`
- `POST /api/devices/{identifier}/retrieve-keys`
- `POST /api/devices/identifier/{identifier}/token`
- `POST /api/devices/identifier/{identifier}/clear-token`
- `PUT/POST /api/devices/identifier/{identifier}/web-push-auth`
- `GET /api/devices/knowndevice/{email}/{identifier}`
- `POST /api/devices/update-trust`
- `POST /api/devices/untrust`
- `POST /api/devices/lost-trust`

### Two-Factor 缺口

未实现：

- YubiKey：`get-yubikey`、`PUT/POST /yubikey`
- Duo user：`get-duo`、`PUT/POST /duo`
- Email 2FA：`get-email`、`send-email`、`send-email-login`、`PUT/POST /email`
- Device verification settings：`GET/PUT /device-verification-settings`
- Organization disable：`PUT/POST /organizations/{id}/two-factor/disable`

Workers 已有组织 Duo 配置，但路径挂在 `/api/organizations/:id/two-factor/...`；主库同时有根路径覆盖形式 `/organizations/{id}/two-factor/...`。

### Auth Requests 缺口

未实现：

- `POST /api/auth-requests/admin-request`
- `GET/POST/PUT... /api/organizations/{orgId}/auth-requests` 组织 auth request 管理。

### Organizations 高级缺口

组织核心缺口：

- organization export：`GET /api/organizations/{organizationId}/export`
- organization import：`POST /api/public/organization/import`
- organization domain：domain get/create/verify/delete、claimed domains 等。
- organization connections：除 `connections/enabled` 外的连接管理。
- organization invite link：policies、status、validate-email-domain、accept。
- organization auth requests。
- Slack/Teams integrations：redirect、create、incoming webhook。
- Organization integration CRUD/configuration CRUD。
- Organization sponsorship。
- Organization create/upgrade/billing 相关路径。

成员管理缺口：

- reset-password-details、account-recovery-details。
- reinvite bulk。
- recover-account。
- delete-account 单个/批量。
- revoke-self。
- enable-secrets-manager。
- pending-auto-confirm、bulk-auto-confirm、auto-confirm。
- invite-link accept。

集合/群组缺口：

- `POST /api/organizations/{orgId}/groups/{id}` alias。
- group bulk delete aliases 和 delete-user aliases。
- root `/collections` 用户集合视角主库端点。
- public API collections/groups/members 版本。

### Events/DIRT 缺口

未实现：

- `GET /ciphers/{id}/events`
- `GET /organizations/{id}/events` 根路径形式
- `GET /organizations/{orgId}/users/{id}/events`
- `GET /providers/{providerId}/events`
- `GET /providers/{providerId}/users/{id}/events`
- Secrets Manager 事件：`/organization/{orgId}/secrets/{id}/events`、`projects`、`service-account`
- Public events：`GET /api/public/events`
- Events service 根路径：`POST /events/collect`

Workers 当前有 `/api/events`、`/api/events/collect`、`/api/organizations/:id/events`，路径和范围均不完整。

### Reports/DIRT 缺口

未实现：

- `GET /api/reports/member-access/{orgId}`
- password health application create/delete/bulk create。
- organization report by id、patch、delete。
- report file validate/upload/download/renew。
- report summary data get/patch。
- report application data get/patch。

### Secrets Manager 缺口

整个模块未实现：

- Projects：list/create/get/update/delete。
- Secrets：list/create/get/update/delete/get-by-ids/sync。
- Secret versions：list/get/get-by-ids/restore/delete。
- Trash：list/empty/restore。
- Service accounts：list/create/get/update/delete。
- Access tokens：list/create/revoke。
- Access policies：potential grantees、project people、project service accounts、service account people、granted policies、secret policies。
- Counts：organization/project/service-account SM counts。
- Import/export：`/api/sm/{organizationId}/export`、`/api/sm/{organizationId}/import`。
- Events：`/api/sm/events/service-accounts/{serviceAccountId}`。
- Request access：`/api/request-access/request-sm-access`。

### Public API 缺口

整个 Public API 未实现：

- `/api/public/collections`
- `/api/public/groups`
- `/api/public/members`
- `/api/public/policies`
- `/api/public/organization/import`
- `/api/public/events`

### Providers/MSP 缺口

整个 provider 管理未实现：

- `/api/providers`
- `/api/providers/{providerId}/users`
- `/api/providers/{providerId}/organizations`
- `/api/providers/{providerId}/clients`
- `/api/providers/{providerId}/billing`
- `/api/providers/{providerId}/billing/vnext`
- provider scoped events。

### Notifications/Push 缺口

未实现：

- Notifications service：`POST /send`
- Notification Center API：`GET /api/notifications`、`PATCH /api/notifications/{id}/read`、`PATCH /api/notifications/{id}/delete`
- Push registration：`POST /api/push/register`
- Push delete：`POST /api/push/delete`
- Push organization membership：`PUT /api/push/add-organization`、`PUT /api/push/delete-organization`
- Push send：`POST /api/push/send`

Workers 的 Durable Object Hub 已提供实时 WebSocket 能力，但不是主库通知/推送 API 的完整替代。

### Icons 缺口

未实现：

- `GET /config` icons service config。
- `GET /change-password-uri`
- `GET /change-password-uri/config`

### Platform/其它缺口

未实现：

- API 服务条件性健康检查：`/healthz`、`/healthz/extended`（非 self-hosted 配置下启用）。
- Installations：`GET/POST /api/installations`
- SSO cookie vendor：`GET /api/sso-cookie-vendor`
- HIBP：`GET /api/hibp/breach`
- root tax/setup intent 等 billing utility。

## 建议复刻优先级

### P0：官方客户端基础兼容闭环

1. 补齐 Send 文件链路：`file/v2`、renew、upload existing file、access file、validate 或 Workers/R2 等价返回。
2. 补齐设备信任和 Web Push 相关端点：device CRUD、keys、retrieve-keys、trust/untrust/lost-trust、web-push-auth。
3. 补齐 Cipher 高风险兼容 alias：admin put/post、collections/v2、partial、attachment validate/download/delete alias/share。
4. 校准 `/api/sync` 对 organizations、groups、collections、policies、sends、attachments 的 response model 字段。
5. 将 `/events/collect` 与 `/api/events/collect` 路径兼容起来。

### P1：组织管理可用性

1. 组织 invite link、domain、auth requests。
2. 成员 auto-confirm、recover-account、delete-account、enable-secrets-manager 字段兼容。
3. Slack/Teams integration 和 organization integrations/configurations。
4. Reports organization report lifecycle/file/data。

### P2：安全与登录高级能力

1. Email/YubiKey/Duo 2FA 完整实现。
2. SSO/TDE/Key Connector 相关 accounts 和 identity flow。
3. IdentityServer discovery/JWKS/authorize/logout 等 OIDC 兼容端点。

### P3：商业/管理/API 扩展

1. Billing/Plans/Licenses/Stripe/Preview invoice。
2. Public API。
3. Provider/MSP。
4. Secrets Manager。
5. Notification Center、Push REST、Installations、HIBP、Icons change-password-uri。

## 后续验证建议

- 为本文档中的 P0/P1 每个功能域建立端点级兼容测试，先比较状态码、错误结构、`object` 字段、Pascal/Camel 字段名和空列表形状。
- 对 `/identity/connect/token`、`/api/sync`、`/api/ciphers/*`、`/api/sends/*`、`/api/organizations/*` 建官方 Web/浏览器扩展/桌面/移动端端到端冒烟脚本。
- 复刻某个主库 Controller 前，按 `workers/AGENTS.md` 要求同步核对上游 Controller、Request/Response Model、Service、Repository、SQL migration 和 tests。
