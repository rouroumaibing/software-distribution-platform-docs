# 访问控制模型（Access Control：用户 / 用户组 / 组织 + 双层角色 + K8s RBAC）

> **本文件的地位 = 规范（normative），不是现状快照。**
> 它写「应当是什么」，并在 §12 与代码 / realm 配置做逐项对账；对账不通过即视为漂移。
>
> **范围**：前端访问控制（用户 / 用户组 / 组织的 CRUD 与页面可见性）+ K8s RBAC 授权层（集群权限下发、kubeconfig 签发、证书吊销）。
> **不在范围**：认证会话（见 [shared/AUTH-ARCHITECTURE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/AUTH-ARCHITECTURE.md)）与 hub API 鉴权决策（见 [shared/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md)）——两者是本文档的下游地基。

---

## 0. 三层叠加与两条不动式

平台访问控制由三层叠加，各层职责互不替代：

| 层 | 文档 | 职责 |
| --- | --- | --- |
| 认证层 | AUTH-ARCHITECTURE | 你是谁（BFF cookie session，KC 签发 token 不出后端） |
| 安全层 | ACCOUNT-PERMISSION-MODEL | hub API 能不能调（hub RBAC 绑定表是唯一判定权威） |
| **可见性 + K8s 授权层（本文档）** | ACCESS-CONTROL | 页面/菜单看不看得见（L1/L2 双层角色）；用户集群里能操作什么（K8s RBAC 下发） |

**两条不动式：**

| # | 不动式 | 含义 |
| --- | --- | --- |
| ① | **L1/L2 只决定可见性** | 双层角色喂前端菜单/路由守卫（UX）；hub API 鉴权仍走安全层绑定表。**菜单可见 ≠ API 可调**；「前端已隐藏所以后端不必校验」依旧无效（承接 ACCOUNT-PERMISSION-MODEL 不动式③）。 |
| ② | **K8s RBAC 层是独立授权面** | 它授权的是**用户目标集群内**的操作（经 kubeconfig 证书），与 hub API 鉴权互不替代、互不推导。两把钥匙，两道门。 |

---

## 1. 双层角色模型

### 1.1 L1 系统角色 = realm role（决定平台级菜单可见）

| 角色 | 语义 | 菜单面 |
| --- | --- | --- |
| `platform-admin` | 平台管理员：全部平台级管理面 | `/admin/*` 全部 |
| `operator` | 运维操作员：执行操作，不管账号/组织 | 总览、服务树、运行中心、接入/凭据管理 |
| `auditor` | 审计员：只读 + 审计面 | 总览、服务树（只读）、平台审计日志 |
| `viewer` | 观察者：纯只读 | 总览、服务树（只读） |
| `self-provisioner` | 自助开通者：可自助建组件/环境 | 服务树 + 自助开通入口 |

- **预置**：五角色随 realm JSON 导入（`roles.realm` 顶层，非 client role）；token 经 `sdp-console` 的 `oidc-usermodel-realm-role-mapper` 携带于**顶层 `roles` claim**（KC26 现状：不在 `realm_access`，核对按 `roles`）。
- **判定边界（不动式①）**：L1 只喂前端可见性。hub 鉴权路径**不消费** realm role（`conformance_test.go` 的 `TestConformance_NoRealmRoleConsumption` 门禁维持不变）。
- **对账义务**：五角色须同步种入 hub `platform_roles`（`actions` 对齐各角色语义）。token 里的 L1 与 hub 绑定表的角色是**两份事实**，由对账暴露错位（菜单可见但 API 403，或反之）——错位是配置错误，不是设计行为。

### 1.2 L2 组织角色 = attributes（决定组织内页面可见）

- **载体**：user / group 的 KC attributes，键 `org_admin`，值为组织名数组（多组织天然支持）：`"org_admin": ["<orgName>"]`。**不是 realm role**（坑 1）。
- **进 token**：`sdp-console` 挂 user-attribute mapper（`org_admin` → 顶层 claim，multivalued）。
- **判定**：前端路由守卫查「当前用户的 `org_admin` 含当前组织名」→ 放行 `/org/dashboard` 及组织作用域菜单。
- **事实源**：组织创建时的 `annotations.org_manager`（§3）是唯一登记点——建组织时把 org_manager 同步写入该用户的 `org_admin` 属性；后续变更走组织注解更新（双向同步由 hub 编排，console 不直改 attributes）。

### 1.3 前端数据源

菜单/路由守卫的角色数据一律来自 **`GET /api/userinfo`**（hub 会话面返回 `roles`（L1）+ `orgAdmins`（L2）+ `orgs`/`groups`），**不直接解析 token**（承接 ACCOUNT-PERMISSION-MODEL §10 #13 裁定：授权相关展示必须来自 hub 权威端点）。

---

## 2. 预置与启动编排

1. **realm 预置**：五 realm role（§1.1）+ `sdp-console` client（已有，public + PKCE + directAccessGrants）。
2. **hub 启动编排**（幂等，启动时执行）：
   - 建默认组织（DB `orgs` + 1:1 service tree）；
   - 建默认组织的管理员子组 `/{org}/admins`（KC CreateSubGroup）；
   - 把 bootstrap admin 用户加入 `/{org}/admins`。
3. **bootstrap admin 语义不变**：`admin/sdp@12345` 首登强制改密（UPDATE_PASSWORD），改密后即为默认组织管理员（L2 `org_admin` 含默认组织名）+ `platform-admin`（L1）。

---

## 3. 组织（Org）

### 3.1 模型

| 字段 | 载体 | 说明 |
| --- | --- | --- |
| `metadata.name` | DB `orgs.name`（slug 唯一索引） | 组织名 = KC 组路径段 |
| `annotations.org_manager` | DB（jsonb） | 组织管理员的 username，单点事实源（§1.2） |
| `quotas` | DB（jsonb） | 组织配额（组件数/环境数/pipeline 数等，落地时定字段） |

### 3.2 CRUD 契约

- `POST /api/v1/organizations`，body：`{ "metadata": { "name": "..." }, "annotations": { "org_manager": "..." }, "quotas": { ... } }`
- **事务性**：一个组织 = 三件套，全部成功才提交，任一失败**整体回滚**：
  1. KC 顶层组 `/{org}`（CreateGroup）；
  2. KC 管理员子组 `/{org}/admins`（CreateSubGroup）+ org_manager 用户入组 + 写 `org_admin` 属性；
  3. DB 行（orgs + service tree + quotas）。
- `DELETE /api/v1/organizations/{org}`：级联清 KC 组树（含子组）+ DB 行 + **hub RoleBinding（platform/component 两类）** + **活跃 session**（坑 2）。

---

## 4. 用户（User）

- `POST /api/v1/users?org=&group=`，body：`{ username, email, initialPassword }`
  - hub 调 KC `CreateUser`，**一次写入组路径**：`user.Groups = ["/{org}", "/{org}/{group}"]` —— KC 层级组语义自动建立 membership（组 + 父组），无需二次 AddGroupMember。
  - 初始口令 temporary + `UPDATE_PASSWORD`（承接强制改密闭环）。
- `DELETE /api/v1/users/{id}`：级联清 KC 用户 + **hub RoleBinding** + **活跃 session**（坑 2）。

## 5. 用户组（Group）

- `POST /api/v1/organizations/{org}/groups`，body：`{ name }` → KC `CreateSubGroup`（父 = `/{org}`）。
- 成员管理：
  - `POST /api/v1/organizations/{org}/groups/{group}/users/{userId}`（adduser）
  - `DELETE /api/v1/organizations/{org}/groups/{group}/users/{userId}`（deluser）
- `DELETE /api/v1/organizations/{org}/groups/{group}`：级联清成员 membership + hub RoleBinding + 活跃 session（坑 2）。
- **保护规则**：默认管理员子组 `/{org}/admins` **不可删、不可改名**（hub 服务层强制，非仅 UI 置灰）。

---

## 6. 前端双路由与菜单可见性

| 路由 | 守卫输入 | 数据源 |
| --- | --- | --- |
| `/admin/dashboard`（平台管理面） | L1：`userinfo.roles` 含 `platform-admin`（细分页按 §1.1 菜单面） | `/api/userinfo` |
| `/org/dashboard`（组织工作台） | L2：`userinfo.orgAdmins` 含当前组织名 | `/api/userinfo` |

- 守卫失败 → `/forbidden`（已有页），不回登录（已认证，只是无权）。
- 菜单渲染同一数据源驱动（L1 → 平台级菜单树；L2 → 组织作用域菜单）。
- 既有 `/admin/*` 五页（targets/credentials/audit/settings/upgrade-approvals）并入 L1 守卫；`/org/dashboard` 为新增面。

---

## 7. K8s RBAC 授权层（独立授权面）

> 前端「集群权限」菜单创建 RoleBinding / ClusterRoleBinding；hub 复用 **environment kubeconfig 凭据**（parse-kubeconfig 已解析的目标集群凭据）直连目标集群下发。**通道裁定**：不新增凭据种类，环境凭据即集群管理凭据（`create` RBAC 资源权限须在环境凭据中具备，缺失时创建报 403 并提示凭据权限不足）。

### 7.1 绑定契约

- `subject.kind`：`User` / `Group` / `Org`，`subject.name` 分别绑 `user_id` / `group_id` / `org_id`（hub 侧 ID）。
- 预置五角色（目标集群内以 ClusterRole + Role 形式落）：

| 角色 | 资源面 | 语义 |
| --- | --- | --- |
| `admin` | 全资源 + RBAC 资源 | 集群内管理员 |
| `ops` | 工作负载 + 网络 | 运维操作 |
| `dev` | 工作负载（namespaced） | 开发自助 |
| `readonly` | 全资源只读 | 观察者 |
| `custom` | 自选资源 × 操作 | 按勾选生成 verbs |

### 7.2 资源 × 操作 → K8s verbs 映射

资源五类（`pods` / `deployments` / `services` / `configmaps,secrets` / `namespaces`），操作两类：

| 操作 | K8s verbs |
| --- | --- |
| `manage` | `create, update, patch, delete, deletecollection` |
| `query` | `get, list, watch` |

`custom` 角色 = 五类资源 × 两操作的任意勾选组合 → 生成对应 verbs 集合（Role rules）。

## 8. Kubeconfig 签发

- 给主体签发 kubeconfig 时：
  - **证书 CN（subject.name）** = `<uid>-<hash>`（用户）或 `<groupid>-<hash>`（组）——`<id>` 为 hub 侧 ID，`<hash>` 为一次性随机值；
  - **证书 O 字段** = 同一 `<hash>`（吊销审计标识）；
  - **CRB/RoleBinding 资源名固定** = `<id>-cert`，其 `subjects[0].name` = `<uid>-<hash>`（与证书 CN 逐字一致，K8s 认证才通过）。
- 签发通道：经目标集群 CSR API（`certificates.k8s.io`）签发，hub 不持目标集群 CA 私钥（最小信任面）；CA 来源 = 目标集群自身。

## 9. 证书吊销

- **只换 subject，不删 CRB**（坑 3）：
  1. 生成新 `<hash'>`；
  2. `PATCH` CRB `<id>-cert` 的 `subjects[0].name` → `<uid>-<hash'>`；
  3. 旧证书（CN = 旧 hash）不再匹配任何 CRB subject → 认证失效，**吊销完成**。
- 不删 CRB 的理由：删除会丢失 `roleRef` 关联与审计脉络；换 subject 保持绑定结构稳定，吊销 = 纯 subject 变更。
- 重新签发 = 同一 CRB 换新 subject + 新 CSR 流程。

---

## 10. 三坑（设计内硬约束）

| # | 坑 | 根因 |
| --- | --- | --- |
| 1 | **组织角色用 attributes，非 realm role** | KC realm role 是全局扁平命名空间，承载不了「同一人分别是 A/B 两组织管理员」的组织维度；attributes 多值数组天然表达。 |
| 2 | **删用户/组/组织必须级联清 RoleBinding**（hub 两类绑定表 + 活跃 session） | hub 主体键 = KC `sub`/组路径，KC 侧删除后 hub 绑定成孤儿行——孤儿绑定继续授权即越权。`BindingReaper` 只回收过期，不回收孤儿，级联必须在删除路径上同步做。 |
| 3 | **吊销证书只换 subject 不删 CRB** | 删 CRB 丢 roleRef 关联；换 subject 即达成「旧证书无处匹配」，结构零破坏。 |

---

## 11. 与既有规范的关系与修订项

| 对象 | 关系 |
| --- | --- |
| ACCOUNT-PERMISSION-MODEL **D1**（组织载体 = `/org:<slug>` 保留前缀、平级组；「组织不作 RBAC 主体」） | **修订**：组载体升级为层级模型 `/{org}/{group}`；`/{org}` 与 `/{org}/{group}` 均可作 `subject_type=group` 绑定主体。`/org:<slug>` 保留前缀规则废止（迁移时存量组须转换）。 |
| ACCOUNT-PERMISSION-MODEL **D2**（角色权威全在 hub 表，token 角色仅对账/展示） | **维持且强化**：L1 realm role 的消费面 = 前端菜单可见性（属 D2 已许可的「展示」）；hub 鉴权路径不读 realm role 的 conformance 门禁不变。 |
| ACCOUNT-PERMISSION-MODEL §1 时序 / §2.4 / D5（Bearer token、localStorage） | **已被 AUTH-ARCHITECTURE（BFF cookie session）实际取代**，该文档相应章节待修订（登记为待办，不在本文档展开）。 |
| AUTH-ARCHITECTURE | 上游：本文档所有「当前用户是谁」来自 BFF 会话（cookie + `/api/userinfo`）。 |
| KEYCLOAK.md | realm 预置（五 role + 层级组 + attributes mapper）落地图纸。 |

## 12. 现状对账（Conformance）

| # | 规范要求 | 现状 | 结论 |
| --- | --- | --- | --- |
| 1 | realm 预置五 L1 角色 | realm roles = `default-roles-sdp/view/edit/admin`，无五角色 | ❌ 待落 |
| 2 | 启动建默认组织 + `/{org}/admins` 子组 + admin 入组 | `DefaultOrg` 读时自举（DB）；组侧 = 平级 `/sdp-admin`（realm JSON）+ 组绑定已种 | ⚠️ 形态有、模型不同（D1 修订后须转换） |
| 3 | `POST /api/v1/users?org=&group=`（Groups 路径一次写入） | `/keycloak/users`（无 org/group 语义） | ❌ 待落（底层 `CreateUser` 已有） |
| 4 | 组 CRUD + 成员管理 + 管理员组保护 | `CreateGroup`/`Add/RemoveGroupMember`/`ListGroupMembers` 原子能力全有；无子组概念、无保护规则 | ⚠️ 原子有、编排缺 |
| 5 | 组织事务性三件套 + quotas + org_manager | `Org` = Name+Slug；创建 best-effort（组失败不回滚） | ❌ 待落 |
| 6 | 双路由 + 守卫 | `/admin/*` 五页有（无角色守卫）；`/org/dashboard` 无 | ❌ 待落 |
| 7 | L1 → 菜单可见 | 无（前端无角色驱动渲染） | ❌ 待落 |
| 8 | L2 attributes 通路 | 无（无 mapper、无 org_admin 概念） | ❌ 待落 |
| 9 | K8s RBAC 下发 | 无 | ❌ 全新 |
| 10 | 五集群角色 + verbs 映射 | 无 | ❌ 全新 |
| 11 | kubeconfig 签发（CSR 通道） | 无（credentials 只有 parse-kubeconfig 解析导入） | ❌ 全新 |
| 12 | 证书吊销（换 subject） | 无 | ❌ 全新 |
| 13 | 删除级联清绑定 + session | `BindingReaper` 只回收过期；删除路径无级联 | ❌ 待落（既有模型同欠） |

## 13. 落地顺序与门禁

| # | 步骤 | 门禁 |
| --- | --- | --- |
| 1 | realm：五 role + 层级组模型 + `org_admin` attributes mapper | `helm template` 渲染解析 realm JSON；password grant 解码断言 `roles`（五角色）与 `groups`（`/{org}` 层级） |
| 2 | hub：组织模型扩展（quotas/org_manager/事务三件套）+ 存量 `/org:<slug>` → `/{org}` 迁移 | 事务回滚单测（KC 失败注入）；迁移脚本幂等 |
| 3 | hub：用户/组 CRUD 新端点 + 删除级联（绑定 + session） | go build/vet/test；级联单测 |
| 4 | hub：`/api/userinfo` 扩展 `orgAdmins` | 契约冒烟 |
| 5 | console：双路由 + 菜单守卫（数据源 userinfo） | pnpm build + smoke |
| 6 | K8s RBAC 层：五角色模板 + CRB 下发 + kubeconfig 签发（CSR）+ 吊销（换 subject） | kind 集群 E2E：签发 → kubectl 通 → 吊销 → kubectl 拒 |

## 14. 相关文档

| 文档 | 关系 |
| --- | --- |
| [shared/AUTH-ARCHITECTURE.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/AUTH-ARCHITECTURE.md) | 下游地基：认证会话（BFF） |
| [shared/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md) | 下游地基：hub API 鉴权（安全层） |
| [shared/KEYCLOAK.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/KEYCLOAK.md) | realm 预置落地图纸 |
| [shared/CERTIFICATES.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/CERTIFICATES.md) | 平台自身 TLS（与本文档的用户集群 kubeconfig 证书分属两域） |

## 15. 变更历史

| 日期 | 决策 | 内容 |
| --- | --- | --- |
| 2026-11-03 | **初版（用户设计裁定）** | 用户提出 12 点访问控制设计（双层角色 + 组织模型 + K8s RBAC 授权层），对照既有代码（hub org/permission/keycloak 包、realm 配置、console 路由）后落地本 SSOT。三项架构裁定：**A** 组载体从 `/org:<slug>` 平级保留前缀修订为 `/{org}/{group}` 层级（修订 ACCOUNT-PERMISSION-MODEL D1，组织组可作绑定主体）；**B** L1 realm role 仅喂前端可见性，hub 鉴权不消费（D2 维持，conformance 门禁不变）；**C** K8s RBAC 下发通道复用 environment kubeconfig 凭据，kubeconfig 签发走目标集群 CSR API（hub 不持目标集群 CA）。三坑写入 §10。 |
