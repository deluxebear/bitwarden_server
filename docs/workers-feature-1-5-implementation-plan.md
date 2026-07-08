# Workers 核心 1-5 功能补齐实施规划

生成日期：2026-07-08

本文按 `clients-web-workers-api-gap-analysis.md` 中“功能域详解”的前 5 项规划完整补齐：

1. 认证、注册、登录。
2. Sync 与基础 Vault。
3. Cipher、附件、分享。
4. Send。
5. 个人设置与安全。

目标是让官方 Web 客户端在个人和基础组织使用场景下形成可验证闭环：注册登录可靠、Sync 数据一致、Vault/Cipher/附件/Send 完整、个人安全设置可用，并且事件、通知、revision 与权限语义一致。

## 总体实现原则

- 先补语义和验证，再补低频兼容别名。当前很多路由已经存在，问题主要在真实邮件、边界校验、权限、事件、通知和端到端验证。
- 对密文数据只做存储和转发，不解密、不重加密、不解析 vault 明文字段。
- 所有写路径必须统一更新 revision，并记录事件、发送通知或至少保证下次 sync 可见。
- 不用假成功掩盖安全功能缺口。邮件、设备信任、WebAuthn、账号恢复等暂未完成时要明确返回可理解错误或提供开发模式路径。
- 每个模块补齐后必须用当前最新 `clients` Web 手测，并用 Workers 自动测试固化关键路径。

## 共同前置工作

### 0.1 统一事件、通知、revision

当前 Cipher、Send、Accounts、Organizations 等路由分别自行更新 revision 和事件。建议先抽象统一 service：

- `revisionService.touchUser(db, userId)`
- `revisionService.touchCipher(db, cipherId)`
- `revisionService.touchOrganization(db, organizationId)`
- `eventService.record(c, eventType, subject)`
- `notificationService.notifyUser/notifyOrganization(c, payload)`

落地原则：

- 不一次性重构全部文件，先在本规划涉及的写路径接入。
- 没有真实 push 时也要保证事件和 revision 正确，通知可先走现有 Durable Object/notification routes。

验收：

- 同一账号两个浏览器窗口中，一个窗口修改 Cipher/Send/Settings 后，另一个窗口刷新或收到通知后 sync 可见。
- 所有写接口返回前数据库 revision 已更新。

### 0.2 建立端到端测试账号脚本

建议新增 `workers/scripts/e2e-core-smoke.*` 或测试文档，覆盖：

- 创建用户 A/B。
- 登录拿 token。
- 创建组织、邀请 B。
- 创建个人 cipher、组织 cipher、附件、send。
- 调 `/api/sync` 比对字段。

验收：

- `npm run test` 中至少包含核心 API 单元/集成测试。
- 手测步骤写入文档，方便每次同步 clients 后复测。

## 1. 认证、注册、登录

### 当前实现

Workers 已有：

- `POST /identity/accounts/prelogin`
- `POST /identity/accounts/prelogin/password`
- `POST /identity/accounts/register`
- `POST /identity/accounts/register/send-verification-email`
- `POST /identity/accounts/register/verification-email-clicked`
- `POST /identity/accounts/register/finish`
- `GET /identity/accounts/webauthn/assertion-options`
- `POST /identity/connect/token`
- `POST /api/accounts/register`

已支持：

- 新版 Web 注册 finish payload。
- password grant。
- refresh token。
- webauthn grant 的基础验证。
- send_access grant。
- 登录时 device 创建/更新。
- 登录时 2FA challenge。

### 需要补齐的能力

#### 1.1 注册和邮件验证闭环

问题：

- `send-verification-email` 当前返回 token，适合本地测试，不是真实邮件闭环。
- `password-hint`、email token、新设备验证邮件也依赖同一类邮件能力。

实现：

- 新增统一邮件 service：
  - `emailService.sendRegistrationVerification(email, token)`
  - `emailService.sendPasswordHint(email, hint)`
  - `emailService.sendEmailChangeToken(email, token)`
  - `emailService.sendNewDeviceVerification(email, token)`
- 支持三种模式：
  - `EMAIL_MODE=disabled`：返回明确错误或仅本地开发返回 token。
  - `EMAIL_MODE=log`：本地日志输出 token。
  - `EMAIL_MODE=provider`：接 Cloudflare Email Service 或其它 provider。
- token 存储建议从“按 hour 计算签名”升级为数据库一次性 token：
  - `verificationTokens(id, userId?, email, type, tokenHash, expiresAt, usedAt, creationDate)`
  - token 明文只发邮件，数据库只存 hash。

验收：

- Web 注册时不需要手动复制 response token 也能完成验证。
- token 过期、重复使用、邮箱不匹配均失败。
- 本地开发模式仍可方便拿到 token。

#### 1.2 登录 token 语义补齐

实现：

- password grant：
  - 校验 deviceIdentifier、deviceType、deviceName。
  - 每次登录更新 device lastSeen。
  - 2FA challenge 返回字段与 Web 当前模型一致。
- refresh token：
  - token rotation 或至少 refresh token revoke 语义明确。
  - 登出/安全戳变更后旧 refresh token 失效。
- webauthn grant：
  - 完成 passkey 登录端到端验证。
  - challenge 必须一次性、短 TTL、防重放。
- send_access grant：
  - 验证 Send 密码、过期、最大访问次数、文件 token 一致。

验收：

- Web 普通登录、刷新页面、锁定/解锁、token refresh 都正常。
- 改主密码或 security stamp 后旧 token 失效。
- Passkey 登录成功并可 sync。

#### 1.3 新设备登录和设备信任

涉及：

- `/api/devices/knowndevice`
- `/api/devices/:identifier/keys`
- `/api/devices/:identifier/retrieve-keys`
- `/api/devices/update-trust`
- `/api/devices/untrust`
- `/api/auth-requests/*`

实现：

- 明确 device trusted/untrusted 状态机：
  - unknown -> pending verification -> trusted -> untrusted/deactivated。
- auth request approve 后写入 device trust keys。
- 新设备验证邮件通过 1.1 的邮件 service 发 token。
- `/identity/connect/token` 根据 device 状态决定是否触发 New Device Verification 或 Auth Request。

验收：

- 新浏览器首次登录出现正确验证流程。
- 已信任设备再次登录不重复要求验证。
- untrust/deactivate 后再次登录需要重新验证。

#### 1.4 SSO/OIDC 在本阶段的边界

本五项的认证登录需要处理 SSO 入口，但完整 SSO 属后续企业能力。

实现：

- `/sso` 登录页如访问 Workers 未支持的 SSO runtime，应返回明确 `unsupported` 错误，不要进入半成功状态。
- `/api/accounts/sso/user-identifier` 保持可读。

验收：

- 非 SSO 用户不受影响。
- SSO 点击不会出现未知 500/404。

### 1.x 测试清单

- 注册新用户。
- 邮件 token 过期/重复使用。
- password grant。
- refresh token。
- 开启 TOTP 后登录 challenge。
- Passkey 登录。
- 新设备登录和信任/取消信任。
- 修改 security stamp 后旧 token 失效。

## 2. Sync 与基础 Vault

### 当前实现

Workers `/api/sync` 已聚合：

- profile、account keys、KDF/user decryption。
- folders、ciphers、sends。
- organizations、organization users、collections、groups、policies。
- equivalent domains。
- attachment download url。

### 需要补齐的能力

#### 2.1 建立 Sync response contract 测试

问题：

- Sync 已能返回数据，但需要保证每类字段与 Web 2026.6.4 期望一致。

实现：

- 新增 sync fixture 测试，构造：
  - 空账号。
  - 个人 vault 全类型账号。
  - 带组织、集合、组、策略账号。
  - 带附件、Send、WebAuthn、2FA 的账号。
- 对 response 做 schema snapshot：
  - `profile.object === "profile"`
  - `ciphers[].object === "cipherDetails"`
  - `collections[].object === "collectionDetails"` 或 Web 实际期望。
  - boolean 字段必须是 JSON boolean，不是 0/1。

验收：

- Web 首屏 sync 无解析错误。
- iOS/desktop 等严格 decoder 不会因 boolean/int 混用失败。

#### 2.2 Cipher 类型全量同步

需要验证字段：

- Login：uris、username、password、totp、fido2Credentials。
- Secure Note。
- Card。
- Identity。
- SSH Key。
- reprompt、favorite、archivedDate、deletedDate。
- attachments、collectionIds、folderId。

实现：

- 对 `toCipherResponse`/sync 中 cipher formatting 建立字段映射表。
- 对每种类型创建、sync、更新、再次 sync 验证字段不丢。
- 未知字段保持透明 JSON 存储和返回。

验收：

- Web 新建每类 Cipher 后刷新页面仍能完整显示。
- 修改某个子字段不会清空其它子字段。

#### 2.3 组织权限同步

需要验证：

- owner/admin/member/custom。
- collection direct access。
- group inherited access。
- readOnly。
- hidePasswords。
- manage。
- allowAdminAccessToAllCollectionItems。
- custom permissions。

实现：

- 把 `canSyncAllOrgItems` 和 `getAllowedCollectionIds` 结果做测试。
- 对不同角色调用 `/api/sync`，确认 ciphers/collections 可见范围。
- 对 hidden password 的 response 字段与 Web 预期一致。

验收：

- 普通成员只能 sync 授权集合。
- Admin 在开启 all access 时能 sync 全部；关闭时按集合授权。
- hidePasswords/readOnly/manage 在 Web UI 表现正确。

#### 2.4 Sync 触发一致性

实现：

- 所有写路径统一调用 revision service。
- 对以下操作后立即 `/api/sync` 验证变化：
  - create/update/delete/restore cipher。
  - upload/delete attachment。
  - create/update/delete folder。
  - create/update/delete send。
  - update account profile/security。
  - org member/collection/group/policy change。

验收：

- 写操作后 `revisionDate` 前进。
- Web 刷新后看到最新数据。

### 2.x 测试清单

- 空 vault sync。
- 每种 Cipher 类型 sync。
- 组织角色矩阵 sync。
- folder/cipher/send/attachment 写后 sync。
- equivalent domains。
- account keys/user decryption。

## 3. Cipher、附件、分享

### 当前实现

Workers 已有大量 Cipher 路由：

- 查询、创建、更新、删除、恢复、归档、取消归档、purge。
- admin variant。
- partial update。
- collections update。
- bulk collections。
- import、import-organization。
- share single/many。
- attachment upload/download/renew/delete/share。
- 匿名附件下载 token。

### 需要补齐的能力

#### 3.1 Cipher 类型和字段保真

实现：

- 创建统一 `normalizeCipherRequest` 和 `toCipherDetailsResponse` 测试，不一定重构代码，但要固定映射。
- 对 Web 2026.6.4 传入的新字段保持存储和返回。
- partial update 只更新请求字段，不覆盖未提交字段。

验收：

- Web 编辑 Login 的 URI 不会丢 TOTP/FIDO2。
- Web 编辑 Card 不会丢字段。
- partial update 后其它字段保持不变。

#### 3.2 附件 access token 语义

需要验证和补齐：

- token 只绑定 cipherId + attachmentId。
- token 有过期时间。
- token 签名使用 `JWT_SECRET` 或独立 secret。
- 删除附件或 Cipher 后 token 失效。
- token 不能跨用户/组织权限绕过。
- Range/download headers 与 Web 下载兼容。

实现：

- `attachment-token.ts` 增加过期、issuer、audience、version 字段。
- 下载时重新校验 cipher 存在、attachment metadata 存在、请求用户权限或 token 来源。
- R2 metadata 与 DB attachments JSON 一致。

验收：

- 用户 A 的附件 URL 用户 B 不能下载，除非是合法短期匿名 token。
- 删除附件后旧 URL 404。
- token 过期后 404 或 Bitwarden 风格错误。

#### 3.3 组织分享和集合迁移

涉及：

- `PUT/POST /api/ciphers/:id/share`
- `PUT/POST /api/ciphers/share`
- `PUT/POST /api/ciphers/:id/collections`
- `PUT/POST /api/ciphers/:id/collections_v2`
- `POST /api/ciphers/bulk-collections`

实现：

- 分享个人 cipher 到组织时：
  - 清除 personal folder 关系。
  - 写 organizationId。
  - 写 collectionCiphers。
  - 检查目标集合权限。
  - 记录事件。
- 从一个集合迁移到另一个集合时：
  - 校验 manage 权限。
  - 维护 collectionCiphers 幂等。

验收：

- Web 分享个人条目到组织后，个人 vault 不再作为个人条目显示。
- 组织成员按集合权限看到共享条目。
- bulk collection 后 sync collectionIds 正确。

#### 3.4 导入和组织限制

实现：

- 个人 import：
  - folders、ciphers、folderRelationships 保真。
  - 导入失败应事务性回滚或记录可恢复状态。
- 组织 import：
  - collections、ciphers、collectionRelationships 保真。
  - 强制 `maxCollections`。
  - 如果决定支持 Free seats 限制，也在相关路径强制。

验收：

- 导入样例 vault 后数量和字段一致。
- 组织导入超过 collection 限制时失败且无脏数据。

#### 3.5 事件和通知

所有 Cipher 操作记录：

- create/update/delete/restore/purge。
- attachment create/delete。
- share/move/collections update。
- import。

验收：

- 组织事件页面可看到对应事件。
- 另一个已登录 Web 窗口能通过 sync 看到变化。

### 3.x 测试清单

- 六类 Cipher 创建/编辑。
- attachment upload/download/delete/renew/token expiry。
- share single/many。
- collection assignment v1/v2。
- personal import/org import。
- admin variant 权限拒绝。

## 4. Send

### 当前实现

Workers 已有：

- `/api/sends` 列表、创建、详情、更新、删除。
- `/api/sends/access`、`/api/sends/access/:id`。
- `/api/sends/file/v2`。
- `/api/sends/:id/file/:fileId`。
- `/api/sends/:id/file/:fileId/download`。
- `/api/sends/:encodedSendId/access/file/:fileId`。
- `/api/sends/access/file/:fileId`。
- `/api/sends/:id/remove-password`。
- `/api/sends/:id/remove-auth`。

代码中已存在：

- password hash/verify。
- deletionDate、expirationDate。
- maxAccessCount/accessCount。
- file R2 存储。
- 公开下载 token。

### 需要补齐的能力

#### 4.1 Send response contract 固定

实现：

- 对 Text Send、File Send、带密码、隐藏邮箱、过期、达到访问次数的 response 建立测试。
- 区分管理端 response 和匿名 access response。
- 确认 `accessId`、`object`、`file`、`text`、`password` 字段与 Web 期望一致。

验收：

- Web 创建 Text/File Send 后刷新仍显示。
- 公开 Send 页面能正确显示文本或下载文件。

#### 4.2 访问控制和计数

实现：

- accessCount 只在真正成功访问内容或签发文件下载 URL 时递增。
- 密码错误不递增。
- 达到 maxAccessCount 后立即拒绝。
- expirationDate/deletionDate 统一比较 ISO 时间，避免时区问题。
- 删除 Send 后 R2 文件一并删除。

验收：

- maxAccessCount=1 的 Send 第二次访问失败。
- 过期 Send 公开页面不可访问。
- 删除后旧下载 URL 失败。

#### 4.3 文件 Send 完整性

实现：

- 创建 `/file/v2` 返回的 upload model 与 Web 兼容。
- 上传文件后 metadata、R2 object、send.fileId 一致。
- 下载 token 绑定 sendId + fileId + access mode。
- 支持合理 Content-Type、Content-Length、Content-Disposition。

验收：

- Web 可创建文件 Send、匿名下载文件。
- 大文件不整块读入内存，保持 streaming。

#### 4.4 Send 与 sync/事件/通知

实现：

- Send create/update/delete/remove-auth 更新 revision。
- access 记录事件或至少访问计数持久化。
- `/api/sync` 中 sends 列表过滤删除/过期规则与上游一致。

验收：

- 创建/更新 Send 后 sync 可见。
- 删除 Send 后 sync 不再返回。

### 4.x 测试清单

- Text Send 无密码/有密码。
- File Send 上传/下载。
- expirationDate。
- deletionDate。
- maxAccessCount。
- remove-password/remove-auth。
- hideEmail。
- 删除后 R2 清理。

## 5. 个人设置与安全

### 当前实现

Workers 已有：

- `/api/accounts/profile`
- `/api/accounts/avatar`
- `/api/accounts/email-token`
- `/api/accounts/email`
- `/api/accounts/password`
- `/api/accounts/verify-password`
- `/api/accounts/security-stamp`
- `/api/accounts/keys`
- `/api/accounts/key-management/rotate-user-account-keys`
- `/api/settings/domains`
- `/api/devices/*`
- `/api/webauthn/*`
- `/api/two-factor/*`

### 需要补齐的能力

#### 5.1 账号资料、邮箱、密码

实现：

- profile update：
  - 更新 name、culture、avatarColor 等 Web 字段。
  - 更新 accountRevisionDate。
- email change：
  - 通过 1.1 邮件 token service。
  - token 一次性使用。
  - 新邮箱唯一性校验。
- password change：
  - 校验当前 master password hash。
  - 更新 masterPassword、key、privateKey、accountKeys、kdf 参数。
  - 变更 securityStamp。
  - revoke 旧 refresh token 或要求重新登录。
- password hint：
  - 通过邮件 service 发送，不泄漏账号是否存在。

验收：

- Web 修改个人资料成功。
- 修改邮箱必须通过 token。
- 修改主密码后旧 session/token 失效，新密码可登录并 sync 解密。

#### 5.2 2FA

当前状态：

- TOTP、Email、WebAuthn、recover、disable 路由存在。
- Duo/YubiKey 明确返回未实现。

实现：

- TOTP：
  - 生成 key、验证 code、保存 provider。
  - recover code 生成/查看/使用。
- Email 2FA：
  - 使用邮件 service 发送登录 code。
  - code 存 hash 和过期时间。
  - 登录成功后清理或轮换。
- WebAuthn 2FA：
  - challenge 短 TTL、一次性、防重放。
  - attestation/assertion 验证计数器。
- Duo/YubiKey：
  - 如果暂不支持，保持明确 unsupported，并让 Web 展示可理解错误。
  - 若要完整支持，需单独接 Duo/YubiKey provider。

验收：

- 开启 TOTP 后登录必须输入 code。
- recovery code 可恢复一次并轮换。
- Email 2FA code 过期失败。
- WebAuthn 2FA 注册、登录、删除均可用。

#### 5.3 WebAuthn/Passkey 管理

实现：

- `/api/webauthn` list/create/update/delete。
- attestation options 绑定 user + challenge。
- assertion options 绑定 credential。
- 支持重命名 credential。
- 删除后不能继续登录。

验收：

- Web Security Keys 页面可添加、重命名、删除。
- 删除 credential 后 Passkey 登录失败。

#### 5.4 设备管理

实现：

- 设备列表展示 name/type/lastSeen。
- deactivate 设备：
  - 删除或禁用 refresh tokens。
  - 取消 trust。
- update trust/untrust：
  - 写 encrypted keys。
  - 和 auth request/new device flow 联动。
- web-push-auth：
  - 存储 push endpoint/key/auth。
  - 后续通知优先使用真实 push，当前至少不 404。

验收：

- Web Device Management 页面可列出当前设备。
- deactivate 另一个设备后该设备 refresh token 失效。
- untrust 后需要重新验证设备。

#### 5.5 账号删除恢复 token flow

问题：

- 直接删除账号已存在，但 recover-delete account token flow 不完整。

实现：

- 新增 recover delete token 表或复用 verificationTokens：
  - type=`delete_account`
  - email/userId/tokenHash/expiresAt/usedAt。
- 补齐 Web 需要的发送删除邮件、验证删除 token、执行删除端点。
- 删除账号要级联或软删除：
  - ciphers、folders、sends、devices、refresh tokens、webauthn credentials。
  - 组织 owner 删除要阻止或要求先转移/删除组织。

验收：

- 未登录用户可请求删除账号邮件。
- token 有效时删除账号。
- 组织 owner 账号删除有正确限制。

#### 5.6 Domain Rules

当前 `/api/settings/domains` 已实现。

补齐：

- Web 修改后 sync 中 equivalent domains 一致。
- 空列表、重复域名、非法域名校验。

验收：

- Domain Rules 页面添加/删除后刷新仍存在。

### 5.x 测试清单

- profile/avatar/culture。
- email token change。
- master password change。
- password hint。
- TOTP enable/login/disable/recover。
- Email 2FA。
- WebAuthn 2FA。
- security keys add/rename/delete。
- devices list/deactivate/untrust。
- domain rules。
- recover delete account token flow。

## 推荐实施里程碑

### M1：认证和邮件基础

范围：

- verificationTokens 表。
- email service 三种模式。
- 注册邮件验证、password hint、email token、新设备邮件。
- token refresh/security stamp 失效。

验收：

- 注册、登录、邮箱验证、改邮箱、密码提示、新设备验证形成闭环。

### M2：Sync contract 和 Cipher 字段保真

范围：

- Sync fixture tests。
- Cipher 类型全量字段测试。
- partial update 保真。
- 组织权限 sync 测试。

验收：

- Web 创建/编辑所有 Cipher 类型后刷新不丢字段。
- 不同组织角色看到正确数据。

### M3：附件和分享闭环

范围：

- 附件 token 过期/权限/删除失效。
- 组织分享 single/many。
- collection assignment v1/v2。
- import rollback/限制。

验收：

- 附件和组织分享在多用户、多集合下正确。

### M4：Send 完整验证

范围：

- Text/File Send response contract。
- maxAccessCount、expiration、deletion、password、hideEmail。
- 文件 streaming 和 R2 清理。

验收：

- Web Send 全路径可用，公开访问行为符合预期。

### M5：个人安全设置闭环

范围：

- TOTP/Email/WebAuthn 2FA。
- Security Keys。
- Devices trust/deactivate。
- Recover delete account。
- Domain Rules。

验收：

- Web Settings/Security 所有核心页面可操作。

### M6：事件、通知、回归测试

范围：

- 把 M1-M5 所有写路径接入 event/revision/notification。
- 新增核心 API 测试和手测 checklist。

验收：

- 多窗口、多用户、组织权限场景下 sync 一致。

## 完成定义

这五项只有同时满足以下条件，才能标记为补齐：

- Web 页面主流程可手动完成。
- 相关 API 无未知 404/500。
- 安全失败路径返回 Bitwarden 风格错误。
- 写路径更新 revision，并且 `/api/sync` 能看到变化。
- 需要事件的操作有事件记录。
- 多设备场景 token、device、notification 语义一致。
- 覆盖成功、权限拒绝、过期、重复、越权、数据不存在测试。

## 建议手测路径

1. 注册 A/B 两个用户，完成邮箱验证。
2. A 登录，创建每种 Cipher，上传附件。
3. A 创建组织，邀请 B，确认 B。
4. A 分享 Cipher 到组织集合，B sync 后验证权限。
5. A 创建 Text Send 和 File Send，匿名访问并测试密码/过期/次数。
6. A 开启 TOTP，登出再登录验证 2FA。
7. A 添加 WebAuthn security key，测试 passkey 登录和删除后失效。
8. A/B 分别在两个浏览器登录，测试设备列表、untrust、deactivate。
9. A 修改邮箱、主密码、domain rules，刷新确认 sync。
10. 请求删除账号 token，验证过期/重复使用/组织 owner 限制。

## 自动化测试建议

最低测试集：

- `identity.register.finish.spec.ts`
- `identity.token.spec.ts`
- `sync.contract.spec.ts`
- `ciphers.types.spec.ts`
- `ciphers.attachments.spec.ts`
- `ciphers.share.spec.ts`
- `sends.access.spec.ts`
- `accounts.security.spec.ts`
- `devices.trust.spec.ts`
- `two-factor.spec.ts`
- `webauthn.spec.ts`

每轮实现后运行：

```bash
cd workers
npm run typecheck
npm run test
```
