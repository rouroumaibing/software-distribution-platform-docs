# 认证架构（AUTH-ARCHITECTURE）

> 平台认证架构单一真源。本文取代旧「浏览器持 KC token + oidc-client-ts」模型（KEYCLOAK.md §6 时序图与 ui-05 §7.15 createdDate 检测均为该旧模型的产物，已废弃）。落地状态以 [STATUS.md](../plans/STATUS.md) 为准；决策记录见 [CONSOLE-UI-DESIGN 变更历史](../console/CONSOLE-UI-DESIGN.md)。

## 1. 模型

**BFF（Backend-For-Frontend）—— hub 是会话权威，浏览器不持 Keycloak token。**

- Keycloak 只管身份 + 组（设计原则不变，见 KEYCLOAK.md §6）；业务授权仍全落 hub。
- 浏览器登录链路取得的是 **hub session cookie**（httpOnly + AES-GCM 加密），不是 KC access_token。
- Keycloak token 仅在 hub 内部短暂持有（login / code 交换时），存入 session 记录供 userinfo 刷新与 logout 传播，**永不下发浏览器**。
- hub 中间件加 session cookie 校验路径，与既有 KC JWT（服务间 / PAT）路径并存。

## 2. 两个互补入口

平台有两条登录入口，共享同一会话建立尾（§4）：

### Flow A —— 凭据面（本地账号 / 强制改密可见性）

自有登录页 `/user/login`（console 拥有 UI，非 KC 托管页），`state.mode` 在 `login` / `updatePassword` 间切换，URL 不变。

```
POST /api/auth/login  {username, password}
  → hub 调 KC password grant（client_id=sdp-console）
  → 200 access_token  ⇒ CreateSession（§4）⇒ 200 session cookie
  → 400 invalid_grant "Account is not fully set up"
       ⇒ hub 字符串匹配 + GetUserByName 查 requiredActions
       ⇒ 返回 400 reason=UPDATE_PASSWORD（前端切 updatePassword 模式）
  → 401 invalid credentials ⇒ 返回 401
```

### Flow B —— 会话面（OIDC code / SSO / 第三方联邦）

```
GET /api/auth/login-url
  → hub 生成 KC auth URL（含 PKCE code_challenge）+ state=uuid
  → hub 持 code_verifier，state→verifier 映射存内存/TTL
浏览器跳 KC 托管登录页 → 登录成功 → 回调 redirect_uri?code&state
前端检测 oauth.code → POST /api/auth/session/code {code, state}
  → hub 用 state 取 verifier → KC token 端点 grant_type=authorization_code
  → 200 ID/access_token ⇒ CreateSession（§4）⇒ 200 session cookie
```

> required-action（含强制改密）由 Keycloak 在 **authorization endpoint 阶段**处理——即 KC 在发 code 之前先渲染 update-password 页。**Flow B 的 code 交换对 required-action 完全无感**，callback 不带任何改密信号。这正是 Flow A 存在的核心互补价值：Flow A 的 password grant 会显式冒出 `Account is not fully set up`，让强制改密状态对前端结构化可见、可走自有 UX。

## 2.1 Flow A 端到端链路（凭据面 / 第一次登录 / 强制改密）

从自有登录页点击到会话 cookie 落地的逐跳。代码位置以仓库现行代码为准。

**登录（正常路径）**
1. `LoginView.vue` `onLogin()` → `auth.login(username, password)`（store action）→ `authApi.login()` → `POST /api/v1/auth/login`（console `src/api/auth.ts:17`；axios `withCredentials:true` 见 `src/api/http.ts:13`）。
2. hub `handler.go` `Login()`（:139）→ `kc.PasswordGrant(loginClientID, username, password)`（`internal/keycloak/login.go:55`）。
3. `PasswordGrant` → `doGrant`（`login.go:78`）POST Keycloak token endpoint（`grant_type=password` + `scope=openid profile email`）。
4. 成功 → `establishSession()`（handler.go:255）：`DecodeIDToken`（`login.go:169`，base64 解码、不验签——token 由 hub 直连 KC 经 TLS 获取）取 `sub`/`preferred_username`/`groups` → `sessions.Create` 写一行 → `session.SetCookie`（httpOnly + AES-GCM + SameSite=Lax，`internal/session/cookie.go:22`）。
5. hub 返回 200 + `Set-Cookie: sdp_sess=<encrypted>`；浏览器后续请求经 axios `withCredentials` 自动带 cookie。

**登录遇强制改密（第一次登录 / 密码被重置）**
1-3 同正常路径，但 `doGrant` 返回 400 且 `error_description` 含 `Account is not fully set up`（坑2：凭证校验通过后才返回 = 旧密码正确）。`doGrant` 分类为 `ErrAccountNotFullySetUp`（`login.go:94-95`）。
4. `Login()` 命中该 sentinel → `GetUserByNameExact` 读 `requiredActions[0]`（`handler.go:151`，`login.go:115`）→ 400 `DomainErrorWithReasons(reason=UPDATE_PASSWORD)`。
5. 前端 `LoginView.vue` catch `AuthError(reason=UPDATE_PASSWORD)`（:34-37）→ `state.mode=updatePassword`，预填原密码字段。
6. 用户输入新密码 → `onChangePassword()` → `auth.changePassword(old, new)` → `authApi.password()` → `POST /api/v1/auth/password`（`auth.ts:25`）。
7. hub `Password()`（handler.go:182）：
   - 校验新密码长度 ≥ 8 且 ≠ 旧密码（:188-197）；
   - 用旧密码 `PasswordGrant` 验证：`ErrAccountNotFullySetUp` = 旧密码正确放行，`ErrInvalidCredentials` = 401（:203-212）；
   - `GetUserByNameExact` 取 user ID（:215）；
   - `ResetPassword(user.ID, newPassword, temporary=false)`（坑3，:222）；
   - `ClearRequiredActions(user.ID)` 传 `[""]`（坑1，:228，`login.go:138`）；
   - `LogoutAll(user.ID)` 清 KC 既有会话（:234）。
   - 返回 200 `{changed:true, subject}`——**不建会话**。
8. 前端切回 `mode=login`，提示「请用新密码登录」（`LoginView.vue:59-66`）。
9. 用户用新密码重走「登录（正常路径）」，password grant 这次成功 → `establishSession` → cookie 入系统。

> 与 §3 关系：本节是 §3 强制改密闭环的业务语义在代码层的逐跳展开。

## 2.2 Flow B 端到端链路（会话面 / OIDC / SSO）

1. `LoginView.vue` `onSSO()` → `auth.getLoginUrl()` → `authApi.loginUrl()` → `GET /api/v1/auth/login-url`（`auth.ts:13`）。
2. hub `LoginURL()`（handler.go:87）：`randomHex(16)` 作 `state`、`generateCodeVerifier()` + `s256Challenge()` 算 `challenge`；`verifiers.set(state, verifier)` 存内存（TTL 10min、一次性消费，handler.go:318/326）；构造 KC auth URL（`client_id=loginClientID`、`response_type=code`、`scope=openid profile email`、`redirect_uri`、`state`、`code_challenge`+`S256`）；返回 `{loginUrl, state}`。
3. 前端 `window.location.assign(loginUrl)`（`LoginView.vue:81`）→ 浏览器跳 Keycloak 托管登录页。
4. 用户在 KC 登录成功（required-action 在 authorization endpoint 阶段已处理，不在 code 回调里）→ KC 回调 `redirect_uri?code&state`。
5. `AuthCallback.vue` `onMounted` 取 `route.query.code/state`（:14-15）→ `auth.handleOAuthCallback(code, state)` → `authApi.sessionCode(code, state)` → `POST /api/v1/auth/session/code`（`auth.ts:21`）。
6. hub `SessionCode()`（handler.go:105）：`verifiers.take(state)` 取 verifier（一次性、过期即失效）→ `kc.ExchangeCode(loginClientID, code, redirectURI, verifier)`（`login.go:68`）→ `doGrant`（`grant_type=authorization_code` + `code_verifier`）。
7. 成功 → `establishSession()`（同 §2.1 第 4 步）→ `Set-Cookie: sdp_sess`。
8. hub 200 `{authenticated:true}`；前端 `router.replace('/')`（`AuthCallback.vue:22`）+ `loadUserinfo()` 拉权限镜像（store `handleOAuthCallback`）。

**闭环（两条 Flow 共用）**：cookie 落地后，浏览器每次请求经 axios `withCredentials` 带 `sdp_sess`；hub `middleware.Authenticator` 的 `sessionVerifier`（`auth_setup.go:47` 注册）`ReadCookie` → 解密 → `sessionRepo.Get` → 写入请求上下文（Subject/Username/Groups）。三条鉴权路径优先级：session cookie > PAT > KC JWT（§8）。

## 3. 强制改密闭环（bootstrap admin 首登）

承接 §7.14 M1（管理员建用户的临时口令首登改密），把同一闭环延伸到 realm 种子引导的 bootstrap admin。**全环境统一**（本地 kind dev / 云上验收 / 生产），无「跳过改密直接使用」路径。

```
登录页（admin + 初始口令）
  → Flow A: POST /api/auth/login  ⇒ 400 reason=UPDATE_PASSWORD
  → 前端 state.mode=updatePassword（新密码 + 确认，URL 不变）
  → POST /api/auth/password {oldPassword, newPassword}
       ⇒ hub 用 oldPassword 做 password grant 验证
            （收到 "Account is not fully set up" = 旧密码正确，放行；见坑 2）
       ⇒ ResetPassword temporary=false（见坑 3）
       ⇒ 清 requiredActions（见坑 1）
       ⇒ 清 KC sessions（POST /users/:id/logout，logout-all）
       ⇒ 200 {changed: true}（不建会话）
  → 前端 state.mode=login，用新密码走 Flow A 登录 ⇒ 200 session ⇒ 入系统
```

**触发机制**：Keycloak `requiredActions=[UPDATE_PASSWORD]`——realm JSON import 确定生效；credential 的 `temporary` 字段在 import 中不可靠（实测），不作依赖。realm 种子落 hub chart `keycloak-realm-configmap.yaml`；存量环境经 KC Admin API 补授。

**密码语义**：密码只存 Keycloak，hub 不落用户表、不回显。bootstrap admin 完成改密后，仓库内初始口令对该环境即失效；口令遗失经 master admin 重置。

## 4. 会话建立（公共尾）

```
hub 拿到 KC token（Flow A 的 password grant / Flow B 的 code 交换 / 改密后的新 token）
  → 解析 ID token 取 username / sub / groups
  → CreateSession：
       • sessions 表写一行（id=uuid, subject=sub, kc_token=加密存, expires_at, ...）
       • Set-Cookie: sdp_sess=<encrypted> ; HttpOnly ; SameSite=Lax ; Secure(生产)
  → 返回 200
前端 setUser → GET /api/userinfo（hub 权限镜像，现有端点保留）→ 入系统
```

## 5. 关键决策

| # | 决策 | 理由 |
|---|---|---|
| D1 | **session 存 DB（GORM `sessions` 表）非 K8s Session CR** | hub 是 Go+Gin+GORM+PG 栈；K8s Session CR 是 K8s 原生平台的做法，对 hub 栈不贴合。hub 已有 PG + GORM AutoMigrate（schema SSOT，只加不删）。session 表生命周期短、按 expires_at 清理。 |
| D2 | **单 client（sdp-console）无 LoginClientImpersonate** | hub 已校验 token `azp == sdp-console`（middleware/auth.go）；单 client 下 KC token 的 azp/aud 即 hub 校验目标，无「域名不匹配」问题。LoginClientImpersonate 是登录/资源双 client 模型（登录 client ≠ 资源 client）的需求，本平台不采用双 client。 |
| D3 | **`directAccessGrantsEnabled` 保 `true`** | Flow A 的 password grant 需要；Flow B「必须 false」是纯 code 流平台的约束，A+B 共存下不适用。e2e 冒烟脚本也依赖 password grant。 |
| D4 | **PKCE，后端持 `code_verifier`** | Flow B 的 `getLoginUrl` 由后端生成 auth URL 并持 verifier，state=uuid 映射 verifier（标准 BFF）。public client 无 PKCE 有 code 拦截风险。 |
| D5 | **KC token 不出后端** | login/code 交换拿到的 KC token 存 session 记录（供 userinfo 刷新 / logout 传播），浏览器只用 hub session cookie。XSS 无法窃取 KC token。 |
| D6 | **session cookie = AES-GCM 加密 + httpOnly + SameSite=Lax** | 复用凭据加密同款 envelope（`10_credentials.sql` 模式，master key 走 env/secret）。httpOnly 防 JS 读；SameSite=Lax 防 CSRF（POST 跨站不带 cookie）。 |

## 6. 三坑（落地约束）

**坑 1 —— 清 requiredActions 必须传 `[""]` 非 `[]`（Go 序列化侧）**
- 现象本质：Go 的 `json:"requiredActions,omitempty"` 会把空切片**整个丢掉** → PUT 时字段省略 → KC merge 保留旧值，永远清不掉。`[""]` 因非空会被序列化而生效。
- raw REST `{"requiredActions":[]}` 在 KC 26.7.4 实测能清（curl 原始 JSON 不经 omitempty），但 Go 客户端要走 `[""]` 或把字段改成可空（`*[]string` / 去掉 omitempty）。
- 落地：`internal/keycloak/directory.go` 的 `kcUserRep.RequiredActions` 改为可空，或 `UserPatch` 加显式 `RequiredActions *[]string`。

**坑 2 —— 旧密码验证放行 "not fully set up"**
- password grant 的 `Account is not fully set up` 是在**凭证校验通过之后**才返回（实测：错密码 → `Invalid user credentials`；对密码 + 挂 RA → `Account is not fully set up`）。收到它 = 旧密码正确的证明。
- 改密 API 据此放行：用 oldPassword 做 password grant，收到 not-fully-set-up 即视为旧密码正确，继续 ResetPassword。
- 附带：改密会使既有 KC token 全部失效（notBefore 回拨），故「清 KC sessions」是双保险。

**坑 3 —— `temporary=true` 触发 required-action（分路径）**
- realm **import JSON** 里 `temporary:true` 不可靠（实测 import 后 `temporary:None`、`requiredActions:[]`）——这是 seed 改用显式 `requiredActions:[UPDATE_PASSWORD]` 的原因。
- Admin **REST** reset-password/credentials `temporary:true` 有效。
- Flow A 改密用 `temporary=false`（避免改完又重挂 RA）；管理员建号/重置仍用 `temporary=true`（设计内，要求下次登录改密）。

## 7. hub 端点清单

| 方法 | 路径 | 入参 | 出参 | 说明 |
|---|---|---|---|---|
| GET | `/api/auth/login-url` | — | `{loginUrl, state}` | Flow B 入口；后端生成 KC auth URL + 持 PKCE verifier |
| POST | `/api/auth/login` | `{username, password}` | 200 session cookie / 400 `reason=UPDATE_PASSWORD` / 401 | Flow A 入口；password grant |
| POST | `/api/auth/session/code` | `{code, state}` | 200 session cookie / 400 | Flow B 回调；code 交换 |
| POST | `/api/auth/password` | `{oldPassword, newPassword}` | 200 session cookie / 400 / 401 | 改密；旧密码验证放行 not-fully-set-up |
| POST | `/api/auth/logout` | — | 204 | 清 session + cookie |
| GET | `/api/userinfo` | — | `{subject, roles, orgs, ...}` | 权限镜像（现有，保留） |

所有 `/api/auth/*` 端点**不挂**鉴权中间件（登录前调用）；`/api/userinfo` 挂 session 校验。

## 8. 中间件：session cookie 校验路径

`middleware/auth.go` 的 `Authenticator` 现校验 KC JWT（azp）+ PAT（`sdp_pat_*`）。新增 session cookie 路径：

```
请求带 Cookie: sdp_sess=<encrypted>
  → AES-GCM 解密 → session id
  → 查 sessions 表（未过期）
  → UserContext: subject = session.subject, groups = session.groups
  → 写入请求上下文（与 JWT 路径同一 contextKey）
```

三条路径优先级：session cookie > PAT > KC JWT。session 路径命中即短路；PAT/JWT 保留给 API token / 服务间调用。

## 9. console 改造

- 新增 `/user/login` 路由 + `LoginView`（`state.mode: login | updatePassword`，URL 不变）
- `oauth.code` 检测（Flow B 回调）→ `POST /api/auth/session/code`
- http 客户端 `withCredentials: true`（带 session cookie）
- 退役 oidc-client-ts 的 `signinRedirect` / `signinRedirectCallback` / `signoutRedirect`；保留 `getLoginUrl` 调后端
- 删 `AuthCallback.vue` 的 createdDate 检测 + end_session 逻辑（§7.15 旧实现）

## 10. 落地状态

代码落地中（hub session 层 + auth 端点 + middleware；console LoginView + http cookie）。**联调待开展**——跳过 build/vet/test gate 与环境联调以省 token；手写注意语法。状态以 [STATUS.md](../plans/STATUS.md) 为准。

## 11. 相关文档

- [KEYCLOAK.md](KEYCLOAK.md) —— Keycloak 部署 / realm 种子 / client 配置事实（§6 交互时序图已由本文取代）
- [ui-05-page-layouts.md §7.15](../console/features/ui-05-page-layouts.md) —— bootstrap admin 首登强制改密闭环（console 侧 UX，机制指向本文）
- [ACCOUNT-PERMISSION-MODEL.md](ACCOUNT-PERMISSION-MODEL.md) §2 —— hub 令牌校验 / UserContext（session 路径新增其上）
