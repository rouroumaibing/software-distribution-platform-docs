# 认证架构（AUTH-ARCHITECTURE）

> 平台认证架构单一真源。本文取代旧「浏览器持 KC token + oidc-client-ts」模型（KEYCLOAK.md §6 时序图与 ui-05 §7.15 createdDate 检测均为该旧模型的产物，已废弃）。落地状态见 §10；决策记录见本文「变更历史」。

## 1. 两层模型

**身份存储层 —— 始终 Keycloak。** 用户、密码、requiredActions 共用 Keycloak 一份存储；hub 不落用户密码、不存在第二身份源。登录协议切换不迁移身份事实。

**协议层 —— 二选一，`login=default|keycloak` 互斥，默认 default。**

- `default`：password grant（BFF 自研登录页）。浏览器不跳 Keycloak，无 SSO。
- `keycloak`：OIDC code flow。浏览器跳 Keycloak 托管登录页，有 SSO；第三方 IDP 联邦挂在本模式（新 IDP 走同一 code flow 链路，非新链路）。

BFF（Backend-For-Frontend）不变：**hub 是会话权威，浏览器不持 Keycloak token**，登录链路取得的是 **hub session cookie**（httpOnly + AES-GCM 加密）。Keycloak token 仅在 hub 内部短暂持有（grant / code 交换 / 二次签发），存入 session 记录供 userinfo 刷新与 logout 传播，**永不下发浏览器**。hub 中间件加 session cookie 校验路径，与既有 KC JWT（服务间 / PAT）路径并存。

## 2. 协议层：登录模式互斥

| login 模式 | 协议 | 浏览器行为 | SSO |
|---|---|---|---|
| `default`（默认） | password grant | console 自研登录页 `/user/login`（`state.mode` 在 login / updatePassword 间切换，URL 不变） | 无 |
| `keycloak` | OIDC code + PKCE | 跳 Keycloak 托管登录页（required-action 含强制改密由 KC 在 authorization endpoint 阶段自处理） | 有 |

- **存储**：login 模式存 hub DB（`settings` 表，key `loginMode`），由 `SettingLoginMode` 服务承载（DB 持久化 + 内存缓存 + 启动 env 种子 `LOGIN_MODE`）；chart values 提供初值 `default`。重启从 DB 恢复，不依赖 KC 可达。
- **前端驱动**：`GET /api/v1/auth/config`（未鉴权）返回 `{login}`；登录页由 `configData.login` 决定渲染自研表单或跳 Keycloak。登录页是**单入口**，双登录按钮并存的形态不采用。
- **管理员切换**：console 以 Radio 单选切换（console 只展示，hub 唯一权限权威）；切换走 `PUT /api/v1/login` 写回 `settings` 表并更新 hub 内存缓存。
- **禁切回约束**：realm 存在**已启用**的 IDP 时禁切回 `default`——IDP 联邦登录仅存在于 keycloak 模式，切回会让 SSO 用户失联（D9）。

### Flow A —— default 模式（凭据面 / 强制改密可见性）

```
POST /api/v1/auth/login  {username, password}
  → hub 调 KC password grant（client_id=登录 client sdp-console）
  → 200 access_token  ⇒ LoginClientImpersonate 二次签发（§4）⇒ CreateSession(allowExist=false)（§4）⇒ 200 session cookie
  → 400 "Account is not fully set up"
       ⇒ hub 分类为 sentinel + GetUserByName 查 requiredActions
       ⇒ 返回 400 reason=UPDATE_PASSWORD（前端切 updatePassword 模式）
  → 401 invalid credentials ⇒ 返回 401
```

### Flow B —— keycloak 模式（会话面 / OIDC / SSO / IDP 联邦）

```
GET /api/v1/auth/login-url
  → hub 生成 KC auth URL（含 PKCE code_challenge）+ state=uuid
  → hub 持 code_verifier，state→verifier 映射存内存/TTL
浏览器跳 KC 托管登录页 → 登录成功 → 回调 redirect_uri?code&state
前端检测 oauth.code → POST /api/v1/auth/session/code {code, state}
  → hub 用 state 取 verifier → KC token 端点 grant_type=authorization_code
  → 200 ID/access_token ⇒ LoginClientImpersonate 二次签发（§4）⇒ CreateSession(allowExist=true)（§4）⇒ 200 session cookie
```

> required-action（含强制改密）由 Keycloak 在 **authorization endpoint 阶段**处理——KC 在发 code 之前先渲染 update-password 页。Flow B 的 code 交换对 required-action 完全无感，callback 不带任何改密信号。强制改密的结构化可见性（`reason=UPDATE_PASSWORD` → 自有改密 UX）只存在于 default 模式。

## 2.1 Flow A 端到端链路（default 模式 / 凭据面 / 第一次登录 / 强制改密）

**登录（正常路径）**
1. `LoginView.vue`（login 模式表单）`onLogin()` → `auth.login(username, password)`（store action）→ `authApi.login()` → `POST /api/v1/auth/login`（console `src/api/auth.ts`；axios `withCredentials:true` 见 `src/api/http.ts`）。
2. hub `handler.go` `Login()` → `kc.PasswordGrant(loginClientID, username, password)`（`internal/keycloak/login.go`）。
3. `PasswordGrant` → `doGrant` POST Keycloak token endpoint（`grant_type=password` + `scope=openid profile email`）。
4. 成功 → `LoginClientImpersonate` 二次签发（§4）→ `establishSession()`：`DecodeIDToken` 取 `sub`/`preferred_username`/`groups` → `sessions.Create`（`allowExist=false`）写一行 → `session.SetCookie`（httpOnly + AES-GCM + SameSite=Lax）。
5. hub 返回 200 + `Set-Cookie: sdp_sess=<encrypted>`；浏览器后续请求经 axios `withCredentials` 自动带 cookie。

**登录遇强制改密（bootstrap admin 首登 / 密码被重置）**
1-3 同正常路径，但 `doGrant` 返回 400 且 `error_description` 含 `Account is not fully set up`（坑2：凭证校验通过后才返回 = 旧密码正确）。`doGrant` 分类为 `ErrAccountNotFullySetUp`。
4. `Login()` 命中该 sentinel → `GetUserByNameExact` 读 `requiredActions[0]` → 400 `DomainErrorWithReasons(reason=UPDATE_PASSWORD)`。
5. 前端 catch `AuthError(reason=UPDATE_PASSWORD)` → `state.mode=updatePassword`，原密码从登录步骤自动带入（不渲染原密码输入框）。
6. 用户输入新密码（新密码 + 确认两框）→ `onChangePassword()` → `auth.changePassword(...)` → `authApi.password()` → `POST /api/v1/auth/password`。
7. hub `Password()`：
   - 校验新密码长度 ≥ 8 且 ≠ 旧密码；
   - 用旧密码 `PasswordGrant` 验证：`ErrAccountNotFullySetUp` = 旧密码正确放行，`ErrInvalidCredentials` = 401（坑2）；
   - `GetUserByNameExact` 取 user ID；
   - `ResetPassword(user.ID, newPassword, temporary=false)`（坑3）；
   - `ClearRequiredActions(user.ID)` 传 `[""]`（坑1）；
   - `LogoutAll(user.ID)` 清 KC 既有会话；
   - 返回 200 `{changed:true, subject}`——**不建会话**。
8. 前端切回 `state.mode=login`，用新密码走正常路径登录。

## 2.2 Flow B 端到端链路（keycloak 模式 / OIDC / SSO）

1. 前端从 `GET /api/v1/auth/config` 读到 `login==="keycloak"` → 触发 `auth.getLoginUrl()` → `GET /api/v1/auth/login-url`。
2. hub `LoginURL()`：`randomHex(16)` 作 `state`、`generateCodeVerifier()` + `s256Challenge()` 算 `challenge`；`verifiers.set(state, verifier)` 存内存（TTL 10min、一次性消费）；构造 KC auth URL（`client_id=loginClientID`、`response_type=code`、`scope=openid profile email`、`redirect_uri`、`state`、`code_challenge`+`S256`）；返回 `{loginUrl, state}`。
3. 前端 `window.location.assign(loginUrl)` → 浏览器跳 Keycloak 托管登录页（IDP 联邦在此页露出）。
4. 用户在 KC 登录成功（required-action 在 authorization endpoint 阶段已处理）→ KC 回调 `redirect_uri?code&state`。
5. `AuthCallback.vue` 取 `route.query.code/state` → `auth.handleOAuthCallback(code, state)` → `authApi.sessionCode(code, state)` → `POST /api/v1/auth/session/code`。
6. hub `SessionCode()`：`verifiers.take(state)` 取 verifier（一次性、过期即失效）→ `kc.ExchangeCode(loginClientID, code, redirectURI, verifier)`（`grant_type=authorization_code` + `code_verifier`）。
7. 成功 → `LoginClientImpersonate` 二次签发（§4）→ `establishSession()`（`allowExist=true`）→ `Set-Cookie: sdp_sess`。
8. hub 200 `{authenticated:true}`；前端 `router.replace('/')` + `loadUserinfo()` 拉权限镜像。

**闭环（两条 Flow 共用）**：cookie 落地后，浏览器每次请求经 axios `withCredentials` 带 `sdp_sess`；hub `middleware.Authenticator` 的 `sessionVerifier` `ReadCookie` → 解密 → `sessionRepo.Get` → 写入请求上下文（Subject/Username/Groups）。三条鉴权路径优先级：session cookie > PAT > KC JWT（§8）。

## 3. 强制改密闭环（bootstrap admin 首登）

承接 §7.14 M1 与 realm 种子引导的 bootstrap admin。**全环境统一**（本地 kind dev / 云上验收 / 生产），无「跳过改密直接使用」路径。

```
登录页（admin + 初始口令，default 模式）
  → POST /api/v1/auth/login  ⇒ 400 reason=UPDATE_PASSWORD
  → 前端 state.mode=updatePassword（新密码 + 确认，URL 不变）
  → POST /api/v1/auth/password {oldPassword, newPassword}
       ⇒ hub 用 oldPassword 做 password grant 验证
            （收到 "Account is not fully set up" = 旧密码正确，放行；见坑 2）
       ⇒ ResetPassword temporary=false（见坑 3）
       ⇒ 清 requiredActions（见坑 1）
       ⇒ 清 KC sessions（POST /users/:id/logout，logout-all）
       ⇒ 200 {changed: true}（不建会话）
  → 前端 state.mode=login，用新密码走 Flow A 登录 ⇒ 200 session ⇒ 入系统
```

**触发机制**：Keycloak `requiredActions=[UPDATE_PASSWORD]`——realm JSON import 确定生效；credential 的 `temporary` 字段在 import 中不可靠（实测），不作依赖。realm 种子落 hub chart `keycloak-realm-configmap.yaml`；存量环境经 KC Admin API 补授。

**适用范围**：仅 bootstrap admin（realm seed 挂 UPDATE_PASSWORD）与显式 reset-password 语义触发首登改密。**管理员建新用户不触发**——`CreateUser` 固定 `temporary=false` 且不写 requiredActions，建号即设固定密码、直接可登录（D10）。

**密码语义**：密码只存 Keycloak，hub 不落用户表、不回显。bootstrap admin 完成改密后，仓库内初始口令对该环境即失效；口令遗失经 master admin 重置。

## 4. 会话建立（公共尾）

```
hub 拿到 KC 登录 client token（Flow A password grant / Flow B code 交换）
  → LoginClientImpersonate 二次签发：
       hub 以资源 client（sdp-backend，confidential，持 secret）调 KC token endpoint
       grant_type=urn:ietf:params:oauth:grant-type:token-exchange
       subject_token=登录 token，audience=资源 client
       ⇒ 资源 token（azp/aud=资源 client，仍绑定用户身份）——hub 内部持有，不下发浏览器
  → 解析 ID token 取 username / sub / groups
  → CreateSession：
       • Flow A：allowExist=false（凭据登录即代表一次新会话意图）
       • Flow B：allowExist=true（SSO 场景同用户多端会话并存）
       • sessions 表写一行（id=uuid, subject=sub, kc_token=资源 token 加密存, expires_at, ...）
       • Set-Cookie: sdp_sess=<encrypted> ; HttpOnly ; SameSite=Lax ; Secure(生产)
  → 返回 200
前端 setUser → GET /api/v1/userinfo（hub 权限镜像，现有端点保留）→ 入系统
```

**域名匹配**：资源 client 的 token 是 hub API 面的访问凭据（azp/audience 与资源 API 面一致才放行）；登录 client（public，绑 console 回调域）的 token 只用于登录流程本身，不作为资源凭据。

## 5. 关键决策

| # | 决策 | 理由 |
|---|---|---|
| D1 | **session 存 DB（GORM `sessions` 表）非 K8s Session CR** | hub 是 Go+Gin+GORM+PG 栈；K8s Session CR 对 hub 栈不贴合。hub 已有 PG + GORM AutoMigrate（schema SSOT，只加不删）。session 表生命周期短、按 expires_at 清理。 |
| D2 | **双 client：登录 client（sdp-console，public+PKCE）≠ 资源 client（sdp-backend，confidential）** | grant / code 交换后 hub 必做 LoginClientImpersonate 二次签发（token exchange，RFC 8693）——登录 client token 只证明"登录成功"，资源 API 面凭据必须 azp/aud 匹配资源 client。资源 token 由 hub 内部持有（D5 不变），浏览器仍只见 hub session cookie。 |
| D3 | **`directAccessGrantsEnabled` 保 `true`** | default 模式（password grant）需要；keycloak 模式「必须 false」是纯 code 流平台的约束，互斥共存下不适用。e2e 冒烟脚本也依赖 password grant。 |
| D4 | **PKCE，后端持 `code_verifier`** | Flow B 的 `getLoginUrl` 由后端生成 auth URL 并持 verifier，state=uuid 映射 verifier（标准 BFF）。public client 无 PKCE 有 code 拦截风险。 |
| D5 | **KC token 不出后端** | grant / code 交换 / 二次签发拿到的 KC token 存 session 记录（供 userinfo 刷新 / logout 传播），浏览器只用 hub session cookie。XSS 无法窃取 KC token。 |
| D6 | **session cookie = AES-GCM 加密 + httpOnly + SameSite=Lax** | 复用凭据加密同款 envelope（`10_credentials.sql` 模式，master key 走 env/secret）。httpOnly 防 JS 读；SameSite=Lax 防 CSRF（POST 跨站不带 cookie）。 |
| D7 | **login 模式存 hub DB（`settings` 表）+ env 种子 `LOGIN_MODE`** | 运行时可切换（管理员 Radio），hub 公开端点 `/api/v1/auth/config` 未鉴权可读驱动登录页渲染；`SettingLoginMode` 服务做 DB 持久化 + 内存缓存，重启从 DB 恢复，不依赖 KC 可达；选型理由：需单测、免 kube client、避免第二真源。 |
| D8 | **IDP 配置落 Keycloak realm，hub 透传 CRUD** | `/api/v1/realmsettings/identityprovider` 透传 `IdentityProviderRepresentation`；`checkProviderID` 白名单预留（KC 原生支持 oidc/saml/cas 等）。新 IDP 走同一 Flow B code flow 链路，非新链路。 |
| D9 | **配已启用 IDP 禁切回 default** | IDP 联邦登录仅存在于 keycloak 模式；SSO 用户在 default 模式（password grant）无对应凭据，切回即失联。 |
| D10 | **CreateUser `temporary=false`、无 requiredActions** | 管理员建号即设固定密码、直接可登录不触发改密。首登强制改密仅保留给 bootstrap admin（realm seed UPDATE_PASSWORD）与显式 reset-password 语义。 |

## 6. 坑（落地约束）

**坑 1 —— 清 requiredActions 必须传 `[""]` 非 `[]`（Go 序列化侧）**
- Go 的 `json:"requiredActions,omitempty"` 会把空切片**整个丢掉** → PUT 时字段省略 → KC merge 保留旧值，永远清不掉。`[""]` 因非空会被序列化而生效。
- raw REST `{"requiredActions":[]}` 在 KC 26.7.4 实测能清（curl 原始 JSON 不经 omitempty），但 Go 客户端要走 `[""]` 或把字段改成可空（`*[]string` / 去掉 omitempty）。
- 落地：`internal/keycloak/directory.go` 的 `kcUserRep.RequiredActions` 可空化，或 `UserPatch` 加显式 `RequiredActions *[]string`。

**坑 2 —— 旧密码验证放行 "not fully set up"**
- password grant 的 `Account is not fully set up` 是在**凭证校验通过之后**才返回（实测：错密码 → `Invalid user credentials`；对密码 + 挂 RA → `Account is not fully set up`）。收到它 = 旧密码正确的证明。
- 该字符串是 KC 400 响应体内容；后端透传时 reason 字段含 `UPDATE_PASSWORD` 供前端匹配（不匹配字符串本身，匹配分类后的 sentinel/reason）。
- 改密 API 据此放行：用 oldPassword 做 password grant，收到 not-fully-set-up 即视为旧密码正确，继续 ResetPassword。
- 附带：改密会使既有 KC token 全部失效（notBefore 回拨），故「清 KC sessions」是双保险。

**坑 3 —— `temporary` 语义分路径**
- realm **import JSON** 里 `temporary:true` 不可靠（实测 import 后 `temporary:None`、`requiredActions:[]`）——bootstrap admin seed 改用显式 `requiredActions:[UPDATE_PASSWORD]`。
- Admin **REST** reset-password/credentials `temporary:true` 有效：显式 reset-password 场景（要求下次登录改密）继续用它。
- Flow A 自助改密与 CreateUser 固定 `temporary=false`（避免改完/建号后又挂 RA）。

**坑 4 —— login 互斥，单入口**
- `default`/`keycloak` 二选一（默认 default）；前端由 `configData.login` 单入口驱动，双登录按钮并存形态不采用。切互斥配置是管理员 Radio 单选，非运行时探测。

**坑 5 —— LoginClientImpersonate 必做**
- grant / code 交换拿到的登录 client token 不直接作为资源凭据；须经 token exchange 二次签发资源 client token（azp/aud 匹配资源 API 面）后才写入 session。跳过此步=登录 token 直穿资源面，azp 校验即失守。

**坑 6 —— IDP 挂 keycloak 模式，配后禁切回**
- IDP 联邦只在 keycloak 模式生效；realm 存在已启用 IDP 时切换端点拒绝回 default（防 SSO 用户失联）。

## 7. hub 端点清单

| 方法 | 路径 | 入参 | 出参 | 说明 |
|---|---|---|---|---|
| GET | `/api/v1/auth/config` | — | `{login: "default"\|"keycloak"}` | 未鉴权；登录页渲染驱动（configData.login） |
| GET | `/api/v1/auth/login-url` | — | `{loginUrl, state}` | keycloak 模式入口；后端生成 KC auth URL + 持 PKCE verifier |
| POST | `/api/v1/auth/login` | `{username, password}` | 200 session cookie / 400 `reason=UPDATE_PASSWORD` / 401 | default 模式入口；password grant + 二次签发 |
| POST | `/api/v1/auth/session/code` | `{code, state}` | 200 session cookie / 400 | keycloak 模式回调；code 交换 + 二次签发 |
| POST | `/api/v1/auth/password` | `{username, oldPassword, newPassword}` | 200 / 400 / 401 | 强制改密；旧密码验证放行 not-fully-set-up |
| POST | `/api/v1/auth/logout` | — | 204 | 清 session + cookie |
| GET | `/api/v1/userinfo` | — | `{subject, roles, orgs, ...}` | 权限镜像（session 校验） |
| PUT | `/api/v1/login` | `{login}` | 200 / 409 | 管理员切换登录模式；已启用 IDP 时禁切 default（D9） |
| GET | `/api/v1/identityprovider` | — | `{identityProviders:[IdentityProvider]}` | IDP 列表（platform 权限组，user:manage） |
| GET | `/api/v1/identityprovider/types` | — | `{types:[string]}` | KC 支持的 provider 工厂 id 白名单（oidc/saml/cas/...），前端下拉用（D8） |
| POST | `/api/v1/identityprovider` | IdentityProvider | 200 `{alias}` / 409 | 创建 IDP；providerId 取白名单 |
| PUT | `/api/v1/identityprovider/:alias` | IdentityProvider | 200 `{alias}` / 404 | 更新 IDP |
| DELETE | `/api/v1/identityprovider/:alias` | — | 204 / 404 | 删除 IDP |

所有 `/api/auth/*` 与 `/api/v1/auth/config` 端点**不挂**鉴权中间件（登录前调用）；`/api/userinfo` 挂 session 校验；`/identityprovider*` 与 `/login` 挂 platform 权限组（user:manage）。

## 8. 中间件：session cookie 校验路径

`middleware/auth.go` 的 `Authenticator` 现校验 KC JWT（azp）+ PAT（`sdp_pat_*`）。session cookie 路径：

```
请求带 Cookie: sdp_sess=<encrypted>
  → AES-GCM 解密 → session id
  → 查 sessions 表（未过期）
  → UserContext: subject = session.subject, groups = session.groups
  → 写入请求上下文（与 JWT 路径同一 contextKey）
```

三条路径优先级：session cookie > PAT > KC JWT。session 路径命中即短路；PAT/JWT 保留给 API token / 服务间调用。KC JWT 路径的 azp 校验目标为**资源 client**（sdp-backend）。

## 9. console 改造

- 登录页**单入口**：`LoginView` onMounted 拉 `GET /api/v1/auth/config`（configData）；`login==="keycloak"` → 触发 `getLoginUrl` 跳 KC；否则自研表单（`state.mode: login | updatePassword`，URL 不变；改密表单 = 新密码 + 确认两框，原密码从登录步骤自动带入）
- 管理员设置页（平台管理 · 认证设置）：登录模式 Radio 单选（default | keycloak）调 `PUT /api/v1/login`；realm 存在已启用 IDP 时切回 default 被 hub 拒绝（409），前端提示
- IDP 管理页（同认证设置页）：CRUD（透传 `IdentityProvider` 关键字段 alias/displayName/providerId/enabled/trustEmail/config），走 `/api/v1/identityprovider`
- `oauth.code` 检测（keycloak 模式回调）→ `POST /api/v1/auth/session/code`
- http 客户端 `withCredentials: true`（带 session cookie）

## 10. 落地状态

- **已落地**：Flow A 全链路（login / 强制改密 / 坑1-3）、Flow B code 交换 + PKCE、session cookie + AES-GCM、middleware session 路径、`/api/v1/auth/*` 五端点；`/api/v1/auth/config` + DB 持久化 login 模式（`settings` 表 + `LOGIN_MODE` 种子）、`PUT /api/v1/login` + 禁切回校验、IDP CRUD 透传（`/api/v1/identityprovider*` + `/types`）、LoginClientImpersonate 二次签发（token exchange）、CreateUser `temporary=false`、console 登录页单入口 + 管理员 Radio + IDP 管理页、middleware azp 目标迁移资源 client（sdp-backend）。
- 状态以 [STATUS.md](../plans/STATUS.md) 为准。

## 11. 相关文档

- [KEYCLOAK.md](KEYCLOAK.md) —— Keycloak 部署 / realm 种子 / client 配置事实（§6 交互时序图已由本文取代）
- [ui-05-page-layouts.md §7.15](../console/features/ui-05-page-layouts.md) —— bootstrap admin 首登强制改密闭环（console 侧 UX，机制指向本文）
- [ACCOUNT-PERMISSION-MODEL.md](ACCOUNT-PERMISSION-MODEL.md) §2 —— hub 令牌校验 / UserContext（session 路径新增其上）

## 12. 变更历史

| 日期 | 决策 |
|---|---|
| 2026-11-04 | 两层设计定版：身份存储层恒为 Keycloak；协议层 `login=default\|keycloak` 互斥、默认 default，login 模式存 ConfigMap（`sdp-login-config`），未鉴权公开端点 `/api/v1/auth/config` 驱动登录页单入口，管理员 Radio 单选切换。推翻 D2「单 client 无 LoginClientImpersonate」拍板，改为双 client（登录 sdp-console / 资源 sdp-backend）+ LoginClientImpersonate 二次签发（token exchange，必做）。CreateUser 语义变更：`temporary=false` 无 requiredActions，建号直接可登录不触发改密（首登强制改密仅保留 bootstrap admin）。新增 IDP 扩展：`/realmsettings/identityprovider` 透传 KC `IdentityProviderRepresentation`，checkProviderID 白名单预留，新 IDP 走同一 code flow 链路；配已启用 IDP 禁切回 default（防 SSO 用户失联）。端点沿用 `/api/auth/*` 现有命名，不按参考项目命名（/users/login 等）重构。 |
| 2026-11-04 | login 模式存储由 ConfigMap（sdp-login-config）改为 **hub DB（`settings` 表）+ env 种子 `LOGIN_MODE`**（`SettingLoginMode`：DB 持久化 + 内存缓存），免 kube client、可单测、避免第二真源。文档校正：realmsettings 端点实际挂在 `/api/v1`（platformGroup，user:manage 守卫），路径不含 `/realmsettings/` 前缀——`identityprovider*` 与 `login` 均为 `/api/v1` 下直连；补充 `GET /api/v1/identityprovider/types`。上述代码已全部落地（hub + console 双端 gate 通过）。 |
