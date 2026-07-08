# Cloudflare Workers 同源部署 Web Vault

本项目可以用同一个 Cloudflare Worker 同时托管：

- Bitwarden Web Vault 静态前端。
- Workers API、Identity、Sync、附件、通知等后端路由。

`workers/wrangler.toml` 使用 Workers Static Assets：

- 静态资源目录：`../clients/apps/web/build`
- SPA fallback：未命中的前端导航请求返回 `index.html`
- API 前缀通过 `run_worker_first` 先进入 Hono Worker

## 构建前端

```bash
./scripts/build-workers-web-assets.sh
```

该脚本会执行：

```bash
cd clients/apps/web
npm run dist:oss:selfhost
```

输出目录：

```text
clients/apps/web/build
```

脚本会删除 `*.map` sourcemap 文件。Workers Static Assets 单文件大小上限为 25 MiB，Web Vault 的生产 sourcemap 可能超过该限制；运行时不需要这些文件。

## 部署 Worker

```bash
./scripts/deploy-workers.sh
```

该脚本会依次执行 Workers 类型检查、测试、Web Vault 静态资源构建和 `wrangler deploy`。它不会执行 D1 migration；数据库迁移需要单独显式运行。

部署前请确认：

- D1、R2、KV、Durable Object bindings 已在 Cloudflare 账号中创建并更新 `workers/wrangler.toml`。
- 生产环境修改 `JWT_SECRET`，并按需配置 `VAULT_BASE_URL`。
- Cloudflare Email Service 已启用：在 Dashboard 完成 `ifn.app` Email Sending domain onboarding，并确认发件地址 `no-reply@ifn.app` 可用。
- `workers/wrangler.toml` 默认使用 `EMAIL_MODE = "cloudflare"`、`EMAIL_FROM = "Bitwarden <no-reply@ifn.app>"` 和 `[[send_email]] name = "EMAIL"`。

Cloudflare Email Service 也可用 Wrangler 初始化发件域名：

```bash
cd workers
npx wrangler email sending enable ifn.app
npx wrangler email sending dns get ifn.app
```

如果需要本地调试邮件 token，可临时把 `EMAIL_MODE` 改为 `log` 并设置 `EMAIL_RETURN_TOKENS = "true"`；生产部署不要启用 token 回显。

## 路由行为

以下路径会先进入 Worker API：

- `/api/*`
- `/identity/*`
- `/icons/*`
- `/events/*`
- `/notifications/*`
- `/hub` 和 `/hub/*`
- `/attachments/*`
- `/organizations/*`
- `/alive`、`/now`、`/version`

其它静态文件和 Web Vault 前端路由由 Workers Static Assets 处理。

不要把 `assets.run_worker_first` 设置成 `true`，否则 Web Vault 的前端路由会被 Worker 的 JSON 404 截走。
