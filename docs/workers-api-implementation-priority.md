# Workers API 复刻实施优先级

生成日期：2026-07-07

本文档用于后续新会话直接执行 Workers API 复刻工作。它基于 `docs/workers-server-api-comparison.md` 的端点覆盖核实结果整理：

- Workers Hono 路由：235 条。
- 上游静态 API 端点：648 条。
- 参数名归一后仍缺：421 条。
- 目标不是一次补齐全部上游 API，而是优先补官方客户端高频、会造成明显功能中断、且与现有 Workers 架构最贴近的接口。

实施原则：

- 先补客户端核心体验，再补企业/商业/公开 API。
- 优先补已有数据模型和 service 能承接的接口，不先引入大范围重构。
- 每个接口实现前，按 `workers/AGENTS.md` 要求核对上游 Controller、Request/Response Model、Service、Repository、SQL migration 和测试。
- 对 Cloudflare D1/R2/KV/DO 无法完全等价的地方，在代码附近写清兼容策略。
- 不要用静默成功掩盖关键状态变更；如果只能占位，文档和代码都要明确标注。

## 总体路线

建议按以下顺序推进：

1. Send 文件链路。
2. Cipher 兼容别名和附件完整链路。
3. Devices 信任、密钥、Web Push auth。
4. `/events/collect` 根路径兼容。
5. 组织 collections/groups alias。
6. 组织成员高级管理。
7. 组织邀请链接。
8. Two-Factor Email/device verification。
9. Auth Requests 组织管理侧。
10. Notification Center/Push。
11. Reports/DIRT 完整报表。
12. Organization integrations。
13. Secrets Manager。
14. Public API。
15. Billing/Provider/MSP。

## P0：官方客户端基础兼容闭环

P0 的目标是让官方 Web、浏览器扩展、桌面端、移动端在个人/家庭自托管常规使用中尽量不遇到 404 或关键能力断链。

### P0.1 Send 文件链路

优先级最高。

待实现接口：

- `POST /api/sends/file/v2`
- `GET /api/sends/{id}/file/{fileId}`
- `POST /api/sends/{id}/file/{fileId}`
- `POST /api/sends/{encodedSendId}/access/file/{fileId}`
- `POST /api/sends/access`
- `POST /api/sends/access/file/{fileId}`
- `POST /api/sends/file/validate/azure`
- `PUT /api/sends/{id}/remove-auth`

现有基础：

- `workers/src/routes/sends.ts` 已有 Send 文本 CRUD、access、remove-password。
- `workers/src/db/schema.ts` 已有 sends 数据结构。
- `workers` 已使用 R2 处理 Cipher 附件，可复用 R2 存储模式。

实现要点：

- 文件内容存 R2，metadata 存 D1。
- 对齐上游 Send response model，尤其是 `object`、`file`、`accessId`、`revisionDate`、`deletionDate`、`expirationDate`、`maxAccessCount`、`accessCount`。
- 支持公开访问路径的鉴权/密码校验语义，不能把私有 Send 文件裸暴露。
- `validate/azure` 可以返回 R2 兼容的最小成功结构，但字段名要匹配客户端预期。
- 删除 Send 时同步删除 R2 对象。

验收标准：

- 官方客户端可创建文件 Send。
- 未登录用户可按访问规则下载文件 Send。
- 密码保护、过期、最大访问次数至少在服务端生效。
- 删除 Send 后文件不可继续下载。

### P0.2 Cipher 兼容别名和附件完整链路

待实现接口：

- `PUT /api/ciphers/{id}/collections`
- `POST /api/ciphers/{id}/collections`
- `PUT /api/ciphers/{id}/collections_v2`
- `POST /api/ciphers/{id}/collections_v2`
- `POST /api/ciphers/{id}/collections-admin`
- `PUT /api/ciphers/{id}/partial`
- `POST /api/ciphers/{id}/partial`
- `GET /api/ciphers/{id}/full-details`
- `PUT /api/ciphers/{id}/admin`
- `POST /api/ciphers/{id}/admin`
- `POST /api/ciphers/{id}/delete`
- `POST /api/ciphers/{id}/delete-admin`
- `PUT /api/ciphers/{id}/delete-admin`
- `PUT /api/ciphers/{id}/restore-admin`
- `POST /api/ciphers/{id}/share`
- `PUT /api/ciphers/{id}/share`
- `POST /api/ciphers/admin`
- `POST /api/ciphers/move`
- `GET /api/ciphers/attachment/download`
- `POST /api/ciphers/attachment/validate/azure`
- `GET /api/ciphers/{id}/attachment/{attachmentId}/admin`
- `POST /api/ciphers/{id}/attachment/{attachmentId}/delete`
- `POST /api/ciphers/{id}/attachment/{attachmentId}/delete-admin`
- `POST /api/ciphers/{id}/attachment/{attachmentId}/share`

现有基础：

- `workers/src/routes/ciphers.ts` 已有 Cipher CRUD、bulk、archive、delete、restore、attachment、import、share/move 的部分实现。
- `collectionCiphers`、`ciphers`、附件 R2 逻辑已存在。

实现要点：

- 很多接口可复用现有 handler，但要保证状态码、响应体和事件/通知一致。
- admin variant 不能简单等价普通用户操作，至少要校验组织权限。
- `partial` 只更新指定字段，不应覆盖未提交字段。
- `collections_v2` 要对齐上游 collection assignment model。
- 附件下载和 validate 要兼容官方客户端期望的 direct upload/download 结构。
- 所有修改 Cipher 的接口都要更新 revision，并触发 sync/notification 所需事件。

验收标准：

- 不同版本官方客户端对 Cipher 管理路径不再出现 404。
- 个人 Cipher、组织 Cipher、附件、集合分配在 sync 中一致。
- 管理员可按权限操作组织 Cipher，普通成员越权返回正确错误。

### P0.3 Devices 信任、密钥、Web Push auth

待实现接口：

- `POST /api/devices`
- `GET /api/devices/{id}`
- `PUT /api/devices/{id}`
- `POST /api/devices/{id}`
- `DELETE /api/devices/{id}`
- `POST /api/devices/{id}/deactivate`
- `PUT /api/devices/{identifier}/keys`
- `POST /api/devices/{identifier}/keys`
- `POST /api/devices/{identifier}/retrieve-keys`
- `POST /api/devices/identifier/{identifier}/token`
- `POST /api/devices/identifier/{identifier}/clear-token`
- `PUT /api/devices/identifier/{identifier}/web-push-auth`
- `POST /api/devices/identifier/{identifier}/web-push-auth`
- `GET /api/devices/knowndevice/{email}/{identifier}`
- `POST /api/devices/update-trust`
- `POST /api/devices/untrust`
- `POST /api/devices/lost-trust`

现有基础：

- `workers/src/routes/devices.ts` 已有 known device、list、identifier、token、clear-token 的部分路径。
- 登录 token payload 已包含 device 相关信息。

实现要点：

- 梳理 devices schema 是否已覆盖 key、token、trust、web push auth；不够则新增 Drizzle schema 和 migration。
- 新设备登录、设备信任、免密码登录相关字段要与 identity/auth-requests 逻辑互通。
- Web Push auth 可以先保存订阅信息，后续 P2/P3 再接入真实 Push API。

验收标准：

- 官方客户端设备列表可读写。
- 新设备登录和设备信任流程不报错。
- 清除 token/取消信任后对应设备无法继续按旧 token 使用。

### P0.4 Events collect 根路径兼容

待实现接口：

- `POST /events/collect`

现有基础：

- Workers 已有 `POST /api/events/collect`。

实现要点：

- 在 `workers/src/index.ts` 或独立 route 增加根路径挂载。
- 复用现有 `events.ts` 收集逻辑。

验收标准：

- `/events/collect` 和 `/api/events/collect` 均可用。
- 返回状态码和错误结构一致。

## P1：组织管理可用性

P1 目标是提升组织/家庭/小团队管理体验。大部分接口可基于现有 organizations、collections、groups、organizationUsers 表扩展。

### P1.1 组织 Collections/Groups alias 和细分接口

待实现接口：

- `POST /api/organizations/{orgId}/collections/{id}`
- `POST /api/organizations/{orgId}/collections/{id}/delete`
- `GET /api/organizations/{orgId}/collections/{id}/users`
- `POST /api/organizations/{orgId}/collections/bulk-access`
- `POST /api/organizations/{orgId}/groups/{id}`
- `POST /api/organizations/{orgId}/groups/{id}/delete`
- `DELETE /api/organizations/{orgId}/groups`
- `POST /api/organizations/{orgId}/groups/delete`
- `DELETE /api/organizations/{orgId}/groups/{id}/user/{orgUserId}`
- `POST /api/organizations/{orgId}/groups/{id}/delete-user/{orgUserId}`

实现要点：

- 先补 alias，复用已存在的 PUT/DELETE handler。
- `bulk-access` 要更新 collection users/groups 的访问关系。
- 返回 details model 时注意 users/groups/readOnly/hidePasswords/manage 字段。

验收标准：

- Web Vault 组织集合和群组页面常规操作不再 404。
- 批量删除、用户移出群组、集合访问变更能在 sync 后体现。

### P1.2 组织成员高级管理

待实现接口：

- `POST /api/organizations/{orgId}/users/reinvite`
- `GET /api/organizations/{orgId}/users/{id}/reset-password-details`
- `POST /api/organizations/{orgId}/users/account-recovery-details`
- `PUT /api/organizations/{orgId}/users/{id}/recover-account`
- `PUT /api/organizations/{orgId}/users/revoke-self`
- `PUT /api/organizations/{orgId}/users/enable-secrets-manager`
- `PATCH /api/organizations/{orgId}/users/enable-secrets-manager`
- `GET /api/organizations/{orgId}/users/pending-auto-confirm`
- `POST /api/organizations/{orgId}/users/bulk-auto-confirm`
- `POST /api/organizations/{orgId}/users/{id}/auto-confirm`
- `DELETE /api/organizations/{orgId}/users/delete-account`
- `POST /api/organizations/{orgId}/users/delete-account`
- `DELETE /api/organizations/{orgId}/users/{id}/delete-account`
- `POST /api/organizations/{orgId}/users/{id}/delete-account`

实现要点：

- reset password/account recovery 涉及密钥材料，不能假成功破坏客户端密钥状态。
- delete-account 属高风险操作，应先实现为明确校验和受限能力。
- auto-confirm 可先按自托管简化策略实现，但需要事件和状态变更。

验收标准：

- 管理员成员管理页面关键按钮可用或返回明确兼容错误。
- 成员状态变化在 `/api/sync` 和 organization user list 中一致。

### P1.3 组织邀请链接

待实现接口：

- `GET /api/organizations/{orgId}/invite-link`
- `POST /api/organizations/{orgId}/invite-link`
- `PUT /api/organizations/{orgId}/invite-link`
- `DELETE /api/organizations/{orgId}/invite-link`
- `POST /api/organizations/{orgId}/invite-link/refresh`
- `POST /organizations/invite-link/status`
- `POST /organizations/invite-link/policies`
- `POST /organizations/invite-link/validate-email-domain`
- `POST /organizations/users/invite-link/accept`

实现要点：

- 需要新增 invite link token 存储，或扩展 organization 表。
- token 必须安全随机生成并可撤销。
- `VAULT_BASE_URL` 缺失时要给出明确兼容行为。

验收标准：

- 组织可创建/刷新/撤销邀请链接。
- 受邀用户可通过 invite link 加入组织。
- 域名策略和组织 policy 能影响邀请链接校验。

### P1.4 组织域名与 SSO 基础查询

待实现接口：

- `GET /api/organizations/{orgId}/domain`
- `POST /api/organizations/{orgId}/domain`
- `GET /api/organizations/{orgId}/domain/{id}`
- `DELETE /api/organizations/{orgId}/domain/{id}`
- `POST /api/organizations/{orgId}/domain/{id}/remove`
- `POST /api/organizations/{orgId}/domain/{id}/verify`
- `POST /api/organizations/domain/sso/verified`
- `GET /api/organizations/{id}/sso`
- `POST /api/organizations/{id}/sso`
- `GET /api/accounts/sso/user-identifier`

实现要点：

- 域名验证可以先支持手动 verified 或 DNS TXT 验证中的一种。
- SSO 配置不建议假成功；若不实现真实 SSO，应返回客户端可理解的 disabled 状态。

验收标准：

- 组织域名页面可正常加载。
- 未启用 SSO 时客户端不报错，启用前有明确配置状态。

## P2：安全与登录高级能力

P2 目标是补安全增强和高级登录体验，涉及外部邮件/硬件/第三方服务时要谨慎。

### P2.1 Two-Factor 补全

建议先实现 Email 2FA 和 device verification settings，再考虑 Duo/YubiKey。

待实现接口：

- `POST /api/two-factor/get-email`
- `POST /api/two-factor/send-email`
- `POST /api/two-factor/send-email-login`
- `PUT /api/two-factor/email`
- `POST /api/two-factor/email`
- `GET /api/two-factor/get-device-verification-settings`
- `PUT /api/two-factor/device-verification-settings`
- `POST /api/two-factor/get-yubikey`
- `PUT /api/two-factor/yubikey`
- `POST /api/two-factor/yubikey`
- `POST /api/two-factor/get-duo`
- `PUT /api/two-factor/duo`
- `POST /api/two-factor/duo`
- `PUT /organizations/{id}/two-factor/disable`
- `POST /organizations/{id}/two-factor/disable`

实现要点：

- Email 2FA 需要邮件发送能力；没有邮件服务时不能默认绕过安全。
- YubiKey/Duo 可先返回 disabled/unsupported，并保证 Web Vault 页面不崩。
- 组织 2FA disable 要校验组织权限。

验收标准：

- 用户 2FA 设置页面完整加载。
- Email 2FA 在配置邮件服务后可真实启用和登录验证。
- 不支持的 provider 返回明确状态，不影响 TOTP/WebAuthn。

### P2.2 Auth Requests 组织管理侧

待实现接口：

- `POST /api/auth-requests/admin-request`
- `GET /api/organizations/{orgId}/auth-requests`
- `POST /api/organizations/{orgId}/auth-requests`
- `POST /api/organizations/{orgId}/auth-requests/{requestId}`
- `POST /api/organizations/{orgId}/auth-requests/deny`

实现要点：

- 复用 `workers/src/routes/auth-requests.ts` 的数据模型。
- 和设备信任、无密码登录状态联动。
- 批量 approve/deny 要记录事件。

验收标准：

- 管理员可查看、批准、拒绝组织 auth requests。
- 被批准请求能被客户端轮询到正确结果。

### P2.3 Push/Web Push/Notification Center

待实现接口：

- `POST /api/push/register`
- `POST /api/push/delete`
- `PUT /api/push/add-organization`
- `PUT /api/push/delete-organization`
- `POST /api/push/send`
- `GET /api/notifications`
- `PATCH /api/notifications/{id}/read`
- `PATCH /api/notifications/{id}/delete`
- `POST /send`

现有基础：

- Workers 已有 Durable Object WebSocket Hub。
- `workers/src/services/push-notification.ts` 已有 hub notification helper。

实现要点：

- Push REST 和 WebSocket Hub 是两套入口，payload 要与上游类型兼容。
- Notification Center 需要 D1 表存储通知状态。
- `POST /send` 是 Notifications 服务内部发送入口，需限制调用来源或鉴权。

验收标准：

- 多客户端登录时，修改 Cipher/Folder/Send 后其他客户端能实时刷新。
- 通知中心列表、已读、删除状态持久化。

## P3：完整上游 API 面扩展

P3 适合在核心客户端体验稳定后推进。

### P3.1 Reports/DIRT 完整报表

待实现：

- `GET /api/reports/member-access/{orgId}`
- password health application create/delete/bulk create。
- organization report get/patch/delete。
- report file validate/upload/download/renew。
- report summary data get/patch。
- report application data get/patch。

### P3.2 Organization integrations

待实现：

- Slack/Teams redirect/create/incoming。
- organization integrations CRUD。
- integration configurations CRUD。

### P3.3 Secrets Manager

待实现模块：

- projects。
- secrets。
- secret versions。
- service accounts。
- access policies。
- trash。
- counts。
- import/export。
- SM events。
- request access。

注意：Secrets Manager 是独立产品面，数据模型和权限体系复杂，不建议夹在 P0/P1 中顺手实现。

### P3.4 Public API

待实现：

- `/api/public/collections`
- `/api/public/groups`
- `/api/public/members`
- `/api/public/policies`
- `/api/public/organization/import`
- `/api/public/events`

注意：Public API 通常用 OAuth client credentials，不应直接复用用户 JWT 鉴权逻辑。

### P3.5 Billing/Provider/MSP

待实现：

- account/org/provider billing。
- invoices/transactions/payment-method。
- Stripe/PayPal/BitPay/Apple webhook。
- subscriptions/preview invoice。
- provider users/orgs/clients。
- sponsorship。

注意：自托管个人/家庭场景可长期保留最小兼容响应；完整实现涉及支付、许可证、安全审计和 webhook 签名校验。

## 每轮开发建议模板

后续新会话可以直接按这个模板发起任务：

```text
请按 docs/workers-api-implementation-priority.md 中的 P0.1 实现 Send 文件链路。
要求：
1. 先核对上游 src/Api/Tools/Controllers/SendsController.cs 及相关 request/response model。
2. 复用 Workers 现有 Hono/Drizzle/R2 模式。
3. 补必要 schema/migration。
4. 实现后运行 npm run typecheck 和 npm run test。
5. 更新 docs/workers-server-api-comparison.md 与本优先级文档状态。
```

每个阶段完成后，应更新本文档对应条目的状态，例如：

- `未开始`
- `进行中`
- `已实现，待客户端验证`
- `已验证`
- `暂缓，原因：...`

## 当前推荐的第一个任务

从 P0.1 开始：Send 文件链路。

理由：

- 用户可见收益高。
- 与现有 R2 附件能力接近。
- 不需要先实现 Billing、SSO、Provider 等复杂横向模块。
- 可以顺带沉淀一套“文件上传/续签/下载/删除”的 Workers 兼容模式，后续 Cipher report file 和 attachment 能复用。
