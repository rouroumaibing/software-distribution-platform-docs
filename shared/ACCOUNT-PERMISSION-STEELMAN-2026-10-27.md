# 双向钢人：§10 #13（前端 token 解析残留）与 /api/userinfo 未消费

> 来源锚点：`shared/ACCOUNT-PERMISSION-MODEL.md` §8 #1 / §10 #13 / §11 #8。
> 本文件为决策分析记录（非正文）；结论已收口至 `ACCOUNT-PERMISSION-MODEL.md` §14 变更历史与对应对账行。正文保持只写最新现状。

---

## 0. 现状复述（source-grounded，非推断）

- **设计红线**（`ACCOUNT-PERMISSION-MODEL.md` §8 #1）：前端不认证、不解析 token（不读 payload、不判断过期、不据 token 做任何授权判断）；唯一例外是「`GET /api/userinfo` 返回角色/组织，前端仅用于隐藏/置灰按钮」（§8 #3–4）。红线例句：`前端不得出现任何形如 if (token.roles.includes('admin')) 的授权判断`。
- **§10 #13 对账结论**：标注 ❌ ——「console 用 `UserManager` 解析并持久化 token、读 `profile`」→ 判为「前端不解析 token」未达成。
- **§11 #8**：`/api/userinfo` 在 hub 已落地（`internal/permission/handler/userinfo.go`），但「console 改造（去 token 解析）未做」→ 即 userinfo 未被消费。
- **代码事实**（已读源码）：
  - `console/src/stores/auth.ts`：`oidc-client-ts` `UserManager`（Authorization Code + PKCE），持有 `user.access_token`（API Bearer）、`user.expired`（登录态 getter）、`user.profile`（身份）。`isAuthenticated = !!user && !user.expired`，`accessToken = user.access_token`。
  - `console/src/layout/MainLayout.vue:158-167`：个人中心 `computed` 读 `auth.user?.profile`，并把 `p.realm_access.roles` 当作「Realm 角色」展示。
  - 全仓检索：无任何 `token.roles.includes` / 据 token 声明做访问控制/路由守卫的代码；403 统一由 `src/api/http.ts` 拦截器跳 `/forbidden`（即「后端说了算」），菜单显隐也由后端 403 驱动，而非前端读 token。
- **结论先行**：console **没有违反安全红线**——它从未据 token 做授权决策。§10 #13 把「库级解析 token（OIDC 客户端物理必需）」与「应用级据 token 授权（红线禁止）」混为一谈，误判为 ❌。真正的残留有且只有两点且都很窄：
  - **(a)** 个人中心展示了 `profile.realm_access.roles`（token 角色），与「角色权威在 hub、token 角色仅供对账/展示」（§10 #3）自相矛盾，并制造「两个角色来源」的歧义；
  - **(b)** hub 已提供 `/api/userinfo`，但 console 从未消费它——既没用它取角色/组织，也没用它做身份展示。
- 两条残留本质上是**同一件事**：console 缺一次「从 hub 取授权相关展示数据」的调用，却回退去读 token 角色。

---

## 1. 钢人 A（支持「严格不读 payload」= 字面执行 §8 #1）

**立场**：前端 app 代码一行都不该读 token payload。

**论据**：
1. **单一真相源**：权限模型 §2.1 / §2.2 裁定 hub 是唯一权限权威，token 角色「仅供对账/展示」（§10 #3 结论）。若 console 既显示 token 角色、又不显示 hub 角色，会出现「界面说的角色 ≠ 后端强制的角色」的漂移——例如绑定变更后 token 未刷新，界面仍显示旧角色，或反之。把角色展示的唯一来源定为 `/api/userinfo`，才能消除漂移。
2. **防渐进越界**：app 一旦「读 `profile` 取角色做展示」，下一个开发者极易顺势写成「读 `profile` 取角色做隐藏/置灰」，红线 `if (token.roles.includes)` 的口子从展示侧被撬开。静态审查无法阻止这种渐进越界。
3. **语义清晰**：token 是 bearer 凭证（给 hub 验签用），不是数据通道。身份长期展示本就不是 token 的职责；OIDC 的 id_token 虽带 profile，但那是为「登录瞬间拿到用户名」用的，长期展示应走后端。
4. **降级可控**：dev 模式（`VITE_AUTH_DISABLED`）本就用伪造 `devUser`；userinfo 也可走同样降级，不增加复杂度。

**最强翻盘条件**：若 hub `/api/userinfo` 在 boot 时不可用，界面将拿不到角色/用户名。但这是实现细节（profile 兜底即可），不构成推翻「角色来源 = hub」。

---

## 2. 钢人 B（支持「务实保留 profile 读取」= 当前实现基本合理）

**立场**：console 读 `profile` 做身份展示是 OIDC 标准用法，红线只禁止「授权决策」，不应扩大化到「任何读 payload」。

**论据**：
1. **库级解析不可避免**：`oidc-client-ts` 作为 OIDC client 必须解码 id_token（silent renew 依赖 `exp`、Bearer 注入依赖 `access_token`）。「前端不解析 token」在库层面物理上不可能，因此红线的真实含义只能是「应用代码不据 token 做授权判断」——这一点 console 已经做到（403 全交后端）。
2. **身份 ≠ 授权**：`name` / `username` / `email` / `sub` 是身份标识，不是权限。OIDC 设计上 id_token 就携带这些；要求 console 不读 `profile` 而绕道 `/api/userinfo` 拿同样的 `username`，是绕远路。`profile` 用于顶栏问候、个人中心、`notifCursorKey`（用 `sub`）都是身份用途，安全无关。
3. **减少 boot 依赖**：`profile` 随 token 落地即同步可用；若强制走 `/api/userinfo`，每次冷启动多一次 hub 往返，且 hub 挂了界面连「你是谁」都不知道（尽管 API 仍 401，但 UX 更脆）。
4. **角色展示的 token 来源并非「错误」**：§10 #3 明写 token 角色「仅供对账/展示」，个人中心把它展示出来恰好是「展示」用途，并未越界到授权。

**最强翻盘条件**：当 hub RBAC 角色与 token 角色出现**语义分叉**时，界面若只显示 token 角色会误导用户。这正是真实风险——当前 `realm_access` 角色（Keycloak realm 级）与 hub 平台角色（`/api/userinfo` 的 `roles`，hub RBAC 表级）是**两套命名空间**；个人中心显示 `realm_access`，而「用户与权限」页显示 hub 平台角色，用户会困惑「我到底有哪些角色」。

---

## 3. 综合裁定（synthesis）

两条钢人在「身份 vs 授权」的切分上达成一致，分歧只在「授权相关展示（角色/组织）的来源」。裁定如下：

- **红线重述（防回退，写入 §8 #1）**：「前端**应用代码不得**据 token 声明做任何**授权**判定（含隐藏/置灰菜单、路由守卫、功能开关）；`oidc-client-ts` 库级解析（renew / expiry / Bearer 注入）不可避免、不在红线范围；`user.expired` 仅用于登录态 UX，每次 API 调用由 hub 重校验，不构成安全边界」。红线例句 `if (token.roles.includes('admin'))` 维持。
- **身份展示**（`name` / `username` / `email` / `sub`）：允许来自 `profile`（OIDC 标准、零额外往返、dev 降级简单）。可顺带用 `/api/userinfo` 的 `username` 对齐，但非强制。
- **授权相关展示**（`roles` / `orgs`）：**必须**来自 `/api/userinfo`（hub 权威），**禁止**读 `profile.realm_access` / token 角色。这同时闭合 §10 #13 残留 (a) 与 `/api/userinfo` 未消费 (b)。
- **实现落点**（Task 10）：console 新增 `userinfoApi`（`GET /api/userinfo`），`auth` store 在 `init`（登录恢复 / 回调后）拉取并缓存 `roles` / `orgs`；`MainLayout` 个人中心改用 `userinfo.roles`（可标注「平台角色」以区别于历史 realm 角色语义）；`profile` 仅保留身份四字段。

---

## 4. 关键变量与风险

- **关键变量**：hub RBAC 角色 vs Keycloak realm 角色是**两套命名空间**。个人中心若继续显示 `realm_access`，会与「权限管理页显示的 hub 平台角色」冲突。→ 因此角色展示切到 `/api/userinfo` 不是「锦上添花」，而是消除语义冲突的必要动作。
- **风险 1**：`/api/userinfo` 在 boot 时 hub 未就绪 / 401 → 个人中心角色区降级为空（不报错），身份仍来自 `profile`。实现层用 `try/catch` 静默，不阻断登录态。
- **风险 2**：KC Admin 代理 SA 凭据集在真实 KC 26 是否够用（`manage-users` / `query-groups` / `query-users` / `view-users`）——属 Task 11 端到端验证项，非本分析范围；`ACCOUNT-PERMISSION-MODEL.md` §14 已记录「`query-groups` 需单授说明复合角色不含 query 类，目录列用户能力显式补齐」。

---

## 5. 决策（已收口至 `ACCOUNT-PERMISSION-MODEL.md` §14）

- §10 #13 结论由 ❌ 改为：**安全语义已达成（app 未据 token 做授权决策）；残留 = 个人中心误读 token `realm_access` 角色 + userinfo 未消费 → 裁定从 `/api/userinfo` 取角色/组织，`profile` 仅留身份展示**。
- 新增 console 实现项：消费 `/api/userinfo`（Task 10）。
- §8 #1 红线重述为「应用代码不据 token 做授权判定；库级解析不可避免；`expired` 仅登录态 UX」。
- §11 #8 `/api/userinfo` 状态由「⏳ console 改造未做」推进为「裁定已下，实现中（Task 10）」。
