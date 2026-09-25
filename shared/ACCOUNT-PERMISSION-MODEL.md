# 账号与权限模型（Account & Permission Model）

> **本文件的地位 = 规范（normative），不是现状快照。**
> 它写「应当是什么」，并在 §10 与代码 / realm 配置 / DB 种子做逐项对账；对账不通过即视为漂移。
>
> **范围**：登录账号（Keycloak 账户）+ 前端访问 + 后端鉴权。
> **不在范围**：TLS 证书、数据库口令、gateway token —— 其当前分布已判定正确，不纳入本轮。
>
> 数据模型的下位细节（DDL、字段级设计）见 [shared/DATA-MODEL.md §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md)；本文不复制 DDL，只做**权威边界与契约**的裁定。
> 认证子系统的部署与 realm 预置见 [shared/KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md)。

---

## 0. 三条不动式（先记住这三句话）

| # | 不动式 | 含义 |
| --- | --- | --- |
| ① | **Keycloak 只做身份** | 认证 + 签发 token（谁 / 角色 / 组织）。**不承担授权决策**。 |
| ② | **后端 hub 是唯一权限权威** | 每个请求做两件事：**认证**（校验 token）+ **鉴权**（token 上的身份/组织/角色 ↔ 资源归属）。密码由 Keycloak 保管，hub **不自管密码**。 |
| ③ | **前端只做展示** | 不认证、不解析 token、不鉴权。按钮/菜单的隐藏与置灰只是 UX；**隐藏不代表安全**。 |

三条推论（写死，避免反复讨论）：

- 任何「前端已隐藏，所以后端不必校验」的实现**无效**。
- 任何「Keycloak 里给了角色，所以权限就生效了」的假设**无效** —— token 里的角色对 hub 是**输入**，是否生效由 hub 的 RBAC 引擎裁定（§5）。
- 权限绑定**必须带有效期**（§7.4），不允许永久挂账。

---

## 1. 总览：一次请求经过什么

```
浏览器                  hub（唯一权限权威）                        Keycloak
  │                          │                                       │
  │  ① 登录跳转（不在前端做认证） │                                       │
  ├──────────────────────────┼──────────────────────────────────────►│
  │  ② 拿到 token 并保存       │                         ③ 签发 token（谁/角色/组织）
  │◄──────────────────────────┼──────────────────────────────────────┤
  │  ④ 业务请求 + Bearer token │                                       │
  ├─────────────────────────►│                                       │
  │                          │ ⑤ 认证：验签 + iss + exp + azp          │
  │                          │ ⑥ 鉴权（两段）：                         │
  │                          │   a. 资源归属：token.组织 vs 资源归属表    │
  │                          │   b. RBAC 决策：角色 ↔ 接口映射           │
  │                          │ ⑦ 审计：写操作统一上报                    │
  │  ⑧ 响应                   │                                       │
  │◄─────────────────────────┤                                       │
  │  ⑨ /api/userinfo → 隐藏/置灰（仅 UX，非安全边界）                    │
```

**前端全程不解析 token、不参与鉴权**；它只有一个额外调用：`/api/userinfo`。

---

## 2. 后端：对接 Keycloak

> 本节四小节：**§2.1** 从 token 读什么（契约）· **§2.2** 明确不做的事 · **§2.3** 组织与角色的载体 · **§2.4** 对接协议（OIDC 标准流程：怎么拿到并验掉那个 token）。

### 2.1 契约：hub 从 token 读什么

hub **只**从 token 取下列声明，其余一律不信（含请求体里自称的身份）：

| 声明 | 用途 | 备注 |
| --- | --- | --- |
| `sub` | **主体唯一标识**（绑定主体） | 稳定不可变；**不以 email 作键**（email 可变） |
| `preferred_username` | 展示名 / 审计留痕 | 非键 |
| `email` | 展示 / 通知 | 非键 |
| `azp` | 客户端校验（`azp == sdp-console`） | 防跨客户端重放 |
| `groups` | 组维度主体（§5.3） | 需 client 侧挂 groups mapper |
| **组织**（§2.3） | **资源归属判定的输入**（§3） | 默认走 `groups` 命名约定（§2.3 / §12 D1），carrier 可换 |
| **角色**（§2.3） | **对账 / 展示**（**已定**：不作判定输入；判定输入只来自 hub 绑定表，§5.1①） | 见 §12 D2（已闭） |

### 2.2 明确不做的事

- **不自管密码**：密码只在 Keycloak。
- **不存用户表**：hub 不维护「用户」实体，绑定主体直接用 token 的 `sub`。
  - ✅ **已合规（2026-09-23，D3）**：`users` 表已删，`UserContext` 不再逐请求开通用户，主体一律取 token `sub`（见 §10 #4 / §12 D3）。
- **不因 token 里有角色就放行**：token 里的角色是**输入**，不是结论 —— 判定输入只来自 hub 的绑定表（§5.1①、§5.2）。
  - ⚠ 本 realm 的角色**并不在 `realm_access`**，而在**顶层 `roles` claim**（`sdp-console` 上的 `oidc-usermodel-realm-role-mapper`，`claim.name: roles`）。按 `realm_access` 去 grep 会一无所获、进而误判为「角色根本没进 token」——**核对时请按 `roles`**。
  - 两段式分工（§4）一句话记住：**a 段吃 token（组织 → 资源归属）· b 段吃 hub 表（角色 → 接口）**。

### 2.3 组织与角色的载体（外部事实）

Keycloak ≥ 26 **原生支持 Organizations**，可作为「组织」维度的载体：

- 需在 realm 上**显式开启** Organizations（realm settings 开关）。⚠ Keycloak **不会自动改写既有 realm 的配置** —— 新增内置 client scope、改动浏览器登录流都须显式做；本仓 realm 由 `--import-realm` 导入，属「既有 realm」形态。
- `organization` 是**内置的可选 client scope**（其 mapper 即 Organization Membership）。**请求形态有三种、语义不同，必须显式选定**：

  | 请求形态 | 语义 | 后果 |
  | --- | --- | --- |
  | `organization` | ANY —— 用户**单一归属**时直接授予该组织 | 属于**多个**组织时**提示用户选择**（交互式）；非交互场景拿不到确定结果 |
  | `organization:<alias>` | SPECIFIC —— 指定某一个组织 | 别名不存在或用户非其成员 ⇒ 请求被拒 |
  | `organization:*` | ALL —— 用户**全部**归属 | 非交互、结果确定，但**语义是「全部组织」**，不是「有组织」 |

  ⚠ **`organization:*` 不是「唯一能拿到 claim 的形态」**：请求内置的 `organization` scope 本身即生效。两者的差别是**语义** —— ALL 会把用户的**全部**归属都放进 token。选哪种取决于 §3 的归属判定式要的是「当前组织上下文」还是「全部成员关系」（论证见 git 历史中的 plans/ACCOUNT-PERMISSION-DECISIONS.md（已删档，结论以本文件 §12 为准） §1）。
- **claim 形态有两种，Go 侧类型必须兼容**：纯别名时是字符串数组 `"organization": ["acme-corp"]`；**开启 `addOrganizationId` / `addOrganizationAttributes`，或使用 Organization Groups** 时变为富 JSON（`{"organization":{"acme-corp":{"id":"…","groups":["/Engineering/Backend"]}}}`）。
- 26.6+ 另有 **Organization Groups**（每个组织独立的组层级），组路径出现在 `organization` claim 内；**本环境 Keycloak 26.7.4 ⇒ 已具备**。
- **启用 Organizations 会把浏览器登录流改为 identity-first**（先识别用户、再要凭据）—— 这是**用户可见**的行为变化，会影响 console 登录路径与既有预置账号的登录体验。
- **组织集合能否随 realm JSON 一起导入，尚未证实**：`RealmRepresentation` 同时有 `organizationsEnabled`（Boolean）与 `organizations`（`List<OrganizationRepresentation>`）两个字段，但社区证据（26.3.1 时期）称 realm 导入**不带** organizations、官方推荐用 Admin REST API 在 realm 创建后再建组织。⇒ **落地时必须实测**（gate 见 §11 步骤 2）；在结论出来之前，**不要**把「组织集随 realm JSON 进 git」当既定事实。**（2026-09-24 澄清：D1 已裁定 = ② 组命名约定 `/org:<slug>`（§12），realm JSON 只导组、不开 Organizations ⇒ 本条实测**仅在翻盘切 ①（federation）时才触发**，当前主路径无此依赖——组预置走 provisioner REST，已在真集群 E2E 验证。）
- **落地硬约定（压降不可逆性）**：**不论选用哪个载体**，hub 侧持久化的**组织键一律取组织 alias 字符串**，且组织**不得**作为 RBAC 主体出现在 `subject_id` —— 于是换载体只改中间件解析、**不需要数据迁移**（论证见 git 历史中的 plans/ACCOUNT-PERMISSION-DECISIONS.md（已删档，结论以本文件 §12 为准） §1.5）。
- **Keycloak 的角色/组映射没有原生成效机制**（其生命周期概念是 token/session 的 lifespan，不是授权时效）⇒ **权限到期回收必须由 hub 实现**（§7.4）。

> **载体不阻塞任何落地项**：§2.1 / §3 的判定式、§12 的表结构，写的都是**组织 alias 字符串**（见下「落地硬约定」）⇒ 换载体只改中间件解析。**默认取「组命名约定」`/org:<slug>`**（复用**已就绪**的 `groups` 通路：`sdp-console` 已挂 groups mapper 且 `full.path=true`、`auth.go` 已读 `groups`；且**组是 realm JSON 的可靠组成部分** ⇒ 真正满足「配置即代码」，而这恰是 Organizations 的**未证实**项）。**Keycloak Organizations 降为条件触发位**：出现「多 IdP / 跨组织 SSO 联邦」需求时再切（因硬约定**无需数据迁移**）；① 的已知成本 = 需开 realm 开关 ⇒ **identity-first 登录流变化**。
>
> **保留命名空间（防语义串味）**：`/org:` 是**保留前缀** —— 该前缀的组**不得**作为 `subject_type=group` 的绑定主体（须在 `BindingService` 校验 + 单测），以守住「组织不作 RBAC 主体」的硬约定。论证见 git 历史中的 plans/ACCOUNT-PERMISSION-DECISIONS.md（已删档，结论以本文件 §12 为准） §1。

### 2.4 对接协议：OIDC 标准流程（hub = Resource Server）

**一句话**：hub 用 **OIDC 标准流程**对接 Keycloak —— 启动时经 **discovery** 取到 `jwks_uri`，之后每个请求拿 Keycloak 的**公钥离线验签**并校验收到的声明。**全程零外呼、不持密钥、不需要在 Keycloak 里建客户端。**

#### 2.4.1 hub 在 OIDC 里的角色是 Resource Server，不是 Client

OIDC 里有两个相关角色，本项目**分别落在两端**：

| 角色 | 干什么 | 本项目是谁 |
| --- | --- | --- |
| **OIDC Client**（Relying Party） | 发起登录跳转、用 code 换 token、刷新令牌、登出 | **console**（`sdp-console`：public + PKCE，**无 secret**） |
| **Resource Server** | **只校验**已签发的 access token，据此决定放不放行 | **hub**（本节） |

因此 hub **不参与**：登录跳转、`authorization_endpoint`、`token_endpoint`、code 交换、refresh、`end_session_endpoint`。它只需要 **issuer + JWKS**。

> **推论（写死）**：**hub 不需要在 Keycloak 里建 client**。`AuthConfig.ClientID` 填的是 **console 的 client ID（`sdp-console`）**，用途仅是校验 `azp` —— 即「这个 token 是不是签发给 console 的」（见 §2.4.3 第 5 步）。
> 服务间调用（client credentials，需 confidential client）是**另一条路径**，不在本节。

#### 2.4.2 标准流程三步

| 步 | 动作 | 端点 / 产物 | 时机 |
| --- | --- | --- | --- |
| ① | **Discovery** | `GET {issuer}/.well-known/openid-configuration` → 取 `jwks_uri`（标准文档里还有 `authorization_endpoint` / `token_endpoint` / `end_session_endpoint`，**hub 不用**，那三个是 console 的） | **启动一次** |
| ② | **取 JWKS** | `GET {jwks_uri}`（本项目即 `/keycloak/realms/sdp/protocol/openid-connect/certs`）→ 公钥集 | 首次验签；**遇未知 `kid` 自动重取** ⇒ Keycloak 轮换签名密钥时 hub **无需重启** |
| ③ | **验签 + 校验声明** | RS256 **非对称**验签（hub 只需公钥；**不接触私钥、不需要 client secret**） | **每个请求** |

`{issuer}` = `https://www.sdpworkflow.com/keycloak/realms/sdp` —— **含 `/keycloak` 相对路径**。issuer 与 chart 的 `http.relativePath` 不一致会让 discovery 直接 404（[shared/KEYCLOAK.md §3](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md)「坑 4」）。

#### 2.4.3 校验清单（顺序即失败顺序，任一不过 = `401`）

| # | 校验项 | 标准要求 | 本项目 |
| --- | --- | --- | --- |
| 1 | 头部 `alg` 必须是非对称算法（RS256） | OIDC 默认 RS256，禁 `none`／禁对称 | go-oidc 内建 |
| 2 | 用 `kid` 从 JWKS 选键**验签** | 必需 | go-oidc 内建 |
| 3 | `iss` **与配置 issuer 逐字相等** | 必需 | go-oidc 内建（故 issuer 必须写对外可达的完整地址，见 §2.4.2） |
| 4 | `exp` / `nbf` / `iat` 时间窗 | 必需 | go-oidc 内建（realm `accessTokenLifespan` = 300s） |
| 5 | **`azp` == `KEYCLOAK_CLIENT_ID`** | 可选（`azp` 非必校项），但**多客户端 realm 下必校** | **自实现**（`errWrongClient` → `401`），防跨客户端重放 |
| 6 | `aud` —— **刻意不校验** | 标准建议校验 | `SkipClientIDCheck: true`：Keycloak 默认 access token 的 `aud` 是 `"account"` 而非 client ID，要改得在 client scope 上加 audience mapper。故**改校 `azp`**，换「realm 零额外配置」 |
| 7 | 声明 → 请求主体 | — | `keycloakClaims`（§2.1 那张表）+ `UserContext` |

> 第 6 条是**刻意的标准偏离**，理由与代价一并记在这里：代价是**无法按 audience 区分多个资源服务器**。将来若出现「同一 realm 多个 API 需要不同 `aud`」，正确做法是加 audience mapper 并去掉 `SkipClientIDCheck`（登记为 §12 D6）。

#### 2.4.4 无状态优先：hub 不调用 Keycloak 的运行时 API

| 不调用 | 为什么 |
| --- | --- |
| `userinfo` | 身份信息**已全在 token 里**，再问一次只是多一次网络往返 |
| `introspection`（RFC 7662） | 那是 **opaque token** 的方案；本项目是 **JWT**，公钥验签即可自证，不必回头问授权服务器 |
| Admin API（**就业务请求而言**） | hub 无 Admin 客户端（连带影响 console「用户列表」来源，见 §12 D3） |

⇒ **每个业务请求对 Keycloak 零外呼**。副作用是好的：Keycloak 短时不可用**不影响**已签发 token 的校验（只有启动时的 discovery 与密钥轮换需要联通）。

> **适用范围（勿扩大解释）**：本节约束的是 **hub 的业务请求路径**（每个请求都要验签）。**管理面**（如 console「用户列表」这类一次性读）**不在**本禁令之内 —— 它属于 §12 D3 第 4 处的**来源决策**，两个选项的取舍与推荐见 git 历史中的 plans/ACCOUNT-PERMISSION-DECISIONS.md（已删档，结论以本文件 §12 为准） §3。

#### 2.4.5 启动即失败（fail-fast），不降级

`NewAuthenticator` 在启动时拉一次 discovery；取不到（Keycloak 未起 / realm 不存在 / issuer 写错）⇒ **进程直接启动失败**（`applog.Fatalf`），**不会**降级成「跳过校验」。

> 理由：**宁可不启动，也不接受无法验证的令牌。** 因此部署顺序上 **Keycloak 必须先 Ready**，hub 才起得来。

反过来，`KEYCLOAK_ISSUER` 为**空**是**显式**的关闭开关（`AuthDisabled()` → dev 模式）。两者语义不同、勿混：**空 = 有意关闭；写了却连不上 = 启动失败**。

#### 2.4.6 令牌生命周期各环节归谁

| 环节 | 归属 |
| --- | --- |
| 登录跳转 / code 换 token / 刷新 / 静默续期 / RP-initiated logout | **console**（oidc-client-ts，用 `authorization_endpoint` / `token_endpoint` / `end_session_endpoint`） |
| 校验 access token | **hub**（本节） |
| 签发 token / 轮换签名密钥 | **Keycloak**（hub 只读公钥，轮换对 hub 无感） |
| 登出后的会话清理 | **无** —— hub **无会话、无状态**，「登出」在 hub 侧不存在 |

---

## 3. 后端：资源归属（一张表）

hub 自己的 DB 只存一件事：**这个资源属于哪个组织 / 开放给谁**。

| 字段 | 说明 |
| --- | --- |
| `resource_id` | 资源主键（组件 / 流水线 / 制品 / …） |
| `resource_type` | 资源类型（【本文件补充】单表承载多资源类型所必需） |
| `owner_org` | 属主组织 |
| `allowed_orgs` | 允许访问的组织集合【本文件补充：单值 `owner_org` 无法表达「共享给兄弟组织」】 |

**鉴权判定式（粗判）**：`token.组织 ∈ {owner_org} ∪ allowed_orgs` → 否则 403。

### 3.1 与既有 org 冗余的关系（避免两个事实源）

现状是 `component → service → service_tree → org` 解析后**冗余**存到 `component_role_bindings.org_id`（见 DATA-MODEL §7）。规范裁定：

- **`resource_ownership` 是归属的权威源**；
- 既有的 `org_id` 冗余列降级为**派生缓存**（可重建、不可手改），重建脚本即对账依据。

---

## 4. 后端：每个请求做的两件事

中间件链顺序（固定，不因路由而异）：

| # | 阶段 | 做什么 | 失败 |
| --- | --- | --- | --- |
| 1 | **认证** `Authenticate` | 验签 + `iss` + `exp` + `azp` | `401` |
| 2 | **主体解析** | 从 claim 组装请求主体（`sub` + 角色 + 组织 + 组） | `401` |
| 3 | **鉴权 a：资源归属** | §3 判定式（粗判） | `403` |
| 4 | **鉴权 b：RBAC 决策** | §5（细判：角色 ↔ 接口） | `403` |
| 5 | **审计** | 仅写操作，§6 | 不影响主流程（失败降级为告警） |

**短路语义**：1→4 任一失败即中止，**不得**以「记录日志后继续」代替拒绝。

---

## 5. 后端：RBAC 引擎

### 5.1 三个要素

| 要素 | 载体 | 现状 |
| --- | --- | --- |
| ① 角色定义 | `platform_roles` / `component_roles`（`actions[]`） | **已存在**（DATA-MODEL §7.7） |
| ② 用户-角色绑定 | `platform_role_bindings` / `component_role_bindings` | ✅ **已存在且带 `expires_at`**（2026-09-22，`migrations/0011`；`ListMatching` 排除过期行 ⇒ §7.4 的到期语义**已生效**，不再是缺失项） |
| ③ **角色 → 接口映射** | 应为**表** | **未落表** —— 现状写在代码里（路由注册时传 action 字面量，如 `main.go` 的 `wrap(permmodels.ActionPipelineTrigger, "id", …)`） |

③ 落表的意义：让「某角色能打哪些接口」可被**独立审阅与对账**，而不是散在路由注册语句里。

### 5.2 Casbin 的边界（划定，别让它长进来）

| 策略类型 | 落在哪 |
| --- | --- |
| 简单 `resource:action`（有/无） | **hub 内置判定**（现有 `BindingService`） |
| 字段级、角色继承、临时/条件策略（如「仅工作时间可发生产」） | **Casbin** |

约束：Casbin **只做决策**，不替代 §6 审计与 §7 审批流；引入与否见 §12 D4。
（现状：仓库**无 Casbin 依赖**，仅 `internal/permission/models/role.go` 有一句「Casbin-style」注释；DATA-MODEL §7.6 将其列为「未来可选、不在本期」。本文件将其**提升为规范的一部分**。）

### 5.3 主体语义必须唯一（本条是最容易出歧义的地方）

`subject_id` 一列同时承载「用户」与「组」两种主体，因此**必须写死格式**，否则绑定会**静默不匹配**：

| `subject_type` | `subject_id` 必须写成 | 反例（会静默失效） |
| --- | --- | --- |
| `user` | Keycloak `sub` | 本地 UUID、email、username |
| `group` | **与 token claim 逐字一致**（挂 `full.path=true` 时是 **`/组名`**，带前导斜杠） | 写 `sdp-admins` 而 claim 是 `/sdp-admins` |

> 现状核对：`sdp-console` 的 groups mapper **已设 `full.path=true`**，但 realm 里**没有任何组** ⇒ claim 为空，组继承通路**装了没数据**。

---

## 6. 后端：操作审计

**原则：绝不让业务代码手动打日志。** 审计是**横切关注点**，统一在过滤器层完成。

| 项 | 规范 |
| --- | --- |
| 挂载范围 | **仅写操作**：`POST` / `PUT` / `PATCH` / `DELETE`（读操作不写审计） |
| 上报方式 | 中间件统一调用 **`audit.Reporter`**；业务代码零调用 |
| 记录内容 | 谁（用户 / 角色 / 来源 IP）· 何时 · 对什么（资源类型 + ID）· 做了什么（操作）· 结果（成功/失败 + 状态码） |
| 落库 | 单表 **`audit_log`** |
| 失败语义 | 审计写失败**不阻断**业务（降级为告警），但必须留痕 |

---

## 7. 后端：申请审批流（独立模块）

### 7.1 为什么要独立

> **审批是流程，决策是规则。两者解耦。**
> 审批模块**不得**被塞进权限决策模块；两者的唯一接口是**数据**（审批通过后写一条绑定），不是函数调用。

### 7.2 `permission_request` 表

（用户原述拼写为 `premission_request`，本文按 `permission_request` 为规范名。）

| 字段 | 说明 |
| --- | --- |
| `id` | 主键 |
| `requester` | 申请人（token `sub`） |
| `requested_role` | 申请的角色 |
| `requested_resource` | 申请的资源（组件/流水线…；平台级可空） |
| `reason` | 申请理由（**必填**，供审计） |
| `approver` | 审批人 |
| `status` | `Pending → Approved \| Rejected` |
| `effective_at` | 生效时间 |
| `expires_at` | **过期时间（核心）** |
| `created_at` / `decided_at` | 留痕 |

### 7.3 状态机

```
Pending ──► Approved ──► （写入绑定，带 expires_at）
   │
   └──────► Rejected
```

### 7.4 通过后写绑定 + 到期回收（合规审计的核心）

- 审批通过 ⇒ **自动写「用户-角色绑定」，并写入 `expires_at`**。
- **权限不能永久挂账**：到期后绑定失效（判定时即过滤），并有**定期回收**作业清理过期行。
- ⇒ 因此绑定表**必须有 `expires_at`**（现状缺，§10）；判定式必须**同时检查有效期**，否则「已过期但仍生效」会静默发生。

---

## 8. 前端：只做展示

| # | 规范 |
| --- | --- |
| 1 | **不做认证**、**不解析 token**（不读 payload、不判断过期、不据 token 做任何授权判断） |
| 2 | **登录跳转交给 Keycloak**（**由 console 触发** OIDC 跳转 —— console 即 OIDC Client，§2.4.1；hub 不参与跳转、不换 code）；拿到 token 后保存（localStorage 或由后端置 Cookie），保存方式见 §12 D5 |
| 3 | 后端提供 **`GET /api/userinfo`** 返回当前用户的**角色 / 组织** |
| 4 | 前端**只用它**隐藏/置灰按钮与菜单 —— **仅此而已** |

**红线**：前端不得出现任何形如 `if (token.roles.includes('admin'))` 的授权判断。

> 现状核对：console 用 `oidc-client-ts` 的 `UserManager` 解析并保存 token，读 `profile` 做登录态判断；**无 `/api/userinfo`**。⇒ 需改（§10）。

---

## 9. 数据模型归属（谁定义什么）

| 表 / 对象 | 定义位置 | 说明 |
| --- | --- | --- |
| `platform_roles` / `platform_role_bindings` | DATA-MODEL §7.7 | 需加 `expires_at` |
| `component_roles` / `component_role_bindings` | DATA-MODEL §7.7 | 需加 `expires_at`；`user` 主体改为 `sub` |
| `pipeline_approvals` | DATA-MODEL §7.4 | 流水线审批（**与 §7 权限申请是两件事**，勿混） |
| `resource_ownership` | **本文件 §3** | ✅ **已落地** —— `internal/permission/{models,repository,service,handler}/resource_ownership*.go` + 中间件 `RequireResourceOwnership` |
| 角色 → 接口映射表 | **本文件 §5.1③** | ✅ **已落地** —— `internal/permission/handler/role_api_mapping.go`（`RoleAPIMappingHandler`） |
| `audit_log` | **本文件 §6** | ✅ **已落地** —— 由 `middleware.AuditMiddleware` 唯一写入（`internal/middleware/audit*.go` + `audit_test.go`） |
| `permission_request` | **本文件 §7.2** | ✅ **已落地** —— `internal/permission/{models,repository,service,handler}/permission_request*.go` + `PermissionRequestHandler` |
| realm（账户 / 客户端 / 角色 / 组 / Organizations） | [shared/KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md) | Keycloak 侧 |

---

## 10. 与现状的对账（Conformance）

> 表格左边是**规范**，右边是**读代码所得的现状**。任一行 ❌/⚠ 即为待办；对账脚本化后应作为门禁。

| # | 规范要求 | 现状 | 结论 | 落点 |
| --- | --- | --- | --- | --- |
| 1 | Keycloak 不做授权决策 | hub `internal/middleware/auth.go` **刻意不读** `realm_access`（注释写明） | ✅ 方向一致 | — |
| 2 | token 携带**组织** | realm **无任何 `/org:<slug>` 组**（§2.3 默认载体 ②）；`groups` mapper 已挂且 `full.path=true`，但 **claim 为空**（与第 6 行同因） | ❌ → ✅ **已落地（2026-09-23，Task #4）**：hub `orgsvc` 在 org `Create` 后幂等 `EnsureGroup("/org:<slug>")`、启动 `ReconcileGroups` 回填存量（`internal/keycloak` Admin 客户端 + realm 赋 `sdp-backend` SA `manage-users`/`query-groups` 最小集）；`KEYCLOAK_ADMIN_CLIENT_SECRET` 缺失则 dev 不建组只告警 | hub 代码（`orgsvc` + `internal/keycloak`） |
| 3 | token 携带**角色** | `sdp-console` 已挂 roles mapper（写**顶层 `roles` claim**，非 `realm_access`），但 hub 不消费 | ✅ **已定**（不作判定输入，仅供对账/展示 —— 由不动式② + §2.1/§2.2 裁定，**非**待拍板；论证见 git 历史中的 plans/ACCOUNT-PERMISSION-DECISIONS.md（已删档，结论以本文件 §12 为准） §2） | §12 D2（已闭） |
| 4 | hub **不存用户表** | ✅ **已落地（2026-09-23，D3）**：`users` 表已删（`migrations/0015`）；`UserContext` 改为**纯解析**（无库、无 provision）；`CurrentUserID` 连同 7 个读取点全部并入 `CurrentSubject`（token `sub`）。⚠ 删表不可逆，部署侧须手工跑 `0015` | ✅ | migration + 代码 |
| 5 | 绑定主体 = token `sub` | `ListMatching` 两侧已按 **subject（`sub`）** 匹配（component 保留 V1 `user_id` 遗留分支）；`CurrentSubject` 由中间件注入 | ✅ **已落地（2026-09-22）** | repo + middleware |
| 6 | 组主体格式唯一 | realm 现有 RBAC 组 `/sdp-admin`（预置 `admin` 已加入）⇒ 组 claim **通路已通**；组织组 `/org:<slug>` 由 hub 运行时自动预置（见第 2 行） | ✅ 通路 + 首个 RBAC 组已就位 · ✅ 组织组已建（Task #4） | hub 代码（`orgsvc` + `internal/keycloak`） |
| 7 | 资源归属单表 | **已建表** `resource_ownership`（§3）+ CRUD 端点 + `IsAllowed` 纯逻辑；**✅ 中间件强制点已接（2026-09-22 第十一批）**：`RequireResourceOwnership` 在 RBAC 之前判归属，拒绝语与 RBAC 的 403 区分；对**未登记归属**的资源放行（当前全部资源如此 ⇒ 零回归） | ✅ **已落地（2026-09-22）** | 新表 §3 + middleware |
| 8 | 角色 → 接口映射落表 | **已建表** `role_api_mappings`（§5.1③）+ CRUD + `SyncFromRoles`；`BindingService` 生效动作集 = 角色 `actions` JSON ∪ 映射表 | ✅ **已落地（2026-09-22）** | 新表 §5.1③ |
| 9 | Casbin 承担复杂策略 | 无依赖；DATA-MODEL §7.6 标为「不在本期」 | ❌（D4 已定延后，登记 B-19） | §12 D4 |
| 10 | 审计中间件 + `audit_log` | **已落地**：`middleware/audit.go` 只记写操作 + `audit.Reporter`；业务零手写 | ✅ **已落地（2026-09-22）** | §6 |
| 11 | 权限申请审批 + 到期 | **已落地**：`permission_requests` 状态机 + 审批写绑定（带 `expires_at`）+ 到期**回收作业**（`BindingReaper`） | ✅ **已落地（2026-09-22）** | §7 |
| 12 | `GET /api/userinfo` | **已落地**：`handler/userinfo.go`（subject / username / groups / orgs / roles） | ✅ **已落地（2026-09-22）** | handler |
| 13 | 前端不解析 token | console 用 `UserManager` 解析并持久化 token、读 `profile` | ❌ | console |
| 14 | 强制点全覆盖 | 组件作用域路由经 `wrap()` 挂**两层**（a 资源归属 + b RBAC）；平台级路由挂 `RequirePlatformPermission`；`:id` 为 pipeline/run 时先反查 owning component | ✅ **已收口（2026-09-22）** | middleware |
| 15 | 平台级授予可达 | `platform_role_bindings` 端点已注册（`/platform-roles`、`/platform-role-bindings`）；**已种入组绑定** `/sdp-admin` → `sdp-admin`，且 **realm JSON 已建该组并预置 `admin` 入组**（第十一批）；console 平台权限管理页已落地（`PlatformAdminView`） | ✅ **已完成（2026-09-22，C-10）** | handler + realm CM ✅ |
| 16 | 对接走 **OIDC 标准流程**（discovery + JWKS 验签） | `coreos/go-oidc/v3` v3.20.0 已引入；`NewAuthenticator` = `oidc.NewProvider` + `provider.Verifier` | ✅ | — |
| 17 | hub 为 **Resource Server**：不建 client、不换 code、不持 secret | `AuthConfig` 仅 `IssuerURL`/`ClientID`，无 secret 字段；无 token 端点调用 | ✅ | — |
| 18 | 校验 `azp`；`aud` 明确跳过 | `auth.go` 的 `errWrongClient` + `SkipClientIDCheck: true`（附注释写明理由） | ✅ | — |
| 19 | **不调用** Keycloak 运行时 API（userinfo / introspection / Admin） | 全仓无相关调用（仅 realm JSON 的 mapper 键名含 `userinfo`） | ✅ | — |
| 20 | 启动 **fail-fast**（issuer 不可达 = 不启动） | `cmd/hub/main.go`：`NewAuthenticator` 出错 → `applog.Fatalf` | ✅ | — |

**第 14 行的性质**：与「账号」无关，但它会让整套鉴权在开启后**立刻不可用**，故必须在开开关前修（修法：中间件先由 pipeline/run 反查 `component_id`）。


**已修（2026-09-22）**：`middleware/rbac.go` 改为按 `Requirement.Resource`（component / pipeline / run）解析路径 id，`internal/permission/service/locator.go` 负责反查（run 走 run → pipeline → component 两跳）；同时固定拒码语义（401 无身份 / 400 参数非 UUID / 404 反查不到 / 403 确实无权限 / **500 查询本身失败**——故障不再伪装成「没权限」）。单测：`internal/middleware/rbac_test.go`（10 例）+ `internal/permission/service/locator_test.go`（6 例）。**注意**：本次**未动**「主体 = 本地 `users.id` 还是 token `sub`」，那属 §12 D3。

**对账脚本化（2026-09-25，#17 收口）**：上表静态不变量已固化为持续门禁 `internal/middleware/conformance_test.go`（随 `go test ./internal/middleware/...` 运行），断言：① hub 不消费 `realm_access`/`resource_access`（§10 #1/#3，经 AST 检查 claims 结构体 JSON tag 而非子串，避免把「注释里声明不读」误报）；② `AuthConfig` 不得携带任何凭据字段（§10 #16/#17 Resource Server 不变量）；③ 校验 `azp`、跳过 `aud`（§10 #18：`SkipClientIDCheck: true` + `errWrongClient`）；④ 鉴权路径不调用 Keycloak 运行时 introspection/userinfo（§10 #19）；⑤ 三个强制点符号（`RequireResourceOwnership` / `RequirePermission` / `RequirePlatformPermission`）存在且被引用（§10 #7/#14，重构删改即编译失败）。对账表新增行时须同步补断言；断言失败即门禁红，禁止用「文档已说明」豁免。
---

## 11. 落地顺序与门禁

| # | 步骤 | 门禁 |
| --- | --- | --- |
| 1 | **D1–D6 已闭（0 项阻塞）**：D2 / D3 / D4 / D6 由本文件正文裁定，D1 / D5 按**可逆默认**自决 —— 见 §12 与 git 历史中的 plans/ACCOUNT-PERMISSION-DECISIONS.md（已删档，结论以本文件 §12 为准） §0.1 | 无 —— realm 与表结构**均可定稿**（§2.3 硬约定使 carrier 可换，**不需要**先拍 D1） |
| 2 | realm 侧（**D1 默认载体 ②**）：预置组织组 `/org:<slug>` + 预置账号；groups mapper **已在**、`full.path=true` ⇒ **无需开 Organizations、无 identity-first 登录流变化** | ① `helm template` 渲染产物解析 realm JSON 通过；② 按 `shared/KEYCLOAK.md` §4 第 5 步的 password-grant curl 取 token，**解码断言 `groups` claim 含 `/org:*`**；③ **仅当**切 ①（federation）时才需实测「组织集能否随 realm JSON 导入」 |
| 3 | 表结构：**✅ 四表已落（2026-09-22 第八批，`0012`）** —— `resource_ownership` / `role_api_mappings` / `audit_log` / `permission_requests`；**✅ `expires_at` ×2（`0011`）**；**✅ C-10 平台级端点已落** | migration 可在空库 + 存量库双向执行；C-10 端点可用，且已种入 `/sdp-admin` 组绑定 —— D2① 落地后**不会**出现「无人是平台管理员」（见 git 历史中的 plans/ACCOUNT-PERMISSION-DECISIONS.md（已删档，结论以本文件 §12 为准） §2.5） |
| 4 | 认证/鉴权中间件按 §4 顺序重排：**✅ 已全部落地** —— subject 解析（`CurrentSubject`）+ 鉴权路径按 `sub` 匹配（2026-09-22），**D3 删 `users` 表 / `CurrentUserID` / V1 遗留列（2026-09-23，`migrations/0015`）** | Go 单测 + `go vet/build/test` ✅ |
| 5 | RBAC ① → ③ 落表并成为判定输入：**✅ 映射表已落 + `BindingService` 生效动作集并入（2026-09-22）**；**⏳ 种 `admin` 的 `sub` 平台管理员绑定待 realm 有组后补种** | 判定结果与旧实现逐例对照；`auth.go` 的 `keycloakClaims` **不得**出现 roles 字段（**防回退静态断言**） |
| 6 | 审计中间件 + `audit.Reporter`：**✅ 已落地（2026-09-22）** —— `middleware/audit.go` 只记写操作 | 写操作有审计行；业务代码零手写（静态检查） |
| 7 | 审批流独立模块 + 到期回收作业：**✅ 已落地（2026-09-22）** —— `permission_requests` 状态机 + `GrantWriter` + `BindingReaper` | 端到端：申请 → 通过 → 绑定生效 → 到期失效（单测覆盖状态机 + 回收谓词；**未跑真实库**） |
| 8 | `/api/userinfo`：**✅ 已落地（2026-09-22）**；**⏳ console 改造（去 token 解析）未做** | 前端不再引用 token payload（静态检查） |
| 9 | **最后**才打开两端鉴权开关 | 全链路 E2E（✅ 已于 2026-09-24 真集群执行，证据见 `plans/STATUS.md` §1.4） |

---

## 12. 决策状态（**0 项阻塞**）

> **不再需要拍板**（第二轮复核，2026-09-22）：D1–D6 里 **4 项已由本文件正文裁定**（D2 / D3 / D4 / D6），**2 项按可逆默认自决**（D1 / D5）。下表「结论」列即**当前生效值**，「备选 / 翻盘条件」列保留供追溯 —— 含「为什么钢人论证仍不等于拍板」的分级论证，见 git 历史中的 plans/ACCOUNT-PERMISSION-DECISIONS.md（已删档，结论以本文件 §12 为准） §0.1。

| # | 问题 | **结论（生效）** | 备选 / 翻盘条件 |
| --- | --- | --- | --- |
| **D1** | 「组织」用什么载体？ | **② 组命名约定 `/org:<slug>`**（复用已就绪的 `groups` 通路；**组随 realm JSON 可靠导入** ⇒ 保住「配置即代码」；零 realm 开关） | ① Keycloak **Organizations**：**翻盘条件 = 出现「多 IdP / 跨组织 SSO 联邦」需求**；因硬约定（组织键=alias、组织不作主体）**切换无需数据迁移**。① 已知成本：开开关 ⇒ **identity-first 登录流变化**；组织集能否随 realm JSON 导入**未证实**；**scope 形态须选定**（`organization`=ANY / `organization:<alias>`=SPECIFIC / `organization:*`=ALL）。**v2 曾推荐 ①（理由「语义隔离」），本轮下调为 ②** —— ② 用保留前缀等价隔离（硬规则：`/org:` 前缀不得作 `group` 绑定主体）。**不可逆性由「高」降为「中」** |
| **D2** | 角色/权限的权威在哪？ | **① 全在 hub RBAC 表**（token 角色仅供对账/展示）—— **已由不动式② + §2.1 / §2.2 裁定，无需拍板** | ②（hub 表 + token 角色参与）/ ③（token 角色为准）均与**不动式②「hub 是唯一权限权威」冲突** ⇒ 不做。⚠ 前置 **C-10**（平台级端点/种子）**仍在** —— 否则落地后无人是平台管理员 |
| **D3** | 「不存用户表」的连锁改动 | **主体键 = token `sub`**（§5.3；`group` 用 claim 逐字）；第 4 处取 **(b′) 只列已绑定主体 + 允许手输 `sub`**。**✅ 5 处全部落地（2026-09-23）** | ➎ **已执行**：`users` 表已删 + `UserContext` 纯解析 + `CurrentUserID` 并入 `CurrentSubject`（原 7 个读取点）；① `components.owner_user` → `owner_sub`（text，回填自 `users.keycloak_id`）；② `user_id` / `role_id` 已删列（V1 解析分支同批移除）；③ approver / operator / createdBy 改取 `sub`；④ console 改「绑定表派生 + 手输」。迁移 `0015`（**不可逆**）—— 代码已落，部署侧须手工 psql |
| **D4** | Casbin 是否本期引入 | **延后**（`shared/DATA-MODEL.md` §7.6「不在本期」+ §5.2 边界已划）—— **已定** | 引入 = **条件触发**：触发条件与硬约束已登记 **B-19**（[hub/STORY-BACKLOG.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md)），非待决 |
| **D5** | token 存法 | **维持 localStorage**（`console/src/stores/auth.ts` 现状；**本文件对此本就沉默** ⇒ 属实现细节）—— **可逆，自决** | BFF / 后端 Cookie：安全基线升级时再议；纯前端单点改动，**可逆** |
| **D6** | `aud` 校验方式 | **① 维持：不校 `aud`、校 `azp`**（§2.4 已实现）—— **已定** | ② 加 **audience mapper** + 去 `SkipClientIDCheck` —— **条件触发**（需按 audience 区分多个资源服务器时），非待决 |

### 12.1 实施期落地裁定（自实施批次归档，2026-09-22 ~ 09-24）

> 以下裁定在实施中做出，是本模型**设计逻辑的一部分**；原文散于已清理的计划文档，此处为唯一权威落点。

**RBAC 引擎落地七条**（对应 §5 / §7）：
1. **到期语义落在 `ListMatching`**，不在 API 边界过滤——它是鉴权中间件唯一的绑定解析路径，只在边界过滤则过期绑定仍授权。**过期行不删**（审计须能回答"曾经授过什么"）；管理面 `List` 不过滤，否则管理员无法清理。
2. **`/org:` 保留前缀禁止作绑定主体**——落实 D1「组织不作 RBAC 主体」，组织载体日后可换而无需数据迁移。
3. **组主体强制前导斜杠**（realm `groups` mapper `full.path=true`）——写 `sdp-admins` 而 claim 是 `/sdp-admins` 的静默不匹配被变成 `400`，不存永不生效的绑定。
4. **内置角色不可改删；被引用时拒删（`409+{reasons}`）**——防一次误操作清空 `sdp-admin` 致所有人进不去。
5. **错误构造用函数**（每次返回新 `*APIError`）——避免包级单例被 `WithError` 并发互踩。
6. **`isSystem` 服务端强制置 `false`**——调用方无法经 POST 伪造"不可改删"角色。
7. **重复授予前置校验用 `ExistsActive`**（只看仍生效绑定）——否则一条今天过期的绑定会永久挡住重新授予。

**资源归属空值语义**（双向钢人，唯一真正有争议点）：方案 A（严格 fail-closed）vs 方案 B（无组织即放行）——裁定 = **用「资源是否已登记归属」切开**：未登记 → 放行（上线零回归）；已登记 → 组织不相交或请求不带组织都拒（"登记归属"成为显式收紧动作，无需开关/迁移窗口）。配套：归属拒用独立错误 `errOutOfOrg`，不与 RBAC `errForbidden` 混用（两者修法不同：改归属行 vs 改角色绑定）。归属只在**组件粒度**登记，pipeline/run 经 `permLocator` 继承；dev 模式（auth==nil）两段守卫整体不装。

**D3 删表三裁定**（2026-09-23 第十四批）：①删表后授权闭环由**手输 `sub`** 补（管理员从 Keycloak 复制即可授权新人，不新增 hub 持有 KC 管理凭据的安全面；若出现"必须展示全量用户目录"的产品要求，按决策 §3.5 重估并独立评审）；②旧 `owner_user` 回填失败**留 NULL + `RAISE WARNING`**（owner override 只是绑定被删后的兜底，P3b 创建时的 `component-admin` 绑定不受影响）；③作者类列（approver/operator/createdBy 等 uuid 主体列）**一起切并清掉映射不到的残留**——残留旧 uuid 是"看似主体、实解析不到人"的值，比留白更危险。

**配套实施裁定**：①Keycloak Admin 客户端**自研**（`net/http`+`httptest`，零外部依赖即可单测），不引 SDK；②凭据存储选 **AES-GCM 信封加密**（项目无外部 secret store，"只存引用名"无法落地；明文兼容 legacy 保迁移安全）→ 详见 `DELETE-CONTRACT` §6.6；③**V1 `roles` 表裁定保留**（全仓活引用 + DROP 不可逆，"有引用则停手记录"；真删须先清 model/repo/service/handler/AutoMigrate/seed 全部引用并获用户显式确认）。

---

## 13. 相关文档

| 文档 | 关系 |
| --- | --- |
| [shared/KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md) | 上游：认证子系统部署、realm 预置、账号改密 |
| [shared/DATA-MODEL.md §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) | 下位：两层 RBAC 与审批表的字段级 DDL |
| [shared/API-REFERENCE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md) | 端点权威清单（`/api/userinfo` ✅ **已补入** —— `GET /userinfo`，`internal/permission/handler/userinfo.go`，`cmd/hub/main.go` 注册于裸 `api`） |
| [hub/STORY-BACKLOG.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-BACKLOG.md) | C-10（平台级 RBAC 端点缺失） |
| [console/CONSOLE-UI-DESIGN.md §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI-DESIGN.md) | 前端权限与审批 UX |
| [runner/STORY-runner-implementation.md §4.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md) | 下游：runner 侧 k8s RBAC 授权边界 |
