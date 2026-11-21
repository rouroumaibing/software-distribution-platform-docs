# UI 下发逻辑验证用例点

> 关联：[console-ui-verification-testcases.md](console-ui-verification-testcases.md)（呈现层 38 例）、[GAP-CONSOLE-UI-VERIFICATION-2026-11-21.md](GAP-CONSOLE-UI-VERIFICATION-2026-11-21.md)（结构缺口）、[STATUS.md](STATUS.md)（进度权威）。
> 来源：`console/src/api/*.ts` + 全部视图的写操作入口、`hub` handler/service 落库路径、本地 kind PG 实地核对。
>
> **定位差异**：既有 38 例验证的是「给定响应，UI 呈现是否符合规范」；本文验证的是「用户在 UI 点下去，后端逻辑是否真的执行」。前者可能假绿（toast 出现但没落库），后者以**后端状态真实改变**为判据。

## 1. 判据模型（第一性）

一条 UI 操作是否"逻辑正常"，唯一可信的证据链：

```
UI 点击/提交 → 捕获 /api 请求(method+path+body 正确) → 后端状态真实改变(GET 或 PG 独立核对) → UI 正确反映
```

三段缺一不可：只看 toast/DOM 会假绿；只看 API 200 无法证明落库（broker-only 操作 200 但零写库）。

### 1.1 关键分层：同步落库 vs broker-only

| 层 | 含义 | 判据 | 涉及操作 |
|---|---|---|---|
| **S 同步落库** | 操作后 DB 立即变 | 操作前后查 GET/PG，断言字段改变 | 建删改 service/component/pipeline/stage/task/环境/配置/权限绑定/用户/组/PAT/订阅/变量组绑定/触发器/依赖、审批**记录** |
| **A 半异步** | 记录同步落，执行靠回流 | 同步部分查"新行+入队"，异步部分带超时查回流字段 | 触发运行（`pipeline_runs` 新行 + `dispatch_jobs` 入队；phase 推进靠回流）、审批决策（`pipeline_approvals.status` 同步；任务放行靠回流） |
| **B 纯 broker-only** | hub 零写库，只转发 | **不能**用 UI 反馈判"下发生效"；只能断言"请求已发出且 200"，执行结果标注为异步不可即时核对 | 灰度 pause/promote/rollback（`rollout_runs` 只由 runner 回流写） |

> 判据纪律：B 类操作若写"点击后步骤器变化=通过"就是假绿。本文只对 B 类断言"请求发送 + 无错误"，并把真实状态核对列为异步观察项。

## 2. 用例点清单（S 同步落库类，按功能域）

编号 `OP-xx`。每条含：UI 操作 / 捕获请求 / 后端核对点 / UI 反映。执行状态列由 STATUS 维护。

### 2.1 服务树与组件（OP-01~05）

| ID | UI 操作 | 请求 | 后端核对（GET / PG） | UI 反映 |
|---|---|---|---|---|
| OP-01 | 建组织 | `POST /orgs` {name,slug} | `GET /orgs` 含新 slug；`orgs`+`service_trees` 同步新增 | 树出现节点、自动切入 |
| OP-02 | 加服务 | `POST /services` {serviceTreeId,key,name} | `GET /orgs/:id/services` 含新 key | 服务节点出现 |
| OP-03 | 加组件 | `POST /components` {serviceId,key,name,repoUrl...} | `GET /services/:id/components` 含新 key | 组件节点出现 |
| OP-04 | 声明依赖 | `POST /components/:id/dependencies` {dependsOnId} | `GET /components/:id/dependencies` 含新边；`component_dependencies` 新增 | 上下游列表刷新 |
| OP-05 | 解除依赖 | `DELETE /components/:id/dependencies` | 同上目标边消失（硬删） | 列表刷新 |

### 2.2 流水线编排（OP-06~11）

| ID | UI 操作 | 请求 | 后端核对 | UI 反映 |
|---|---|---|---|---|
| OP-06 | 建流水线 | `POST /pipelines` {componentId,name,kind} | `GET /components/:id/pipelines` 含新名 | 跳编辑器 |
| OP-07 | 改名（确认保存） | `PUT /pipelines/:id` {name} | `pipelines.version` +1 且 `pipeline_versions` 新增快照 | 列表显示新名 |
| OP-08 | 建/删阶段 | `POST /pipelines/:id/stages`、`DELETE /stages/:id` | `GET /pipelines/:id/stages` 增减；软删 `deleted_at` | DAG 重刷 |
| OP-09 | 建/改/删子任务 | `POST /stages/:id/tasks`、`PUT /tasks/:id`、`DELETE /tasks/:id` | `GET /stages/:id/tasks` 的 type/displayOrder | 任务列表重刷 |
| OP-10 | 编排重排落库 | `PUT /pipelines/:id` + `PUT /stages/:id` + `PUT /tasks/:id` | sequence/displayOrder/executionMode 改变 | dirty 标记清除 |
| OP-11 | 版本回滚 | `POST /pipelines/:id/versions/:v/rollback` | `pipeline_versions` 新增回滚快照 | 结构回到目标版 |

### 2.3 配置与版本（OP-12~14）

| ID | UI 操作 | 请求 | 后端核对 | UI 反映 |
|---|---|---|---|---|
| OP-12 | 建/改配置参数 | `PUT /components/:id/configs/:key` | `GET /components/:id/configs` 值匹配 | 列表刷新 |
| OP-13 | 删配置参数 | `DELETE /components/:id/configs/:key` | 键消失 + `component_config_history` action=delete | 列表刷新 |
| OP-14 | 配置回滚 | `POST /components/:id/config-versions/:v/rollback` {comment} | `component_config_snapshots.version` +1 且 comment 含"回滚到" | 配置恢复 |

### 2.4 环境与目标（OP-15~18）

| ID | UI 操作 | 请求 | 后端核对 | UI 反映 |
|---|---|---|---|---|
| OP-15 | 建环境 | `POST /environments` {componentId,key,envType,targetId...} | `GET /components/:id/environments` 含新 key | 环境树出现 |
| OP-16 | 建/删环境分组 | `POST /environment-groups`、`DELETE .../:id` | `GET /environment-groups` 增减 | 分组树刷新 |
| OP-17 | 保存环境对接配置 | `PUT /environments/:id` | `GET /environments/:id` 字段匹配 | 状态点更新 |
| OP-18 | 运行连接测试 | `POST /environments/:id/test` | `environments.status/last_test_result` 落库 | checklist 渲染（**注意 verified≠真实可达**，hub 只做 checklist） |

### 2.5 权限（OP-19~23）

| ID | UI 操作 | 请求 | 后端核对 | UI 反映 |
|---|---|---|---|---|
| OP-19 | 建/删平台角色 | `POST/PUT/DELETE /platform-roles` | `platform_roles` 增减 | 列表刷新 |
| OP-20 | 建/删组件角色 | `POST/PUT/DELETE /component-roles` | `component_roles` 增减 | 列表刷新 |
| OP-21 | 平台权限绑定/解绑 | `POST /platform-role-bindings`、`DELETE .../:id` | `platform_role_bindings` 增减 | 绑定表刷新 |
| OP-22 | 组件权限绑定/解绑 | `POST /components/:id/role-bindings`、`DELETE /role-bindings/:id` | `component_role_bindings` 增减 | 绑定表刷新 |
| OP-23 | 集群权限建/吊销/删 | `POST /cluster-permissions`、`.../:id/revoke`、`DELETE .../:id` | `cluster_bindings` 字段变化 | 列表刷新 |

### 2.6 身份与令牌（OP-24~27）

| ID | UI 操作 | 请求 | 后端核对 | UI 反映 |
|---|---|---|---|---|
| OP-24 | 建用户 | `POST /keycloak/users` | `GET /keycloak/users?search=` 含新用户；`user_entity` 新增 | 一次性口令展示、目录刷新 |
| OP-25 | 启停用户 | `PUT /keycloak/users/:id` {enabled} | `user_entity.enabled` 翻转 | 状态刷新 |
| OP-26 | 建/吊销 PAT | `POST /me/tokens`、`DELETE /me/tokens/:id` | `GET /me/tokens` 含新项；`personal_access_tokens.revoked_at` | 明文一次展示、列表刷新 |
| OP-27 | 重置密码 | `PUT /keycloak/users/:id/password` | `credential.created_date` 更新 | 一次性口令展示 |

### 2.7 通知 / 变量组 / 触发器 / 运维（OP-28~32）

| ID | UI 操作 | 请求 | 后端核对 | UI 反映 |
|---|---|---|---|---|
| OP-28 | 保存订阅规则 | `PUT /notifications/subscription` | `GET /notifications/subscription` 字段匹配 | 表单回填 |
| OP-29 | 变量组绑定/解绑 | `POST /components/:id/variable-group-bindings`、`DELETE .../:id` | `GET /components/:id/variable-group-bindings` 增减 | 行变已绑定 |
| OP-30 | 触发器新建/启停/删 | `POST /pipelines/:id/triggers` 等 | `GET /pipelines/:id/triggers` 的 enabled/name | 列表刷新 |
| OP-31 | 保存变更窗口 | `PUT /platform/settings/change-window` | `GET /platform/settings/change-window` 字段匹配 | 表单回填 |
| OP-32 | 凭据建/改/轮转/删 | `POST/PUT /credentials`、`DELETE .../:id` | `GET /credentials` 字段匹配 | 列表刷新 |

## 3. 用例点清单（A 半异步 / B 纯 broker-only）

| ID | UI 操作 | 同步可核对 | 异步/不可即时核对 | 判据 |
|---|---|---|---|---|
| OP-33 | 触发运行 | `pipeline_runs` 新行 phase=Pending + `dispatch_jobs` 入队 | phase 推进靠 runner 回流 | A：断言同步部分，异步带超时观察 |
| OP-34 | 审批决策 | `pipeline_approvals.status/decided_at/approver` 同步写 | 任务放行靠回流 | A：只断言记录落库；注意自审禁止 |
| OP-35 | 取消运行 | 请求 200 | `pipeline_runs.phase` 回流到 Cancelled | B：断言请求发出，phase 异步观察 |
| OP-36 | 单任务重跑 | 请求 200 | task_runs 重置靠回流 | B：同上 |
| OP-37 | 重新投递 | 请求 200 | phase 回流 | B：同上 |
| OP-38 | 灰度 pause/promote/rollback | **零写库**（hub 纯 broker） | `rollout_runs.phase/current_weight` 只由 runner 回流写 | B：只断言请求 200；**禁止**用 UI 步骤器变化证明下发成功 |

## 4. 前端缺失入口（无法从 UI 测，登记不测）

变量组 CRUD、审批策略配置、权限申请发起、编辑组织/服务、编辑环境分组、编辑/删除接入目标、组件变量组优先级调整、组织工作台资源/成员/集群权限（占位）。详见 `GAP-CONSOLE-UI-VERIFICATION-2026-11-21.md` G5/G7 等。

## 5. 执行与判定纪律

1. 每条用例：操作前读一次后端状态 → UI 操作并捕获请求 → 操作后再读后端状态 → 断言"状态确实按请求改变"。
2. 失败先归因：**驱动选择器错**（改测试）／**后端没落库**（修 hub）／**前端没发请求或发错**（修 console）。三者都当场修根因再继续。
3. broker-only（B 类）禁止用 UI 呈现判成功；只能断言请求发出且无错。
4. 所有证据入 `console/evidence/<stamp>/`，manifest 记 `before/after/request/verdict`。
5. 不因单条失败停下问用户；按清单逐条推进，直到可测项全部执行完。

## 6. 变更历史

| 时间 | 变更 |
|---|---|
| 2026-11-21 | 初版：从"UI 呈现验证"转向"UI 下发逻辑验证"，枚举 38 条操作用例（32 同步 + 6 异步/broker-only），建立"操作→请求→后端状态→UI"判据模型与 S/A/B 分层。 |
| 2026-11-21 | 全量执行 + 根因修复：`op-harness.mjs`（三段判据 + S/A/B 分层，B 类只断请求 2xx 无 JS 异常、禁止用 UI 反馈证明下发）、`op-fixtures.mjs`（公共 setup）、`seed-op-runs.mjs`（A/B 类幂等造数）。执行脚本按域拆分：第一批 7/7（OP-01/12/19/26a/26b/28/31）、tree 10/10（OP-02~05/13~18）、pipeline 5/5（OP-06~09/30）、perm 3/3（OP-20/21/32）、run 6/6（OP-33~38）、extra（OP-10/11/22/23/29）。**两处产品缺陷从第一性原理修复**：① 环境 `PUT /environments/:id` 全量绑定 + gorm Save，前端只发可编辑字段导致 key/status/lastTestResult 被零值清空——hub `internal/environment/service/environment.go` 改 read-modify-write（服务器自有字段从 stored row 继承），加 `TestUpdate_PartialPayloadKeepsServerOwnedFields` 单测，镜像 `v0.0.3-envfix` 部署后 API 复现验证 key/status 保留；② 集群权限页环境下拉用 `listPaged('/environments')` 默认分页（pageSize=20），环境增多后选项被挤出无法新建——`ClusterPermissionsView.vue` 改 `pageSize:1000`。验证 gate：hub go test/vet 绿、console pnpm build + test:runcenter 22/22 绿。**诚实 known-gap**：OP-24/25/27（建/启停用户、重置密码）因本地 Keycloak 目录不可用（无新建用户入口）SKIP，不记通过。 |
| 2026-11-21 | 收口复验与三处追加修复，最终 36/36 PASS（operations 7 + tree 10 + pipeline 5 + perm 3 + run 6 + extra 5）。① **修正上一行 ② 的误诊**：环境下拉恒空的真根因是 hub 从未注册全量 `GET /environments`（`RegisterCRUD` 只挂 POST/GET/:id/PUT/:id/DELETE/:id，按组件列出走 `/components/:id/environments`），前端请求 404 被 `.catch(()=>({items:[]}))` 静默吞掉——补 repo `FindAll` + service `List` + handler `GET /environments`（platform-wide 分页列表），`pageSize:1000` 保留为下拉全量语义。② 集群权限创建对"环境未配 kubeconfig"返回 500：`kubeconfigResolver.Resolve` 改抛 `common.ErrBadRequest`（APIError 透传 → 400 可操作提示），`ClusterPermissionHandler.Create` 改 `AbortWithError`；`e2e-ops-extra` 造数改为 kubeconfig 凭据（kind kubeconfig server 换集群内 DNS）+ kubeconfig 模式环境。③ OP-12 UI 反映失败：`GET /components/:id/configs` 无排序 + 默认分页把新建参数挤出第一页——`ComponentConfigRepository.FindByComponentID` 改 `created_at DESC, key DESC`（新参数首行可见）。部署链：console `v0.0.3-opfix`、hub `v0.0.3-envfix → envlist2 → cfgsort`。 |
