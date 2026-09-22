# 账号与权限：D1–D6 决策请求（Decision Request · **双向钢人版**）

> **本文件的地位 = 决策请求（非规范、非现状快照）。**
> 规范是 [hub/ACCOUNT-PERMISSION-MODEL.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/ACCOUNT-PERMISSION-MODEL.md)（§12 是待拍板清单），本文只做**一件事**：把那 6 个问题摊成可比较的选项，附**双向钢人论证 + 上游事实复核 + 推荐 + 连锁改动 + 不可逆性**。
> 拍板结论一旦确定，**应回写进 ACCOUNT-PERMISSION-MODEL.md §12**（把「备选」换成「已定」），本文随即可归档。

**体例（沿用本仓既有惯例）**：每项五段 —— **事实**（source-grounded，带代码锚点或上游出处与置信度）→ **钢人**（支持推荐选项的最强论证）→ **假钢人**（支持另一选项的最强论证，**不得稻草人**）→ **分歧 + 关键变量** → **判定**。与 `hub/DELETE-CONTRACT.md` §6.6、`console/CONSOLE-UI-DESIGN.md` 附 B 同体例。

**「以文档为准」的判定规则**（本轮全篇依此执行）：

| 级 | 情形 | 处置 |
| --- | --- | --- |
| **A** | 规范文档**已明确** | 照办，本文只标注「依 §x」，**不重新论证** |
| **B** | 规范文档**沉默** | 本文补裁，并**回写**规范（§12 等） |
| **C** | 规范文档**与事实冲突** | **改文档**（清单见 §7）—— 但先判「事实」是否可靠：**单一弱来源不予改文档**，降级为「需实测」标记 |

> **v2 修订说明（2026-09-22）**：v1 只列了备选与推荐，没有钢人论证。本版为每项补足双向钢人，并**逐条复核上游事实**。复核结果**推翻了 v1 的三处结论**（D1 的理由与不可逆性分级、D5 的否决理由、D3 的处数），并发现文档 **14 项缺陷**（§7：**10 项由本轮复核引发 + 4 项顺带修复的既有陈旧**）。凡推翻处均保留原文并说明推翻理由，不做静默改写。
>
> **v3 修订说明（2026-09-22，第二轮）**：回答「钢人已经做了，为什么还要人拍板」——**钢人产出论点，不产出偏好**；按「以文档为准」重分类六项后，**没有任何一项同时满足「文档沉默 + 不可逆」** ⇒ **0 项阻塞**（§0.1）。据此 **D1 默认由 ① 翻为 ②**（§1），**§8 步骤 1–2 随默认改写**。v1 / v2 原文全部保留。

---

## 0. 一页总览

| # | 问题 | **钢人后的推荐** | 一句话理由 | 与 v1 的差异 | 不可逆性 |
| --- | --- | --- | --- | --- | --- |
| **D1** | 「组织」用什么载体？ | **② 组命名约定 `/org:<slug>`**（**自决、可逆**） | 复用**已就绪**的 `groups` 通路（mapper 已挂、`auth.go` 已读），零 realm 开关 ⇒ 无 identity-first 登录流变化；且**组随 realm JSON 可靠导入** ⇒ 真拿到「配置即代码」（这正是 v1 误记给 ① 的那条）；隔离由保留前缀 + 硬规则保障 | **推荐翻转（v3）**：v2 推荐 ①（理由「语义隔离」）—— ② 用**保留前缀**同样隔离，且省掉 ① 的两项成本（开开关改登录流、组织集导入未证实） | **中**（v1 记「高」，**降级**，见 §9） |
| **D2** | 角色/权限的权威在哪？ | **① 全在 hub RBAC 表** | 不动式②；且「两段式鉴权」的 **a 段吃 token（组织）、b 段吃 hub 表（角色）** 是三条不动式的唯一自洽解释 | 同 | 低 |
| **D3** | 「不存用户表」的连锁改动 | **实为 5 处（v1 与规范都记 4 处，漏了最大的一处）**；第 4 处取 **(b) 只列已绑定主体 + 允许手输 subject** | 删 `users` 表是全仓主体语义改造 | **处数修正**：规范 §12 D3「4 处」漏掉 `users` 表 + `UserContext` 每请求 provision + `CurrentUserID` 签名（全仓 7 个读取点） | **中高**（删表不可逆；`owner_sub` 回填须显式置空 + 告警） |
| **D4** | Casbin 是否本期引入 | **延后 + 登记触发条件**（新登记 backlog B-19） | 边界内需求**今天一条都没有**；引入即同时引入策略存储 / 热更新 / 一致性三件事 | 同（增加「登记已落实」） | 低 |
| **D5** | token 存法 | **维持 localStorage** | **但 v1 的否决理由错了**：BFF 并不必然让 hub 持会话（BFF 可以是独立薄组件）；真正理由是「本期无 XSS 威胁模型，且 BFF = 新部署面/新故障域」 | **理由换** | 低 |
| **D6** | `aud` 校验方式 | **① 维持现状（不校 `aud`、校 `azp`）** | 单资源服务器；且本 realm 确有第二个 client（`sdp-backend`），`azp` 校验**不是理论问题** | 同（补实测依据） | 低 |

### 0.1 为什么「钢人论证」仍不等于「拍板」——以及为什么这次其实不用拍

**钢人论证产出的是**：最强论点（两侧）、**真正的分歧**、以及**决定分歧走向的关键变量**。它把**事实与逻辑**做到最强。
**但决策 = 论点 + 偏好/风险胃口**：「关键变量」本身是事实，**你怎么给这些变量加权**是价值判断，**不在文档里**。所以纯逻辑上，钢人做完仍可能剩一个偏好问题。

**然而**——按本轮的判定规则（「以文档为准」，§判定规则 A/B/C），**只有同时满足「文档沉默」且「不可逆」的项才真需要人**。据此重分类，六项**没有一项符合**：

| 类别 | 项 | 依据 |
| --- | --- | --- |
| **A 文档已定（照办，无需拍板）** | **D2 / D3 / D4 / D6** | **D2** = 不动式②「hub 是唯一权限权威」+ §2.1/§2.2 已成正文；**D3** = §5.3 **已写死**主体键（`user`→`sub`），第 4 处的唯一替代「全列用户」被 **§2.4.4 零外呼**排除 ⇒ **无选择空间**；**D4** = `hub/DATA-MODEL.md` §7.6「不在本期」+ B-19 已登记；**D6** = §2.4 已实现，且备选 ② 本属**条件触发** |
| **B 可逆 ⇒ 自决** | **D1 / D5** | **D1** 因 §1.5 硬约定（组织键=alias、组织不作主体）⇒ **换载体无需数据迁移**；**D5** = 前端单点、文档本就沉默 |
| **C 真需要人** | **（空）** | 唯一文档给不了的输入是 **D1 的路线偏好**（近期是否有「多 IdP / 跨组织 SSO 联邦」）—— 但它**不阻塞**：已按可逆默认 **②** 落地，若你有联邦需求再切 ①（因硬约定**零迁移**） |

⇒ **本轮之前「必须拍板」的措辞（本文 §0 旧文、规范 §12 标题、§11 步骤 1）均不再成立**，已全部回写为「决策状态（0 项阻塞）」。
⇒ **不再有拍板请求**；只剩一条**信息请求（不阻塞）**：*若你近期规划里有跨组织 SSO 联邦，请告知，我把 D1 切回 ①*。

---

## 1. D1 — 「组织」用什么载体？

### 1.1 事实

**代码事实（本仓，2026-09-22 核对）**

| # | 事实 | 锚点 |
| --- | --- | --- |
| F1 | realm JSON **没有** `organizationsEnabled`；`sdp-console` 的 `defaultClientScopes` = `web-origins/acr/profile/roles/email`，**没有** `organization` ⇒ 组织维度**完全没接线** | `build/hub/charts/software-distribution-platform-hub/templates/keycloak-realm-configmap.yaml` |
| F2 | `sdp-console` **已挂** `groups` mapper 且 `full.path=true`，但 realm 内**无任何组** ⇒ `groups` claim 为空（§10 #6「通路装了没数据」） | 同上（`protocolMappers` 段） |
| F3 | 部署版本 **Keycloak 26.7.4**（chart `keycloakx` 7.3.2）⇒ **26.6+ 的 Organization Groups 可用** | `hub/KEYCLOAK.md` §1 |
| F4 | hub 的 `keycloakClaims` **无** organization 字段 | `internal/middleware/auth.go:29-41` |
| F5 | console 请求的 scope **写死**为 `openid profile email` | `console/src/stores/auth.ts`（`UserManager({ scope })`） |

**上游事实（2026-09-22 复核，附置信度）**

| # | 事实 | 来源 | 置信度 |
| --- | --- | --- | --- |
| U1 | `organization` 是**内置的可选 client scope**，其 mapper 即 Organization Membership mapper | 官方 server_admin「Mapping organization claims」 | **高** |
| U2 | 请求形态有**三种且语义不同**：`organization` = ANY（单一归属直接授予；**多归属时提示用户选择**）；`organization:<alias>` = SPECIFIC；`organization:*` = ALL（用户全部归属） | 官方 `OrganizationScope` javadoc（ANY/SPECIFIC/ALL）+ 官方文档 | **高** |
| U3 | **Organization Groups 于 26.6.0 引入**；其组路径以富 JSON 形式出现在 `organization` claim 内（`{"organization":{"acme":{"id":…,"groups":["/Engineering/Backend"]}}}`）；启用 id / attributes 也会让 claim 变富 JSON | 官方 2026-04 博文 `org-groups` + protocol-mappers 参考 | **高** |
| U4 | **启用 Organizations 会把浏览器登录流改为 identity-first**（先识别用户再要凭据） | 官方 Keycloak 26 发布公告 | **高** |
| U5 | `RealmRepresentation` **同时**有 `organizationsEnabled`（Boolean）与 `organizations`（`List<OrganizationRepresentation>`） | 官方 Admin API javadoc（latest） | **高（字段存在）** |
| U6 | 但社区证据（26.3.1）称 **realm JSON 导入不带 organizations**，「官方推荐用 Admin REST API 在 realm 创建后再建组织」；且 Keycloak **不会自动修改既有 realm 的配置**（新增 client scope / 改登录流需手工或 API） | StackOverflow 26.3.1 + 中文迁移分析 | **中** ⇒ 只能记为「**需在 26.7.4 实测**」，不足以据此改文档（依 §判定规则 C 的保留条款） |

> **U5 与 U6 的冲突是本节的关键**：API 层面字段存在 ≠ 导入路径真的会消费它。v1 直接写了「两者都能进 realm JSON 受 git 管理」——**这是未经证实的断言**，本轮降级为「需实测」。

### 1.2 钢人（支持 ① Keycloak Organizations）

1. **两个维度不该共用一个 claim。** 「组织」（资源归属，§3 判定式吃它）与「组」（授权主体，§5.3 吃它）在规范里是两件事。② 让它们挤在 `groups` 里，等于规定「组名带 `/org:` 前缀的是组织、否则是授权组」——一层**自造 DSL**，写进 hub 代码后**没有 schema 可校验**，写错前缀**静默失效**（正是 §5.3 警告的那类 bug）。
2. **原生语义在 schema 里，可被独立审阅。** 组织在 Keycloak 控制台是一个**一等实体**（有 alias / domain / IdP 绑定 / 成员邀请），运维不必知道 hub 的前缀约定；换载体时是 Keycloak 里的一次操作，不是「重命名一堆组」。
3. **未来扩展不需要重做。** 组织级 IdP / 域路由（按 email 域名自动路由到组织 IdP）是 B2B 场景的常见诉求，① 直接具备；② 要另造一套。
4. **同维度的 Organization Groups（26.6+，本环境 26.7.4 已具备）** 提供了「每个组织独立的组层级」，天然避免多租户组名碰撞——这是 ② 必须靠 `/org:<slug>/<组>` 路径约定硬模拟的东西。
5. **规范文档的取向**：§2.3 把 Organizations 作为「组织维度的载体」**先列**，把另一条称为「**组命名约定**」（= 约定，不是机制）；§11 步骤 2 的正题也是「开 Organizations」。

### 1.3 假钢人（支持 ② 组命名约定，最强版，非稻草人）

1. **② 的配置是「已经验过的那一半」。** `groups` mapper 已在 `sdp-console` 上且 `full.path=true`，users 的 `groups[]` 与 realm `groups` 段**本来就在本仓的 realm JSON 里**（F2），`--import-realm` 路径**已在跑**。选 ② 意味着**不引入任何未验证的上游行为**；选 ① 意味着把「组织维度的接线」押在 U6 那个「需实测」上——**一次性风险集中在最不可回退的那个维度上**。
2. **claim 形态稳定。** ② 的 `groups` 永远是 `string[]`；① 的 `organization` claim **可能是** `string[]`，**也可能是**富 JSON（U3：开 id / attributes / Organization Groups 任一即变）。Go 侧要写「能解两种形态」的解析，而一旦选了 Organization Groups，序列化结果就与「纯别名数组」**不是同一种东西**——这会给 §3 归属判定式埋一个「看起来一样、其实不同」的坑。
3. **③ 不改变登录流，① 会。** U4：启用 Organizations 会把浏览器登录流切成 identity-first。这是**用户可见的行为变化**，会影响 console 登录 UX、会影响已预置账号的登录路径，还会与 nginx-ingress 的最长前缀路由（KEYCLOAK.md 坑 4 那个已经踩过一次的坑）叠加出新的排查面。② 对登录流**零影响**。
4. **② 顺带解决 §5.3 的多租户组问题，且不用 26.6+ 的新特性。** `full.path=true` 下 `/org:acme/devs` 一条路径同时表达「归属 acme」与「acme 内的 devs 组」——组织与组**天然嵌套**。用 ① 反而要额外启用 Organization Groups 才能达到同样效果，而那会把 claim 推向富 JSON（见第 2 条）。
5. **组织目录仍在 git 里（② 的确定性优势）。** 不论 U6 实测结果如何，② 的组织集合**必然**可由 `helm template` 渲染产物完整校验（realm `groups` + `users[].groups` 都是既有字段）；① 的组织集合能否被同一道 gate 覆盖**取决于实测**。

### 1.4 分歧 + 关键变量

**真正的分歧**：「组织」是**身份域概念**（Keycloak 侧一等实体：有 IdP、有域、有邀请，可以独立演化）还是**平台侧的归属标签**（hub 表里的一个字符串字段，随资源绑定一起存）？

**关键变量**：
1. **近期是否会出现「组织级 IdP / 按域路由登录」诉求？** 出现 ⇒ ① 的胜势迅速拉大；不出现 ⇒ ② 的「零新机制」优势就足够。
2. **组织集合能否随 realm JSON 一起导入（U6 实测）？** 能 ⇒ ① 的成本与 ② 持平，① 明显胜；不能 ⇒ ① 的组织集必须**命令式**供给（Admin API / 控制台手工），破坏「配置即代码」，② 胜。

### 1.5 判定（推荐 ①，但**理由已换**，并给出压降不可逆性的硬约定）

**依 §判定规则 A/B**：规范 §2.3 已把 Organizations 列为组织载体、§11 步骤 2 的正题就是「开 Organizations」⇒ 按「以文档为准」，**维持 ①**。

**但必须同时修正 v1 的两条错误理由**（这两条是 v1 推荐的全部依据，复核后都不成立）：

| v1 的说法 | 复核结果 | 修正后 |
| --- | --- | --- |
| 「两者都能进 realm JSON 受 git 管理」（指 ① 的组织实体也能） | **未证实**：字段存在（U5）但导入行为有反证（U6） | 改为「**需在 26.7.4 实测**」；实测为否定时，① 的组织集须另行供给（Admin API 脚本 / 控制台），**gate 随之改写** |
| 「原生能力没有理由放弃」（暗示零成本） | 有成本：U4 登录流变化 + U2 请求形态是**带语义的选择** + U3 claim 形态可能变富 JSON | 三条成本**写进落地清单**（§7 对应修正），不再以「零成本」立论 |

**v3 翻转：默认取 ②，① 降为条件触发位。** 理由（全部 source-grounded）：

1. **`groups` 通路已就绪、`organization` 通路没有**：`sdp-console` 已挂 groups mapper 且 `full.path=true`（`hub/ACCOUNT-PERMISSION-MODEL.md` §5.3），`auth.go` **已读** `groups`（§2.1）；而 realm **未开** Organizations、任何 client **未挂** `organization` scope（§10 第 2 行）。
2. **② 保住「配置即代码」，① 没有**：**组**是 realm JSON 的可靠组成部分（长期官方能力）；而**组织集能否随 realm JSON 导入恰是 ① 的「未证实」项**（§2.3、§10 置信度表）。⇒ v1 误记给 ① 的那条优势，**② 才是真拿到**。
3. **零 realm 开关 ⇒ 无 identity-first 登录流变化**（① 的用户可见成本，§2.3）。
4. **① 的「语义隔离」优势 ② 可等价取得**：`/org:` 作**保留前缀**，并立硬规则——**该前缀的组不得作为 `subject_type=group` 的绑定主体**（`BindingService` 校验 + 单测），即可守住「组织不作 RBAC 主体」。

**切换判据（写死）**：出现「**多 IdP / 跨组织 SSO 联邦**」需求 ⇒ 切 ①；因 §1.5 硬约定，**无需数据迁移**（只改中间件解析 + 开一个 realm 开关）。

**压降不可逆性的硬约定（本条是本轮最有价值的结论）**：

> **不论选 ① 还是 ②，持久化在 hub 里的组织键一律取「组织 alias（slug）字符串」，且 `slug == alias`；组织身份不参与 RBAC 主体（组织不得出现在 `subject_id`）。**

由此：

- `resource_ownership.owner_org` / `allowed_orgs`、`component_role_bindings.org_id` 的**派生值**，写的都是 alias 字符串 —— **与载体无关**；
- 两个载体都能产出 alias（① 的 `organization` claim 默认就是 alias；② 的 `/org:<alias>` 剥前缀即得）⇒ **换载体只改中间件解析，不改任何存量数据**；
- 只有「组织被当作 RBAC 主体行」的那部分绑定需要改写 —— 而上一条硬约定**从源头禁止**了这种行。

⇒ **D1 的不可逆性由「高」降为「中」**（v1 记「高（绑定表与 realm 一起迁）」）。此项**修正 v1 §9 分级**。

### 1.6 文档核对（→ §7 的修正项）

| 规范文档原文 | 问题 | 处置 |
| --- | --- | --- |
| §2.3「**必须请求 `organization:*` scope**（只请求 `organization` 不含该 claim）」 | **错**。`organization:*` 的语义是 **ALL（全部归属）**，不是「唯一能拿到 claim 的形态」；`organization` 是内置**可选** scope，请求它即生效（单归属直接授予、多归属提示选择） | **改**（列为三形态 + 语义，并把「选哪种」标为落地决策） |
| §2.3「需在 realm 上**显式开启** Organizations（realm settings 开关）」 | 对但**不完整**：既有 realm 不会自动补 client scope / 改登录流 | **补** |
| §2.3「默认形态是字符串数组；开启 id/attributes 后为富 JSON」 | **漏了 Organization Groups 也会推成富 JSON**（26.6+，本环境可用）⇒ 影响 Go 侧类型 | **补** |
| §2.3 未提**启用会改浏览器登录流（identity-first）** | 缺一条**用户可见**的成本 | **补** |
| §11 步骤 2 门禁 = 「`helm template` 渲染产物解析 realm JSON 通过」 | 若 U6 为否定，组织集**不在** realm JSON 里 ⇒ 该 gate 会给**虚假保证** | **改**（gate 拆成两条，见 §8） |

---

## 2. D2 — 角色/权限的权威在哪？

### 2.1 事实

| # | 事实 | 锚点 |
| --- | --- | --- |
| F1 | `auth.go` **刻意不读** `realm_access` / `resource_access`，`keycloakClaims` 里**没有** roles 字段 | `internal/middleware/auth.go:24-41` |
| F2 | **但本 realm 的角色并不在 `realm_access`，而在顶层 `roles` claim**（`oidc-usermodel-realm-role-mapper`，`claim.name: "roles"`，挂在 client 上） | realm-configmap `protocolMappers` |
| F3 | 平台级 `platform_role_bindings` **无 HTTP 端点、无 UI、零种子**（C-10） | §10 #15；`hub/STORY-BACKLOG.md` C-10 |
| F4 | 判定现状：`BindingService` 只做简单 `resource:action` 有/无（无有效期，列都没加） | `internal/permission/service/binding.go` |
| F5 | 规范**内部冲突**：§2.1 把「角色」写成「**RBAC 决策的输入之一（§5）**」，§2.2 / §10 #1 / §10 #3 又写「不读、不作结论」 | §2.1 vs §2.2 |
| F6 | 规范 §10 #3 的结论栏写的是「**✅ 已裁定（待 D2 拍板）**」——同一格内既称已裁定又称待拍板 | §10 #3 |

### 2.2 钢人（支持 ① 全在 hub RBAC 表）

1. **三条不动式的唯一自洽解释**：本模型的鉴权是**两段式**（§4）——**a 段吃 token**（组织 → 资源归属）、**b 段吃 hub 表**（角色 → 接口）。若角色也来自 token，b 段就退化成「把 token 里的字符串映射成 actions」，hub 不再是**权威**，只是**翻译器**。
2. **不动式②与 §2.2 的措辞是结论性的**：「token 里的角色是**输入**，不是结论」「不因 token 里有角色就放行」；§0 推论更直接把「Keycloak 里给了角色 ⇒ 权限生效」判为**无效假设**。
3. **审计可解释性**：§6 要求审计回答「谁 · 对什么 · 做了什么」。若角色有两个事实源，回答「为什么他能点这个按钮」需要同时查 hub 绑定表与 Keycloak realm 角色 —— 事故复盘时无法在一个查询里闭合。
4. **审批流的产物天然是 hub 行**：§7 的审批通过动作是「写一条绑定（带 `expires_at`）」。① 之下这条链路是**单一写入口**；② / ③ 之下审批写入的绑定还要和 token 角色做合并，且**合并规则本身需要再定义**（哪个优先？过期怎么算？）。
5. **代码方向已经一致**（F1），且将来 Casbin（§5.2）只可能加在 b 段。

### 2.3 假钢人（支持 ③ token 角色为准 / ② 混合，最强版）

1. **① 在当前状态下会让平台级权限**对所有人**为空**。F3：`platform_role_bindings` 连写入口都没有、零种子。而 realm 侧 `view/edit/admin` 角色**今天就在**、预置账号 `admin` **今天就被授予了 `admin`**。也就是说：③ 是**零迁移立刻可用**，① 是**先做 C-10 再灌种子**才能让管理员有权限。**在 C-10 完成之前，① 的落地状态与「权限系统没上线」无法区分。**
2. **Keycloak 是 IdP，「角色」本来就是它的原生词汇。** realm 角色是**跨系统**的（第二个接入方也懂），hub 表是私有格式，离开本平台即无意义；将来接第二个系统时要重新映射一遍。
3. **不动式②说的是「判定权」在 hub，不是「数据来源」必须自持。** hub 完全可以是「读 token 角色 → 用 hub 的**映射表**决定这些角色能做什么」——判定仍在 hub，仍然满足「hub 是唯一权限权威」。③ 并不像 §2.2 暗示的那样等于「把授权交给 Keycloak」。
4. **§2.1 的表格本来就写了角色是 §5 的输入之一**（F5）。按「以文档为准」，这一句**支持** ②（hub 表为主体、token 角色参与），而不是 ①。
5. **运维一致性**：用户离职/换岗时，运维在 Keycloak 里删角色是**已知的既有流程**；① 之下这一步**不会**改变 hub 权限，需要额外记得去 hub 页面解绑 —— 多一个人为遗忘面。

### 2.4 分歧 + 关键变量

**真正的分歧**：**「谁能给自己/别人加权限」这件事的边界画在哪？**

- ③/② 之下：**能改 Keycloak realm 角色的人 = 能提权的人**（`manage-realm` / Realm Admin）。
- ① 之下：提权必须经过 hub 的写入口（最终是 §7 的审批流 + §6 的审计）。

**关键变量**：**将来是否要求「提权必须留痕于 hub 的 audit_log，且必须能被 §7 审批流前置约束」？**

- 要求 ⇒ ①（否则提权旁路了本模块存在的全部理由）；
- 不要求、且认为「Keycloak 管理员本来就是高权角色，不需要 hub 再管一次」 ⇒ ③ 更省。

### 2.5 判定（推荐 ①，并接受假钢人第 1 条的代价）

**依规范 §2.2 / §10 #1 与不动式②** ⇒ **① 全在 hub RBAC 表**（与 v1 一致）。

理由：本模块的**存在理由**就是「鉴权决策可审计、提权可约束」；把角色权威留在 Keycloak 会让提权**绕过** §6 审计与 §7 审批流。假钢人第 3 条的区分（判定权 vs 数据来源）在**抽象层面**成立，但落到本项目即失效——因为 §7 的审批产物、§5.1① 的角色定义、`actions[]` 枚举**都已经在 hub 表里**，掺入 token 角色等于**在已有单一来源上人为再造一个**。

**必须接受的代价与补偿（这是 v1 漏掉的）**：

- 假钢人第 1 条成立：**C-10（平台级 RBAC HTTP 端点）成为 D2① 的前置**。⇒ 落地顺序上，C-10 与「§11 步骤 3 表结构」**必须同批**，且**种下至少一条平台管理员绑定**（`admin` 的 `sub` → `platform-admin`）。否则会出现「鉴权已开、人是管理员、但没有任何主体有平台级权限」的荒谬状态。
- 假钢人第 5 条（离职换岗）用**运维文档**补偿：KEYCLOAK.md §7「账号如何修改」补一条「删除 Keycloak 用户**不会**回收 hub 的绑定，须同步在 hub 侧解绑」。（登记为落地项）

**文档修正（→ §7）**：F5（§2.1 与 §2.2 冲突）、F6（§10 #3 自相矛盾）、并**点明本 realm 的角色 claim 名是 `roles` 而非 `realm_access`**（否则审计者按「realm_access」去 grep 会一无所获，误判为「角色根本没进 token」）。

### 2.6 门禁

- §11 步骤 5 的「判定结果与旧实现**逐例对照**」保留；
- 新增**防回退静态断言**：`auth.go` 的 `keycloakClaims` **不得**出现 roles 字段（一旦被加回来，D2① 就被静默推翻）。

---

## 3. D3 — 「不存用户表」的连锁改动（**实为 5 处，最大的一处被漏了**）

### 3.1 事实（逐处读代码所得）

规范要求 hub **不存用户表**（§2.2），绑定主体直接用 token 的 `sub`（§5.3）。§12 D3 列了 **4 处**，逐处核对后**性质并不同质，且漏了第 5 处**：

| # | 位置 | 事实 | 锚点 | 性质 |
| --- | --- | --- | --- | --- |
| 1 | `components.owner_user` | `*uuid.UUID`，指向**本地 `users.id`** | `internal/component/models/component.go:25` | ❌ **真需改表** |
| 2 | `component_role_bindings.user_id` / `role_id` | `*uuid.UUID`，注释写明 **V1 legacy**；**同表已有** `subject_type` / `subject_id`（text） | `internal/permission/models/binding.go:28-31` | ⚠ **比文档描述更轻**：主体列已就位 ⇒ 停写 + 手写 SQL 删列 |
| 3 | `pipeline_approvals.approver` | 类型**已是 `string`** ✅；**但写入值是本地 `users.id`**：`approver = CurrentUserID(c).String()`（同型问题另有同文件的 `Operator`） | `internal/run/models/pipeline_approval.go:22`；`internal/run/handler/pipeline_run.go:305-310`、`:359` | ❌ **表不用改、写入点要改** |
| 4 | console 用户列表来源 | `GET /users` → **hub 本地 users 表**（设计文档附 D 的 Permission 行也登记了 `GET /users`） | `console/src/api/permission.ts:55,60`；`console/CONSOLE-UI-DESIGN.md` 附 D | ❓ **来源决策**（见 3.4） |
| 5 | **`users` 表本身 + `UserContext` + `CurrentUserID`** | `UserContext` **每个请求**调 `GetOrProvisionByKeycloakID(sub, …)` 落一行本地用户，把**本地 `users.id`** 塞进 context；`CurrentUserID(c) (uuid.UUID, bool)` 是**全仓 7 个读取点**（component handler ×1 / config handler ×2 / pipeline handler ×1 / run handler ×2 / rbac ×1） | `internal/middleware/user_context.go:46,61`；读取点见 grep 结果 | ❌ **最大的一块，也是全仓签名改造** |

> **与已改代码的关系**：§10 #14 的修复（B-18）**与 D3 正交** —— 修的是「路径 id 是哪种资源」，没动「主体是本地 id 还是 `sub`」。D3 落地后，`RequirePermission` 里的 `userID uuid.UUID` 会变成 `subject string`（范围可控：`middleware/rbac.go` + `BindingService.HasPermission` 签名）。

### 3.2 钢人（推荐 (b) 只列已绑定主体，第 4 处的选项）

1. **不引入新的凭据面**：hub 一旦持有 Keycloak Admin 凭据，这把凭据就是**新的高权资产**（§10 #19 目前记为 ✅「全仓无 Admin 调用」）；它要进 Secret、要轮换、要进审计范围。
2. **与「hub 是唯一权限权威」同构**：hub 只该展示**它自己有权解释的东西** —— 绑定表里的主体，就是 hub 能回答「这个人在这平台是什么角色」的全部集合；列不出的人，本来就该去 Keycloak 控制台看。
3. **展示页的失败模式更安全**：Admin API 不可用时（Keycloak 抖动、凭据过期）用户页会**整页失败**；绑定表离线时它会**退回旧结果**。展示页不该把 Keycloak 的可用性引入自身的关键路径。
4. **§10 #19 / §2.4.4 的现状是 ✅**，改动它需要**明确收益**；本处收益只是「一个展示页更全」。

### 3.3 假钢人（支持 (a) hub 新增 Admin API 客户端，最强版）

1. **推荐 (b) 会打断授权闭环 —— 这是最硬的反驳。** 删掉 `users` 表后，hub **再也说不出「系统里有哪些人」**。于是「给新同事授权」这件事：控制台里**选不到他**（他没有任何绑定 ⇒ 不在 (b) 的列表里）；而「先让他登录一次产生记录」这条路**也被删表堵死了**。⇒ **新主体无法被授权**，平台的用户入职流程断在授权这一步。
2. **Admin API 就是 Keycloak 官方给管理面准备的接口**（`view-users` / `query-users` 是**只读** scope）。把它一并禁掉属于**扩大解释**，而且可以只申请只读 scope，风险面远小于「不写密码」那类禁令所针对的场景。
3. **§2.4.4 的措辞本来就是「每个业务请求对 Keycloak 零外呼」**（原节标题就是这个）—— 用户列表是**管理面的一次性读**，不是每请求；把管理面也纳入同一禁令，是把一条性能/健壮性优化**升级成了架构禁令**。
4. **§2.4.1 已经预留了口子**：「服务间调用（client credentials，需 confidential client）是**另一条路径**」；realm 里**已经建好了** `sdp-backend`（confidential + service account）。

### 3.4 分歧 + 关键变量

**真正的分歧**：**「授权表单必须能列出『还没被授权过的人』吗？」**

- 必须 ⇒ (a)：要么 Admin API，要么承认需要一个「见过的主体」目录（那就是 users 表的变体，回到 §2.2 的矛盾）。
- 不必（可手输） ⇒ (b) 成立。

**关键变量**：**新用户的第一个绑定由谁录入、怎么录入？** 这是一个**UX + 流程**问题，不是数据模型问题。

### 3.5 判定

1. **主体语义**：一律用 token `sub`（规范 §5.3 已写死，属判定规则 A，照办）。第 1/3/5 处按此改。
2. **第 4 处取 (b′) = (b) + 允许手输 subject**：
   - 列表来源 = hub 绑定表去重（不引入 Admin API）；
   - 授权表单的「主体」字段从「下拉选人」改为「**下拉已绑定主体 + 手输 `sub`/用户名**（格式校验）」；
   - ⇒ 闭环不靠 Admin API 补，而靠**输入**补（假钢人第 1 条被化解，且不新增凭据面）。
3. **(a) 明确记为「本期不做」，并写触发条件**：出现「必须展示全量用户目录」的产品要求时重估；届时需同时接受「hub 持有一把 Keycloak 只读管理凭据」的安全面，**独立评审**。
4. **§2.4.4 的适用范围要写清**（业务请求 vs 管理面），消掉「扩大解释」的歧义（→ §7）。
5. **落地的 5 处清单**（按依赖顺序）：
   - 先加 `CurrentSubject(c) string`（新读取点），保留 `CurrentUserID` 直到 1/3 处改完；
   - 改写入点：`owner_user → owner_sub`、approver/operator → `sub`；
   - 再删 `users` 表 + `UserContext` 的 provision + `CurrentUserID`（迁移须手写 SQL，AutoMigrate 只加不删）；
   - console：`GET /users` 换成绑定表派生 + 手输；
   - 文档同步：附 D 的 Permission 行去掉 `GET /users`。

### 3.6 文档修正（→ §7）

| 原文 | 问题 | 处置 |
| --- | --- | --- |
| §12 D3「连锁改动 | **4 处**」 | **漏了最大的一处**（`users` 表 + `UserContext` 每请求 provision + `CurrentUserID` 签名，全仓 7 个读取点）；第 5 处恰好是「删表不可逆」的所在 | **改**为 5 处并把第 5 处前置 |
| §12 D3 第 3 处「`pipeline_approvals.approver`」（暗示要改表） | 类型**已合规**，问题在**写入值** | **改**为「表不改、写入点改」 |
| §2.4.4「不调用 Admin API」 | 未区分**业务请求**与**管理面**，被 §12 D3 第 4 处当成了一律禁令 | **补**适用范围 + 指向本节判定 |

---

## 4. D4 — Casbin 是否本期引入

### 4.1 事实

| # | 事实 | 锚点 |
| --- | --- | --- |
| F1 | 仓库**无 Casbin 依赖**（`go.mod` 无 casbin；`go-oidc v3.20.0`、`gorm v1.31.2` 在列） | `go.mod` |
| F2 | 仅有一句风格注释「Casbin-style `resource:action`」 | `internal/permission/models/role.go:19` |
| F3 | DATA-MODEL §7.6「开源参考映射」把 **OPA / Casbin** 列为「未来『仅工作时间可发布生产』等用策略引擎，**不在本期**」 | `hub/DATA-MODEL.md` §7.6 |
| F4 | 现状判定只有简单 `resource:action` 有/无 | `internal/permission/service/binding.go` |
| F5 | 规范 §5.2 已按策略类型划边界：简单 `resource:action` → 内置判定；**字段级 / 角色继承 / 临时条件策略** → Casbin | §5.2 |

### 4.2 钢人（引入）

1. **需求是可预见的**：生产环境强审批、审批超时、版本对比等主规格项（backlog B-11）都会落到「按环境/时间/字段判定」，正是 §5.2 划给 Casbin 的那一格。
2. **策略与代码分离**：改策略不必发版、不必停机，符合「配置即代码」的项目取向。
3. **模型天然贴合本项目的两层粒度**：Casbin 的 RBAC-with-domains（`dom`）正好表达「平台级 / 组件级 / org 域」三层主体，比 hub 现在手写的两层查询更贴近信息模型。
4. **§5.2 已把边界写进规范**（F5），引入不等于放开 —— 它被限定在「复杂策略」一格内。

### 4.3 假钢人（延后，最强版）

1. **边界内今天一条需求都没有**。引入即同时引入**三件新事**：策略存储（表还是文件？热更新怎么做？）、与 hub 表的一致性（绑定变了策略要不要重导出？）、以及**双事实源** —— 而后者正是不动式②反对的。
2. **可解释性下降**：§6 的审计要回答「为什么」。hub 表现在能直接指出「哪一行绑定授权了这个 action」；`enforce()` 只能给「允许/拒绝」，审计要另做一层解释。
3. **§5.2 的边界是「先划后等」，本身就隐含延期**：划边界的目的就是**不必现在决定**；提前引入等于为一个未发生的需求先付运维成本。
4. **YAGNI 的成本不对称**：延后是**零成本**（没有依赖、没有表、没有迁移）；引入后回退要拆表/拆依赖 + 把策略迁回代码。选项之间**成本不对称**时，默认取可逆的一侧。

### 4.4 分歧 + 关键变量

**真正的分歧**：是否存在**无法用 `(主体, 资源, 动作)` 三元组表达**的策略？

**关键变量**：第一条「凭资源字段/环境条件/时间」的策略**何时出现**。

### 4.5 判定（延后 + **把触发条件真正登记掉**）

**依规范 §5.2 的边界 + F3 的「不在本期」** ⇒ **延后**（与 v1 一致）。

但 v1 只写了「把需求点登记为 backlog」而**没有真的登记**（文档里的承诺未落实）⇒ 本轮**落实为 backlog B-19**：

- 编号：`B-19`（`hub/STORY-BACKLOG.md`）
- 内容：复杂策略引擎（Casbin / OPA）**需求点登记**
- 触发条件（写死，避免反复讨论）：出现第一条**无法用 `resource:action` 表达**的策略（典型：仅工作时间可发生产、金额/环境阈值以上需双人审批）时，**在那一期**引入
- 引入时的硬约束（写死）：Casbin **只做决策**；策略**由 hub 表导出**，**不得反向写** hub 表（保持不动式②）；不替代 §6 审计与 §7 审批流

### 4.6 文档修正（→ §7）

DATA-MODEL §7.6 的 OPA/Casbin 行补 B-19 指针（否则「需求点登记」在规范里仍然无迹可寻）。

---

## 5. D5 — token 存法

### 5.1 事实

| # | 事实 | 锚点 |
| --- | --- | --- |
| F1 | console 用 `oidc-client-ts` 的 `UserManager`，token 存 **`localStorage`**（`WebStorageStateStore`） | `console/src/stores/auth.ts` |
| F2 | 请求 scope = `openid profile email`；`automaticSilentRenew: true` | 同上 |
| F3 | console 目前**没有任何**基于 token 的角色判断（§8 红线当前**是干净的**，grep `roles` / `isAdmin` / `hasRole` 在 store 与 router 中**零命中**） | 同上 + `src/router/` |
| F4 | `accessTokenLifespan = 300`（5 分钟） | realm-configmap |
| F5 | §2.4.6 写死「**hub 无会话、无状态**；『登出』在 hub 侧不存在」 | §2.4.6 |
| F6 | 规范 §8 第 2 行的表述是「**登录跳转交给后端 / Keycloak**」 | §8 |

### 5.2 钢人（支持维持 localStorage）

1. **零改动 + 零新组件**：现状已在跑（F1），改法只有「不动」。
2. **与 §2.4.6 的无状态裁决同向**：任何需要 hub 参与会话的方案都要先推翻 §2.4.6。
3. **窃取窗口被压短**：5 分钟寿命（F4）+ silent renew；攻击者拿到的是**很快过期**的 token，而非长期凭据。
4. **console 当前不做任何 token 内容判断**（F3）⇒ token 对前端的用途**仅是「附在请求头里」**，把它换成更安全的存储**不改变**任何业务逻辑 —— 也就是说，这个决定**不会**因业务演进变得更贵。

### 5.3 假钢人（支持后端 Cookie / BFF，最强版）

1. **XSS 的暴露面是全量 token**：localStorage 里任何脚本可读（F1）。httpOnly Cookie 让 JS **完全拿不到** token —— 这是彻底的、不依赖寿命的防护。
2. **v1 的否决理由不成立（必须纠正）**：v1 写「Cookie/BFF 需要 hub 持会话，与 §2.4.6 直接冲突」。**这不必然**：BFF 可以是**独立薄组件**，只做「OIDC 回调换 token → 置于 httpOnly Cookie → 转发时注入 Authorization」，会话仍在 Keycloak 的 SSO session 里，**hub 依旧无状态**。§2.4.6 约束的是 **hub**，并没有禁止新增组件。
3. **部署面已经很接近**：本仓已用 nginx-ingress + 同域 `/keycloak`（KEYCLOAK.md §3），BFF 只需在同一 host 上加一条前缀路由，不需要新域名/新证书（复用 `console-ingress-tls`）。
4. **业界默认**：SPA 纯前端持 token 已是反模式；BFF 是当前主流推荐。

### 5.4 分歧 + 关键变量

**真正的分歧**：**「BFF 算不算一个新组件」的代价是否值得**？

- v1 的框架（「BFF ⇒ hub 有状态」）是**错的**，所以本项不再是「架构冲突」，而是**一个纯粹的取舍**：新组件（部署面 / 故障域 / 健康检查 / 会话与 Cookie 的 CSRF 面）↔ XSS 下的 token 保护强度。

**关键变量**：**是否存在真实 XSS 威胁模型**（会引入不可信第三方脚本 / 用户可控 HTML 渲染）？

### 5.5 判定（维持 localStorage，**但理由已换**）

**判定**：**维持 localStorage（本期）**，理由是：**本期无 XSS 威胁模型，且不引入新组件的收益不足以支付其部署与运维成本**。

**明确纠正 v1 的错误理由**（写给将来重估的人，避免被同一句错误论据误导）：

> BFF **并不**要求 hub 持会话；§2.4.6 只约束 hub。若将来重估，**不要**再用「与 §2.4.6 冲突」否决 BFF —— 应当评估的是「BFF 作为新组件的部署/故障/CSRF 成本」。

**零成本折中（列为此项的次选，随时可切）**：把 `WebStorageStateStore({store: localStorage})` 换成 **`sessionStorage`** —— 同样是 `oidc-client-ts` 内置能力，**一行改动**；效果是「关标签页即失效、跨标签页不共享」，把窃取面从「持久」压到「当前标签页生命周期」。

**触发条件**：引入不可信第三方脚本、或出现真实 XSS 事件 ⇒ 上 BFF（**不是**改 hub）。

### 5.6 文档修正（→ §7）

§8 第 2 行「登录跳转交给**后端 / Keycloak**」与 §2.4.1「**console** 是 OIDC Client（`sdp-console`，public + PKCE）」冲突：登录跳转是 **console 触发**的，不是后端。⇒ 改为「登录跳转交给 Keycloak（由 console 触发 OIDC 跳转）」。

---

## 6. D6 — `aud` 校验方式

### 6.1 事实

| # | 事实 | 锚点 |
| --- | --- | --- |
| F1 | `SkipClientIDCheck: true`，改校 `azp == KEYCLOAK_CLIENT_ID` | `internal/middleware/auth.go:69-76`、`:106-110` |
| F2 | `KEYCLOAK_CLIENT_ID` 默认 **`sdp-console`** | `internal/config/config.go:100` |
| F3 | 本 realm **有两个 client**：`sdp-console`（public + PKCE）、`sdp-backend`（confidential + **serviceAccountsEnabled**）⇒ **确实可能收到 `azp=sdp-backend` 的 token** | realm-configmap `clients[]` |
| F4 | `default-roles-sdp` 复合了 `account` client 的 `manage-account` / `view-profile` ⇒ Keycloak 默认 access token 的 `aud` 含 `account`（与本仓注释一致） | realm-configmap `roles.realm[]` |
| F5 | §2.4.3 第 6 条**已把它记为刻意的标准偏离**，并写明代价「无法按 audience 区分多个资源服务器」 | §2.4.3 |

### 6.2 钢人（① 维持现状）

1. **azp 校验在本 realm 是有效的实测行为，不是理论问题**：realm 里**已有第二个 client**（F3），服务账号 token 的 `azp` 是 `sdp-backend`，会被正确拒绝 —— 跨客户端重放**已经被挡住**。
2. **单资源服务器**：把 `aud` 校成 client id 只是把「同一件事」换个位置写；当前不存在第二个需要独立 audience 的 API。
3. **代价不对称**：② 要在 realm 上加 audience mapper（改 realm JSON + 影响所有 client），换来一个**当前无人消费**的能力；① 的代价（F5 已登记）只在「多 API」时兑现。
4. **§2.4.3 第 6 条已把偏离与代价写在同一处**（F5），改动它等于重开一条已裁定的标准偏离。

### 6.3 假钢人（② 加 audience mapper，最强版）

1. **语义位置不同**：`aud` 是「这个 token 给**谁**用」，`azp` 是「**谁**要的 token」。用 azp 代替 aud 校验，等于用「发起方」代替「受众」——**在语义上是一个近似，不是一个等价**。
2. **token 自描述性**：带正确 `aud` 的 token **离线可判**（任何资源服务器都无需额外配置就知道自己该不该收），这**更贴合** hub「零外呼、只看 token」的取向；azp 方案则把「我该收谁签发的 token」这个知识放在**每个服务自己的配置**里，配置漂移即静默失效。
3. **阈值很低**：`oidc-audience-mapper` 是内置 mapper，一段 JSON；相比它能消除的语义近似，成本几乎可忽略。
4. **F3 反过来也能支持本方向**：既然 realm 已经有第二个 client，说明「多客户端」不是假想 —— 那么「多个**资源服务器**」也只是时间问题。

### 6.4 分歧 + 关键变量

**真正的分歧**：**「资源服务器自己的身份」写在哪里** —— token 的 `aud`（自描述）还是 hub 的配置（`KEYCLOAK_CLIENT_ID`）？

**关键变量**：**是否会出现「同一 client 签发的 token 需要被 hub 以外的资源服务器接受」或「第二个前端复用 `sdp-console`」？**

### 6.5 判定（维持 ①，并补一条低成本加固）

**依 §2.4.3 第 6 条（判定规则 A：文档已明确）** ⇒ **① 维持现状**，不重开论证。

**触发条件**（写死）：出现第二个需要独立 audience 的资源服务器、或第二个复用 `sdp-console` 的前端时，执行 ②。

**可选加固（低成本，写入落地项）**：把 `azp` 校验失败**与其它 401 原因区分并留痕**（现在只回 401 不记录）。注意这**超出 §6 现状**（§6 只登记写操作 POST/PUT/PATCH/DELETE），因此需要**先在 §6 加一行**说明「认证失败的留痕**不在**审计中间件职责内、由访问日志承担」，或明确把它列为 §6 的扩展项后再做 —— 否则会出现「审计规范说只写写操作，实现却记了 401」的新漂移。

### 6.6 文档核对

本节**未发现文档与事实冲突**；F5 的存在使 §6.5 成为判定规则 A 的直接适用。**唯一需要补**的是 F3 的实测依据（原 §2.4.3 第 5 条说「多客户端 realm 下必校」，但没说清本 realm **就是**多客户端）：作为**增强**（非修正）写进 §7。

---

## 7. 第一轮修正清单（v2，共 **14 项** = 由复核引发的 10 项 + 顺带修复既有陈旧的 4 项）

> 依据 §判定规则的 C 级。每处均标注**原表述 → 问题 → 改法**，便于逐条复核。

| # | 文件 | 位置 | 原表述 | 问题 | 改法 |
| --- | --- | --- | --- | --- | --- |
| 1 | `hub/ACCOUNT-PERMISSION-MODEL.md` | §2.3 | 「**必须**请求 `organization:*` scope（只请求 `organization` 不含该 claim）」 | **事实错误**：`organization:*` = ALL（全部归属）；`organization` 是内置**可选** scope，本身即生效（单归属直接授予 / 多归属提示选择） | 改写为**三种形态 + 语义**，并把「选哪种」明确为**落地决策**（D1 §1.5） |
| 2 | 同上 | §2.3 | 未提**组织实体能否随 realm JSON 导入** | 缺一条决定「配置即代码 / gate 形态」的事实；v1 据此错误断言「可进 git」 | 增补：字段存在（`RealmRepresentation.organizationsEnabled` / `organizations`）但**导入可用性需实测**（含反证来源），并标 **需实测** |
| 3 | 同上 | §2.3 | 「开启 id/attributes 后为富 JSON」 | **不完整**：Organization Groups（26.6+，本环境 26.7.4 可用）**也会**推成富 JSON；直接影响 Go 侧类型设计 | 增补第三种致富 JSON 的条件 + 提示类型须兼容两形态 |
| 4 | 同上 | §2.3 | 未提**启用会改浏览器登录流** | 缺一条**用户可见成本**（identity-first） | 增补 |
| 5 | 同上 | §2.1 | 角色行「RBAC 决策的**输入之一**（§5）」 | 与 §2.2 / §10 #1 冲突（内部矛盾）；且掩盖了「a 段吃 token / b 段吃 hub 表」的分工 | 改为「**对账 / 展示**（D2① 推荐下不作判定输入）」，并点明两段式分工 |
| 6 | 同上 | §2.2 | bullet 标题「**不读 `realm_access` 就放行**」 | 措辞歧义（可读成「不读也放行」，与原意相反）；且本 realm 的角色 claim 名是 **`roles`** 而非 `realm_access` | 改写标题与正文，并点明**本 realm 实际 claim 名** |
| 7 | 同上 | §8 第 2 行 | 「登录跳转交给**后端** / Keycloak」 | 与 §2.4.1（**console** 是 OIDC Client）冲突 | 改为「由 **console** 触发 OIDC 跳转（console 即 OIDC Client）」 |
| 8 | 同上 | §10 #3 | 结论栏「**✅ 已裁定**（待 D2 拍板）」 | **自相矛盾**（同格既称已裁定又称待拍板）；会让对账表读者误判为已关闭 | 改为「⏳ 待 D2 拍板（钢人后推荐①）」 |
| 9 | 同上 | §2.4.4 / §11 / §12 | 「不调用 Admin API」被 §12 D3 第 4 处当成**一律禁令**；§11 步骤 2 的 gate 假定组织集在 realm JSON 里；§12 D3 记「4 处」 | 三处连锁失真：适用范围被扩大解释 / gate 可能给虚假保证 / **漏掉最大的一处改造** | §2.4.4 补**适用范围**（业务请求 vs 管理面）；§11 步骤 2 gate 拆两条（渲染 + **token 断言**）；§12 D3 改 **5 处**并把第 5 处前置 |
| 10 | `hub/KEYCLOAK.md` | §6 | 「⚠️ **已知缺口（开工前必读）**：…这 4 条路由对所有人返回 403…**本次未改**」 | **已过时**：§10 #14 已于 2026-09-22 修复（backlog B-18） | 改为「✅ 已修复（2026-09-22）」并保留 4 条路由清单 + 指向 B-18 |

**顺带修复的文档漂移（非本轮 D1–D6 引发，属既有陈旧）**：

| # | 文件 | 问题 | 改法 |
| --- | --- | --- | --- |
| 11 | `hub/STORY-BACKLOG.md` §4 | **C-01 / C-02 / C-12 三行仍记「⬜ 未做 / 🟡 部分」**，而 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §4/§5 已记 **2026-09-22 完成**（产物与门禁均在：`CommandPalette.vue` / `tokens.css` / `utils/{theme,search,pipeline}.ts` / 四个冒烟脚本全绿） | 三行改为「✅ 已完成（2026-09-22）」并补证据 |
| 12 | `hub/STORY-BACKLOG.md` §1/§3 + `hub/DATA-MODEL.md` §7.6 | D4 的「登记复杂策略需求点」在文档里**无落点**（规范提了要求，backlog 无对应行） | 新增 **B-19**（Casbin/OPA 需求点 + 触发条件 + 引入硬约束），并同步汇总数字与 §7.6 指针 |
| 13 | `plans/UNIMPLEMENTED-MODULES-PLAN.md` §6.5/§7.4 | 下一步仍写「等 D1–D6 拍板」，且措辞把 `organization:*` 当既定 | 改为「钢人已毕，推荐见 `ACCOUNT-PERMISSION-DECISIONS.md` §0」+ 去掉 `organization:*` 的既定语气 |
| 14 | `README.md` | 决策文档的章节描述（§1–§6 逐项备选…）已不匹配重写后的结构 | 更新目录树与索引行的描述 |

---

## 7.5 第二轮修正清单（v3，6 项）

> 起因 = 「钢人已做，为何仍需拍板」；处置 = 把「待拍板」收敛为「0 项阻塞」，并让 D1 默认与落地步骤自洽。

| # | 文件 | 位置 | 原表述 | 问题 | 改法 |
| --- | --- | --- | --- | --- | --- |
| 15 | `hub/ACCOUNT-PERMISSION-MODEL.md` | §12 标题 + 引言 + 表头 + 6 行 | 「**待拍板（阻塞项）**」「拍板后请把结论回写」「备选」 | 与本轮结论（**0 项阻塞**）冲突；且 D2/D3/D4/D6 的结论其实早已由正文裁定 | 标题改「**决策状态（0 项阻塞）**」；表头「影响/备选」改「**结论（生效）/备选·翻盘条件**」；逐行写出生效结论 |
| 16 | 同上 | §2.3 末 | 「是**必须先拍板**的前置」 | **已被本轮自己引入的硬约定推翻** —— 组织键取 alias + 组织不作主体 ⇒ carrier **不阻塞表结构** | 改为「**载体不阻塞任何落地项**」+ 默认 ② + 切换判据 + 保留前缀硬规则 |
| 17 | 同上 | §2.1 两行（组织 / 角色） | 「载体待定，见 §12」（组织）；「D2 推荐① 下不作判定输入」（角色） | 角色行仍把**已裁定**的事写成「推荐/待定」 | 组织行改「默认 `groups` 命名约定」；角色行改「**已定**」 |
| 18 | 同上 | §10 第 2 / 3 行 | #3 结论「⏳ 待 D2 拍板」；#2 落点泛指「realm CM」 | #3 实为**已定**；#2 的修法随默认 ② 变（预置组，非开 Organizations） | #3 改 ✅ 已定；#2 落点写明「默认 ② ⇒ 只需预置 `/org:<slug>` 组」 |
| 19 | 同上 | §11 步骤 1 / 2 | 步骤 1「**拍板** §12 的 D1–D6」，门禁「无 D1/D2 无法定稿」；步骤 2「**开 Organizations** → 选定 scope 形态 → 实测组织集导入」 | 步骤 1 前提不成立（**可定稿**）；步骤 2 与默认 ② 矛盾 | 步骤 1 改「**D1–D6 已闭**」；步骤 2 改「**默认 ②**：预置 `/org:<slug>` 组，无需开 Organizations」，门禁改「解码断言 `groups` claim 含 `/org:*`」 |
| 20 | `plans/UNIMPLEMENTED-MODULES-PLAN.md` / `README.md` | Epic C 标题与下一步、决策文档索引行 | 「**阻塞于 D1–D6 拍板**」「必须先拍板 D1–D6，再动代码」「等拍板」 | 与「0 项阻塞」冲突 | 全部改「**已闭（0 项阻塞）**，可直接开工」；README 索引行补「决策分级（0 项阻塞）」；并修掉 `按倉内既有体例` 的**繁体误字**（倉→仓） |

---

## 8. 开工第一步（修订 §11 步骤 1–4；原「拍板之后的第一步」）

| 步 | 动作 | 门禁（**已按 D1/D2 修订**） |
| --- | --- | --- |
| 1 | realm 侧按 **D1 默认 ②** 落地：预置组织组 `/org:<slug>`（groups mapper **已挂**，无需改动）→ **无需开 Organizations** | ① `helm template` 渲染产物解析 realm JSON 通过；② 按 `hub/KEYCLOAK.md` §4 第 5 步的 password-grant curl 取 token，**解码断言 `groups` claim 含 `/org:*`** |
| 2 | **仅当切 ① 时才需**：实测 U6（组织集能否随 realm JSON 导入） | 能 ⇒ 进 realm JSON；不能 ⇒ 命令式供给 + 可重跑检查（并在 §2.3 明记「配置即代码在该维度不成立」）。**默认 ② 下本步不阻塞** —— 组随 realm JSON 导入属可靠路径，仍以步骤 1② 的解码断言兜底 |
| 3 | 表结构：`expires_at` ×2、`resource_ownership`、角色↔接口映射表、`audit_log`、`permission_request`；**并同批做 C-10（平台级 RBAC 端点）** | migration 在空库 + 存量库双向可执行；C-10 端点可用（否则 D2① 落地后**无人是平台管理员**） |
| 4 | 中间件按 §4 重排 + **D3 的主体语义改造（5 处，`sub` 取代本地 user id）** + 种一条平台管理员绑定 | Go 单测 + build/vet/test；`owner_sub` 回填**映射不到的显式置空 + 告警** |

---

## 9. 不可逆性分级（修订）

| 级别 | 项 | 说明 | 与 v1 的差异 |
| --- | --- | --- | --- |
| **中高** | **D3 第 5 处**（删 `users` 表） | 删表不可逆；`owner_sub` 回填依赖「旧 `users.id → sub`」映射，映射不到的**必须显式置空 + 告警** | 同（v1 记为「高」，本版并入「中高」以与 D1 并列比较） |
| **中** | **D1** | **降级**：组织键统一取 alias（slug）字符串且组织不作 RBAC 主体 ⇒ 换载体**不需要数据迁移**，只改中间件解析；仅「org 形主体绑定」这类行需改写，而该形态已被硬约定禁止。默认取 ② 后**更缓**：`groups` 通路已就绪 ⇒ 即便翻盘到 ① 也只是加开一个开关 | **由「高」降为「中」**；v3 默认 ② |
| 低 | D2 / D4 / D5 / D6 | 都是「本期不引入」或「判定优先级 / 存储位置」，随时可调（D5 甚至有一行改动的折中位） | 同 |

---

## 10. 附：上游事实的来源与置信度（供复核）

| 事实 | 来源 | 置信度 | 需实测？ |
| --- | --- | --- | --- |
| `organization` 是内置**可选** client scope，mapper 为 Organization Membership | 官方 server_admin 文档「Mapping organization claims」 | 高 | 否 |
| 三种请求形态与语义（ANY / SPECIFIC / ALL） | 官方 `OrganizationScope` javadoc + 官方文档 | 高 | 否 |
| Organization Groups 于 **26.6.0** 引入；org 组路径进 `organization` claim 且为富 JSON | 官方博文 `org-groups`（2026-04） | 高 | 否 |
| 启用 Organizations ⇒ 浏览器登录流变 identity-first | 官方 Keycloak 26 发布公告 | 高 | 否 |
| `RealmRepresentation` 含 `organizationsEnabled` + `organizations` | 官方 Admin API javadoc | 高 | 否 |
| **realm JSON 导入是否真会落 organizations** | 社区问答（26.3.1，称**不会**）+ 第三方扩展自建 import 端点（旁证） | **中** | **是**（26.7.4） |
| 既有 realm 开启 Organizations 后是否自动补 scope / 改流 | 中文迁移分析（称**不会**，Keycloak 不自动改既有 realm 配置） | 中 | **是**（26.7.4） |
| Keycloak 默认 access token 的 `aud` 含 `account` | 本仓 `auth.go` 注释 + realm `default-roles-sdp` 复合 `account` 客户端角色 | 高（本 realm 内可解释） | 否 |

> **凡标「需实测」的，本文一律不据此改规范文档的**事实性**表述**，只作为**落地 gate** 写入 §8 —— 避免把「一个社区回答」升级成「规范」。
