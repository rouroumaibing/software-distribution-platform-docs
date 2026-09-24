# 未落地模块梳理与开发计划（UNIMPLEMENTED MODULES PLAN）

> 来源：`software-distribution-platform-docs` 全库 + 三仓实际代码（source-grounded 核对，2026-09-22）。
> 目的：把"文档里写了、代码里还没落地"的模块**全部梳理**成一张清单，按优先级给出执行顺序，并标注本期已实现的部分。
> 本文是**权威待办索引**；具体契约见各自文档（`DELETE-CONTRACT.md` / `DATA-MODEL.md` / `ACCOUNT-PERMISSION-MODEL.md` / `STORY-BACKLOG.md`）。

---

## 0. 已落地（从 backlog 中剔除，避免误读）

| 编号 | 事项 | 落地时间 / 证据 |
| --- | --- | --- |
| B-03 | 审批下发闭环（`POST /pipelines/:id/runs/:runId/tasks/:taskName/decision`） | 早前 Runner 实现 |
| B-12 | 后端 DELETE 级联校验 + `409 + {reasons}`（N-15 / N-5） | **2026-09-22 本轮**（§3.4 gate 全绿） |
| B-13 | 环境分组落库（`environment_groups` + `environments.group_id`） | **2026-09-22 本轮**（§7.12 一并实现，含 409 非空拒绝） |
| B-14 | `component_config_history` 去 FK + `environment_key` 快照列 | **2026-09-22 本轮**（`migrations/0008`） |
| B-15 | 封父存在性校验 + `pipelines` partial unique index + 模型时间列映射 | 2026-09-16（`DELETE-CONTRACT.md` §6.6-3 落地记录） |
| B-15(剩) | `pipeline_stages` / `pipeline_task_templates` 补 `deleted_at`（+ 活行唯一 + stage 级联软删） | **2026-09-22 本轮**（`migrations/0009`） |
| B-16(源头) | Artifact 删对象不再吞错（改结构化日志） | **2026-09-22 本轮**（级联 / 清理标记 / `expires_at` 生效 / 对账仍未做） |
| §7.12 环境对接配置 | 前端 5 组件 + hub credentials/environmentgroup/connection-test/parse-kubeconfig/enroll-token | **2026-09-22 本轮** |
| console 多数 §7.x 页面骨架 | OverviewTab / ConfigTab / PipelinesTab / ReleasesTab / RunsTab / EnvironmentsTab / PermissionsTab / ArtifactsTab / LogsTab / PlatformAdminView 均已存在 | console `src/views` 实测 |
| C-01 | ⌘K 全局搜索（浮层，跨类型命中 + 键盘导航 + 客户端索引） | **2026-09-22 本轮**（`CommandPalette.vue` + `utils/search.ts` + `useGlobalSearch.ts`；25 条契约断言） |
| C-02 | 暗色主题（双主题令牌 + 顶栏切换 + 灰阶自检 + 首屏防白闪） | **2026-09-22 本轮**（`tokens.css` 双块 + `utils/theme.ts` + `index.html` 引导脚本；**左栏清掉海军蓝与 3px 竖条**，落 §9.2 的 P4） |
| C-12 | 流水线全生命周期 UI（列表五列 / 新建入口 / 删除强确认 + `409 reasons` / 编辑器重排 + `executionMode` 开关 + 请求体预览 / 子任务表单改**配置派生**） | **2026-09-22 本轮**（§5；门禁 `pnpm test:pipeline` 41 条） |
| hub `pipeline_stages.execution_mode` | 阶段内并行 / 串行**字段**落地（存得下、读得回、UI 可切换）；**`Serial` 调度行为仍缺**（backlog C-06） | **2026-09-22 本轮**（`migrations/0010`） |
| hub `GET /runs?componentId=` | 可选过滤，供流水线列表「最近运行」列一次取回（避免 N+1） | **2026-09-22 本轮** |

---

## 1. 未落地模块总表（按 epic 分组）

### Epic A — 后端数据一致性 / 删除契约（✅ **本轮已完成 — 2026-09-22**）
> 权威规格：`hub/DELETE-CONTRACT.md` §4 + §6.6；决策均已拍板（§6.5）。
> **状态**：B-12 / B-14 / B-15（含 `deleted_at`）全部完成；B-16 仅"源头堵漏"完成，级联 + 清理标记 + `expires_at` + 对账见 Epic E。落地清单 / gate / 未跑项见 §3.1 与 §3.4。
> 下表"当前真实状态"列保留为**改造前**的快照，便于回溯。

| 编号 | 事项 | 当前真实状态 | 阻塞 | 关联 |
| --- | --- | --- | --- | --- |
| **B-12** | `DELETE` 级联校验 + `409 + {reasons}` | `APIError` 无 `reasons` 字段；Service/Component/Environment.Delete 均直删无校验；Pipeline.Delete 仅"任意历史即拒"（语义错） | 无 | §N-15 / §N-5 |
| **B-14** | `component_config_history` 去 FK + 加 `environment_key` 快照列 | 模型无该列；FK 仍在 → 删环境随机 500 | 无（需手跑迁移去 FK） | §6.6-2 |
| **B-15(剩)** | `pipeline_stages` / `pipeline_task_templates` 补 `deleted_at` | 两模型仍 `BaseNoSoftDelete` 无 `deleted_at` | 无（仅剩此列，不需产品拍板） | §6.6-3 |
| **B-16(源头)** | Artifact 源头治理（级联 + 清理标记 + `expires_at` 生效）+ 孤儿对账（仅报告） | `artifact/service.Delete` 吞错 `_ = store.Delete()`；无 GC | 对账任务可延后（仅报告） | §6.6-4 |

### Epic B — Console UX 缺口（前端，自包含）
| 编号 | 事项 | 当前真实状态 | 阻塞 |
| --- | --- | --- | --- |
| **C-01** | ⌘K 全局搜索（浮层，资源直达） | ✅ **已落地（2026-09-22 本轮）** — 见 §4 | — |
| **C-02** | 暗色主题（dark token + 切换） | ✅ **已落地（2026-09-22 本轮）** — 见 §4（含左栏 P4 纠正） | — |
| ~~**C-08**~~ | ~~DAG 自由画布编辑器~~ | ⛔ **刻意不做** —— `CONSOLE-UI-DESIGN.md` §4.2 已裁定：`❌ DAG 自由画布（沿用结论，DependsOn 需求明确后评估 vue-flow）`。本 plan 首版曾把 C-08 误列为待办，此处纠正 | 待 `DependsOn` 需求拍板 |
| **C-12** | 流水线全生命周期 UI（新建/删除入口完整） | ✅ **已落地（2026-09-22）** —— 见 §5 | — |
| **R-8**（补记） | 服务树独立页规模化：懒加载（展开才请求）+ 服务端搜索 + 虚拟滚动 + 独立滚动容器 | ✅ **已落地（2026-09-22）** —— 见 §6。服务端端点已自行拍板并实现（`GET /search` = 附 A N-8、`GET /orgs/:id/services` = 附 A N-9），前端四项机制全部到位 | — |
| B-01(部分) | 运行 DAG 监控 / 灰度监控页 | `RunMonitorView`/`RunListView` 存在但 DAG 可视化未做 | 无 |

### Epic C — 账号与权限（**D1–D6 已闭，0 项阻塞**）
| 编号 | 事项 | 当前真实状态 | 阻塞 |
| --- | --- | --- | --- |
| **C-10** | 平台级 RBAC HTTP 端点（`/platform-roles`、`/platform-role-bindings`） | ✅ **已落地（2026-09-22）** —— 见 §8 | — |
| PermissionsTab 功能化 | §7.9 组件级权限 Tab 真正可用（绑定 CRUD） | ✅ **已落地（2026-09-22）** —— 页面骨架 + 绑定 CRUD 均已实现 | — |
| 平台级权限管理 UI | 「用户与平台权限」页（PlatformAdminView）真正可用：平台角色 CRUD + 平台绑定 CRUD，消费 C-10 端点 | ✅ **已落地（2026-09-22 第七批）** —— 见 §8.5 | — |
| 账号/权限模型缺口 | §10 对账 15 行（组织 claim 未接 / 无 audit / 无 permission_request / Casbin / `/api/userinfo`） | ✅ **已全部落地**：第八批（§9：四表 + 审计 + 审批 + 回收 + D3 可逆部分）、第十一批（§12：组织 claim + 资源归属强制点）、**第十四批（§14：D3 全量执行 —— 删 `users` 表 / `owner_sub` / V1 遗留列）**。**仍不做**：Casbin（D4 已定延后）；**仍未建**：realm 侧**组织组** `/org:<slug>`（DB 驱动，须按库中 orgs 逐条建，写不进静态 realm JSON） | 仅剩 2 项非本仓代码 |
| **§10 #14（预修）** | `RequirePermission` 把 pipeline/run id 当 component id 查绑定 ⇒ 开鉴权后**恒 403** | ✅ **已修复（2026-09-22）** —— 见 §7 | 无（不依赖 D1–D6） |

### Epic D — Runner / 执行后端
> 全部 10 项已于 **2026-09-22** 落地（`software-distribution-platform-runner` 模块），`go build / go vet / go test` 全绿，新增纯逻辑单测 30+ 例。e2e 未跑（无运行集群），详见文末「Epic D 落地记录」。

| 编号 | 事项 | 当前真实状态 | 阻塞 |
| --- | --- | --- | --- |
| B-02 | 实时日志流（`log_chunk` 落库 + Pod 抓取发送） | ✅ **已落地（2026-09-22）** — `pkg/logstream` 行分块 + 通过 `connector` 发 `LogChunkPayload`；TaskRunReconciler 在 Job Running 时起 goroutine 抓 Pod 日志（受 `SDP_LOG_STREAMING` 降级开关控制） | 无 |
| B-04 | IngressCanary 专用 canary Ingress | ✅ **已落地（2026-09-22）** — `TrafficRoutingType==IngressCanary` 时建/更新带 `nginx.ingress.kubernetes.io/canary-weight` 注解的 canary Ingress（M1 仍保留副本切分，Ingress 为渐进路由资源交付） | 无 |
| B-05 / B-06 | HTTP/Prometheus 健康检查 / Rollout 读真实 replicas | ✅ **已落地（2026-09-22）** — `canary.Evaluate` 增 `healthy` 入参，HTTPProbe/PrometheusQuery 通过 `pkg/health` 真实探测并计入 `ConsecutiveFailures`→自动回滚；`RolloutSpec.Replicas` + 在线 Deployment `spec.replicas` 优先于默认 2 | 无 |
| B-08 | 单元测试（核心逻辑） | ✅ **已落地（2026-09-22）** — canary engine / health / logstream / dispatch(快照+重跑) / controller(串行+resync) / 环境模型 均有表驱动单测 | 无 |
| B-09 | 监控告警 + 降级开关 | ✅ **已落地（2026-09-22）** — `pkg/metrics`（Prometheus 计数器/仪表 + 失败告警），`SDP_LOG_STREAMING` / `SDP_CANARY_INGRESS` / `SDP_ALERTING` 三个降级开关 | 无 |
| C-03 | Pipeline 触发时 stages/tasks 快照固化 | ✅ **已落地（2026-09-22）** — `ApplyPipelineRunPayload.PublishVersion` + `SnapshotSpec` 内容哈希，Apply 时落 `sdp.io/spec-snapshot` / `sdp.io/publish-version` 注解 | 无 |
| C-05 | connector 重连后 resync | ✅ **已落地（2026-09-22）** — `connector.OnConnect` 钩子 + `controller.ResyncAll` 重连后回灌在途 PipelineRun 状态 | 无 |
| C-06 | ExecutionMode=Serial（阶段内串行） | ✅ **已落地（2026-09-22）** — `PipelineTaskSpec.ExecutionMode` + `findRunnableTasks` 串行判定（同阶段任务逐一通过，无需 hub 合成 DependsOn） | 无 |
| C-07 | 失败节点单任务重跑 | ✅ **已落地（2026-09-22）** — `MessageRerunTask` / `RerunTaskPayload` + `RerunHandler` 重置单任务并级联重跑下游（`DownstreamTasks` 纯函数） | 无 |
| C-13 | Test 类型 / 环境模型 | ✅ **已落地（2026-09-22）** — `TaskTypeTest`（按 Build 同路执行）+ `EnvironmentType` 六类枚举与 `IsValidEnvironment` 校验 | 无 |

### Epic E — Hub / Console 功能完整性（✅ **本轮已完成 — 2026-09-22，§11**；B-07 除外）
| 编号 | 事项 | 当前真实状态 | 阻塞 |
| --- | --- | --- | --- |
| B-07 | 端到端验证 | ⛔ **仍未跑**（本机无集群：`kind` 未安装、`kubectl` 无 current-context）—— 仅编译/vet/单测通过，**未伪造** | 需真实/kind 集群 |
| B-11 | 主规格细化（审批超时/生产强审批/产物签名下载/版本对比/自定义角色） | ✅ **已落地（2026-09-22 本轮）** —— 审批超时 + 生产强审批新写；产物签名下载**核对后确认既有实现已完整**（仅更正过时 ⬜）；版本对比由 C-09 一并交付；自定义角色补齐组件级 CRUD（`/component-roles` 写端点）。见 §11.1 | — |
| C-09 | 流水线版本历史/对比/回滚 | ✅ **已落地（2026-09-22 本轮）** —— 结构性保存自动留档 + 4 个 hub 端点 + console 版本面板。见 §11.2 | — |
| B-16(对账) | Artifact 孤儿对象对账（周期性、仅报告） | ✅ **已落地（2026-09-22 本轮）** —— 只报告不删除，默认关闭（`ARTIFACT_RECONCILE_INTERVAL=0`）。见 §11.3 | — |

---

## 2. 推荐执行顺序（按"规格完整度 × 阻塞度 × 价值"）

1. ~~**Epic A（本期）** — 规格最完整、决策全拍板、无外部阻塞、直接提升数据完整性。~~ ✅ **已完成（2026-09-22）**，见 §3.4。
2. ~~**Epic B：C-01 ⌘K + C-02 暗色主题** — 纯前端、自包含、用户可感知度高。~~ ✅ **已完成（2026-09-22）**，见 §4。
3. ~~**Epic B：C-12 流水线全生命周期 UI** — B-12 后端契约已就位。~~ ✅ **已完成（2026-09-22）**，见 §5。
   - ⚠️ 原写「+ C-08 DAG 画布」系误列：DAG 自由画布属 §4.2 **刻意不做**，不在执行序内。
4. ~~**Epic B：R-8 服务树规模化** —— 原本卡在"服务端搜索端点未定"。~~ ✅ **已完成（2026-09-22）**，见 §6。
   - 端点不再等外部拍板：由本轮自行定形并实现（`GET /search` + `GET /orgs/:id/services`），落地后 `CONSOLE-UI-DESIGN.md` 附 A 的 N-8 / N-9 两条后端依赖**同时关闭**。
5. **Epic C（账号权限）** — ✅ **已全部落地**：第一批（**C-10** + `expires_at` ×2，见 §8）、批次七（PermissionsTab + 平台权限 UI）、批次八（§9：四表 + 审计 + 审批 + 回收 + D3 可逆部分）、批次十一（§12：组织 claim + 资源归属强制点）、**第十四批（§14：D3 全量执行，含唯一不可逆的删 `users` 表）**。**剩余（均非本仓代码）** = 部署侧手工跑 `migrations/0015`、realm 侧组织组 `/org:<slug>`（DB 驱动）、Casbin（D4，条件触发）。
6. **Epic D / E（Runner / 功能完整性）** — ✅ **Epic D 已完成（2026-09-22）**，见 §10；✅ **Epic E 已完成（2026-09-22 本轮）**，见 §11（**唯一未跑项 = B-07 端到端验证**，需真实/kind 集群）。**下一步 = 有集群后跑 B-07**（`plans/E2E-VERIFY-PLAN.md` + `plans/e2e-smoke.sh`），其余登记项见 §11.4。

---

## 3. 本期执行范围（Epic A）

### 3.1 交付清单（**全部完成 — 2026-09-22**）

- [x] **B-12-foundation**：`common.APIError` 增 `Reasons []string` + `DomainErrorWithReasons`；`Envelope` 增 `reasons` 并序列化（`internal/common/{errors,response}.go`）。
- [x] **B-12-pipeline**：`PipelineService.Delete` 改为"仅活跃 phase（Pending/Running/WaitingApproval）拒绝"+ `reasons`；**不再调用** `CountByPipeline`。
- [x] **B-12-component**：`ComponentService.Delete` 注入活跃运行计数，有活跃运行 → `409 + reasons`；否则软删。
- [x] **B-12-service**：`ServiceService.Delete` 注入活跃运行计数（按 service 下钻 component→pipeline→run），有活跃运行 → `409 + reasons`；否则软删。
- [x] **B-12-env**：`EnvironmentService.Delete` 删前统计配置覆盖条数并写审计日志（不拒绝，§6.4 #8）。
- [x] **B-14**：`ComponentConfigHistory` 加 `EnvironmentKey`；config 服务经 `EnvKeyResolver` 写历史时填充（解析失败降级 `""`，不阻断写入）；新增迁移 `0008` 去 FK + 加列（AutoMigrate 加列；FK 需手跑 SQL）。
- [x] **B-15**：`PipelineStage` / `PipelineTaskTemplate` 换 `common.Base` 加 `deleted_at`；旧唯一约束改 partial unique index（`0009`）；`StageService.Delete` 服务层级联软删模板。
- [x] **B-16-source**：`ArtifactService.Delete` 不再吞错——对象清理失败记结构化日志；元数据已删即成功（不把对象错误升级成 API 错误，避免对调用方撒谎）。
- [x] 文档回填：`STORY-BACKLOG.md`（B-12~B-16 状态）、`DELETE-CONTRACT.md` §1.3 / §2.3 / §4.1 / §4.4 + §6.6-2 / §6.6-3 落地记录 + §6.7 状态。

**本轮附带修复（不在原清单，但为通过 gate 与修掉真实缺陷）**
- `internal/component/service/component.go`、`internal/catalog/service/service.go` 缺 `net/http` import（**编译失败**，上一轮遗留）。
- **`uniqueIndex` 标签 shared 字段写漏**：首版只在 `Name`/`Sequence`、`Name` 上打标签，GORM 会生成 `UNIQUE(name, sequence)` / `UNIQUE(name)` —— 语义从"pipeline/stage 内唯一"静默变成"全表唯一"。已补 `PipelineID` / `StageID`，并由 DB-free schema 测试钉住完整索引 DDL。
- `ComponentService` / `ServiceService` / `PipelineService` / `EnvironmentGroupService` 的持久化依赖改为窄接口（`ComponentStore` / `ServiceStore` / `PipelineStore` + `VersionStore` / `EnvironmentGroupStore`），使删除分支可脱离 Postgres 单测 —— 与 `StageService` / run 包既有手法一致。
- **`EnvironmentGroup.Delete` 的 verdict 形状与契约不符**：原实现返回 `400` 且**不带 `reasons`**，而 `DELETE-CONTRACT.md` §6.4 #11 与 `DATA-MODEL.md` §8.4 均要求 `409 + {reasons}`。已改为 `DomainErrorWithReasons(KindEnv, 409, 2, …, reasons)`（带组内环境条数），并由单测固定。

### 3.2 验证 gate
- `go build ./...` + `go vet ./...` + `go test ./...`（含新增删除级联单测）全绿。
- 单测：`ComponentService.Delete` / `ServiceService.Delete` 有活跃运行 → `409 + reasons`、无 → 放行；`PipelineService.Delete` 仅活跃拒绝、历史放行；`EnvironmentGroup.Delete` 非空 → `409 + reasons`、空 → 放行；stage 软删级联 3 例；`envKeySnapshot` 4 例；DB-free schema 2 例。
- 不跑端到端（无运行集群），文档标注"未跑 e2e-smoke"。

### 3.3 明确不做（本期）
- B-16 的周期性孤儿对账任务（仅报告）—— 按 §6.6-4 延后，源头先堵。
- Service/Component 删除的**全量级联软删**（子资源物理清理）—— 本期只做"活跃运行拒绝"这一硬规则；级联清理作为后续独立任务（需跨 repo 事务设计）。
- Epic C/D/E 全部—— 等本轮 Epic A 验收后再排期。

---

### 3.4 落地结果与验证（2026-09-22）

**Gate 结果：全绿**（`software-distribution-platform-hub`）

| Gate | 命令 | 结果 |
| --- | --- | --- |
| 构建 | `go build ./...` | ✅ |
| 静态检查 | `go vet ./...` | ✅ clean |
| 单测 | `go test ./...` | ✅ 全部 ok |
| 格式 | `gofmt -l`（仅本轮触碰的文件） | ✅ clean |

> `gofmt -l` 在本仓**全量**跑仍会列出 9 个文件（`credentials/*`、`db/db.go`、`environment/models/environment.go`、`environmentgroup/handler/*`、`middleware/user_context.go`、`permission/models/{binding,role}.go`、`target/models/target.go`）—— 这些是本轮**未触碰**的历史遗留漂移，未一并格式化以免污染 diff。

**新增测试（18 例）**

| 文件 | 覆盖 |
| --- | --- |
| `internal/component/service/delete_test.go` | 活跃运行 → `409 + reasons` 且**不碰 repo**；仅历史 → 放行；未装配 counter 仍可删 |
| `internal/catalog/service/delete_test.go` | 同上（service 层，`ERR.04409001`） |
| `internal/pipeline/service/pipeline_delete_test.go` | 流水线：仅活跃拒绝 / 42 条历史放行且**不再调** `CountByPipeline`；stage 软删级联 3 例（正常 / 级联失败可重试 / 未装配级联） |
| `internal/component/service/config_test.go` | `envKeySnapshot` 4 例（nil 环境不查库 / 正常解析 / 解析失败降级 / nil resolver） |
| `internal/environmentgroup/service/delete_test.go` | 分组非空 → `409 + reasons`（`ERR.07409002`）且不碰 repo；空组 → 放行 |
| `internal/db/schema_dryrun_test.go` | GORM DryRun **不连库**钉住"模型 → DDL"：`deleted_at` 列、两条 partial unique index 的**完整列清单**、`environment_key` 快照列且 `environment_id` 保留 |

**未跑（如实标注）**
- 真实库上的 `migrations/0008` / `0009`；`plans/e2e-smoke.sh`（本地无 Postgres / Docker / 集群）。
- 落地到环境时的前置检查：① 0008 依赖 Postgres 默认约束名 `component_config_history_environment_id_fkey`（文件带 `if exists` + 自检兜底）；② 0009 若库里已有重复**活行**，建唯一索引会报 duplicate key，须先人工去重。
- console 侧 `mockDeleteNode` / `mockDeletePipeline` 仍未切真端点（纯前端改动，不在 Epic A 范围）。

---

## 4. Epic B 第一批（C-01 ⌘K + C-02 暗色主题）落地结果与验证（2026-09-22）

> 规格权威在 `console/CONSOLE-UI-DESIGN.md` §5.3 / §7.1 / §7.5 / §9.2 / §9.6，**正文未改**；
> 实现态、显式差异、顺带修掉的缺陷全部记在 **该文档「附 G」**，本节只做**索引 + 门禁**。

### 4.1 交付清单（全部完成）

| 编号 | 落地物（`software-distribution-platform-console/src/`） |
| --- | --- |
| C-02 | `styles/tokens.css`（`:root` / `:root[data-theme="dark"]` 双块 + `:root.gray`）、`utils/theme.ts`（纯逻辑）、`composables/useTheme.ts`（状态 + 副作用）、`index.html` 首屏内联引导（防白闪） |
| C-02 | `layout/MainLayout.vue`：顶栏三件套（⌘K 搜索 / 主题 / 灰阶）；左栏改 `--rail-bg`、去 3px 竖条、图标换原型线性 SVG |
| C-01 | `components/CommandPalette.vue`（四态 + ↑↓/Enter/Esc）、`composables/useGlobalSearch.ts`（索引/防抖/选中）、`utils/search.ts`（纯打分排序，零 import） |
| C-01 | `views/ServiceTreeView.vue` 消费 `?node=<id>` 深链（服务树页定位） |
| C-01 | `composables/useResourceMap.ts` 扩出 `services` / `components` 池（与运行中心共用一次树遍历） |
| 门禁 | `scripts/theme-and-search-smoke.mjs` + `package.json` 加 `test:theme-search` / `test` |

### 4.2 Gate（全绿）

| Gate | 命令 | 结果 |
| --- | --- | --- |
| 类型 | `vue-tsc --noEmit` | ✅ |
| 构建 | `vite build` | ✅（暗色块与 `--rail-*` / `--term-*` 已进产物 CSS） |
| 既有契约冒烟 | `pnpm test:runcenter` | ✅ 16/16（无回归） |
| 新增契约冒烟 | `pnpm test:theme-search` | ✅ 25/25 |

### 4.3 本轮顺带修掉的真实缺陷（不在原清单）

1. `PermissionsTab.vue` 引用三个**从未定义**的令牌（`--border` / `--primary` / `--muted-fg`）→ 该页边框与文字色**静默失效**。
2. 左栏底色是固定海军蓝 `--menu-bg: #001529`，与 §9.2「light 全浅 / dark 全深，消除割裂（P4）」直接冲突。
3. 日志/终端面板硬编码 `#0f172a` / `#e2e8f0` → 暗色主题下与 `--bg` 几乎同色，面板失去边界（已抽 `--term-bg` / `--term-fg`）。

### 4.4 明确不做（本轮）

- **顶栏面包屑**（§7.1）：需同时改 10+ 个 view 并先裁定各页段位，独立排期；不与 C-01/C-02 混进同一 diff。
- **顶栏「ⓘ 设计备注」**（§8.4）：备注内容是按视图维护的评审数据，console 尚无数据源 —— 按其自身铁律「不渲染无 handler 的装饰控件」，先不渲染该按钮。
- **服务端 `GET /search`**（附 A N-8）：hub 未落地；console 走**已文档化的降级路径**（前端一次遍历建索引）。N-8 仍开放。

### 4.5 下一步

C-12 已完成（见 §5）。按 §2 顺延，下一步为 **R-8 服务树规模化**（懒加载 / 服务端搜索 / 虚拟滚动 / 独立滚动容器）—— 但它**卡在服务端搜索端点未定**（与 附 A N-8 同源），需先拍端点形态再动前端；若该端点短期不排，建议直接跳到 **Epic C（账号权限）** 的 D1–D6 拍板。

> **两处更正与补记**（本轮发现，已回改本文档）：① C-08 DAG 自由画布原被误列为待办，实为 §4.2 刻意不做；② 新增补记 **R-8**（服务树规模化：懒加载 / 服务端搜索 / 虚拟滚动），§4.1 在范围内且实现缺口真实，此前未被跟踪。

---

## 5. Epic B 第二批（C-12 流水线全生命周期）落地结果与验证（2026-09-22）

> 权威规格：`console/CONSOLE-UI-DESIGN.md` §6.1 · §7.4 · 附 D；落地记录见该文 **附 H**。

### 5.1 交付清单

| 项 | 落地物 |
| --- | --- |
| 列表（§7.4） | `console/src/views/component/tabs/PipelinesTab.vue`：五列（名称 / 类型 / 版本 / 最近运行 / 操作「运行 · 编辑 · 删除」）+ `＋ 新建流水线`；「最近运行」走一次 `GET /runs?componentId=` 本地分组 |
| 新建（§6.1 C1） | 名称 / 类型 / 描述 + 所属组件**只读锁定** → `POST /pipelines` → 保存后直接进编辑器 |
| 删除（§6.1 D1） | **强确认（输入名称）** → `DELETE /pipelines/:id`；`409 + {reasons}` 渲染「无法删除」，reasons **原样**来自后端 |
| 编辑器（§7.4） | `console/src/views/PipelineEditorView.vue`：**改直取 `GET /pipelines/:id`**；头部「编辑信息」；阶段 `◀ ▶` / 子任务 `▲▼` 重排；阶段头 `executionMode` 切换；`[保存] [▶ 触发] [🗑 删除流水线]` |
| 请求体预览（附 D.4） | 保存前 JSON / YAML 双视图 + 端点标注 + **实际调用序列**（如实标注 hub 无整 DAG 端点） |
| 子任务表单（§7.4 拍板） | `console/src/components/TaskFormDrawer.vue`：**去掉三态原词三选一**，改为派生出的产品语言 + 三段配置 |
| 纯逻辑层 | `console/src/utils/pipeline.ts`（零 import，可被 node 直接 import 断言） |
| hub 侧 | `migrations/0010` + `PipelineStage.ExecutionMode` + `StageService` 枚举校验 + `PUT /stages/:id` 透传；`GET /runs?componentId=` 过滤 |

### 5.2 门禁

```
vue-tsc --noEmit            ✅
vite build                  ✅（PipelinesTab / PipelineEditorView 均懒加载分包）
pnpm test:runcenter         ✅ 16/16   （既有门禁无回归）
pnpm test:theme-search      ✅ 25/25   （既有门禁无回归）
pnpm test:pipeline          ✅ 41/41   （本轮新增）
（hub）go build / vet / test ✅ 全绿
```

### 5.3 如实标注：仍未做

- **`Serial` 的调度行为**（backlog C-06）：`execution_mode` 只做 API ↔ DB 往返；serial 阶段里的子任务在 runner 侧**仍并发启动**。UI 不声称串行已生效。
- **hub 无「整 DAG 一次提交」端点**（附 D.4 的待拍项）：[保存] 由 console 展开为多次调用（元信息 1 次 + 每阶段 1 次 + 子任务按需），预览面板已如实展示该序列。
- **真实浏览器交互未接自动化**：浮层 / 抽屉 / 重排的端到端行为只有纯逻辑单测 + 源码静态断言覆盖。
- **未跑真实库**：`migrations/0010` 需手跑 psql（AutoMigrate 会加列；CHECK 约束与老行回填只在迁移里）。

### 5.4 顺带修掉的真实缺陷（均不在原清单）

1. `TaskFormDrawer` 把三态原词做成用户可选项，**直接违反 §7.4 拍板**。
2. 编辑器按"pipeline 无单查端点"的**过时结论**绕路（`?componentId=` 反查），而 `GET /pipelines/:id` 一直存在。
3. 列表按 `kind !== 'build'` 拦截编辑 —— 过时客户端闸门（N-7）。
4. 列表徽章原计划自造 `st-*` 类，而 `tokens.css` 已有全局 `.b-*`（§8.1）—— 自造类未定义会让状态色**静默丢失**（本轮在写组件前对齐，未进入产物）。

### 5.5 下一步

**R-8 服务树规模化** —— 但**卡在服务端搜索端点未定**（与 `CONSOLE-UI-DESIGN.md` 附 A N-8 同源）。若无该端点，懒加载与虚拟滚动只能做一半（可先做独立滚动容器 + 展开才请求，服务端搜索留白）。若短期不排此端点，建议改跳 **Epic C（账号权限）**，先拍 D1–D6。


---

## 6. Epic B 第三批（R-8 服务树规模化）落地结果与验证（2026-09-22）

### 6.1 交付清单

**hub**
- 新模块 `internal/search`（models / repository / service / handler）+ `GET /search?q=&type=&limit=`（附 A N-8）：
  三类资源（service / component / pipeline）各取 `limit` 条；`ILIKE` 匹配名称与 key 并**转义 LIKE 元字符**；
  排序为「精确命中 > 名称前缀 > 名称包含」；JOIN 出展示路径 `组织 / 服务 / 组件`；逐表过滤软删。
- `internal/catalog` 新增 `ListByOrg` + `GET /orgs/:id/services`（附 A N-9）：一次把组织 id 解析成 1:1 服务树再列直接子层。
- 测试：`internal/search/service/search_test.go`（解析 / 分发 / 夹取 / 合并顺序 / 不吞错）、
  `internal/search/repository/search_dryrun_test.go`（**DB-free 查询形状回归**）、
  `internal/catalog/service/org_services_test.go`（树 id 解析 / 未知组织向上抛 / 漏装配不 panic）。

**console**
- `views/ServiceTreeView.vue` 重写：懒加载四态状态机 + 服务端搜索面板 + 虚拟滚动 + 独立滚动容器；
  保留 `?node=` 深链定位（新增 `?org=` 组织提示，避免逐个组织扫描）。
- `utils/tree.ts`（零 import 纯逻辑）：`flattenVisible` / `computeWindow` / `shouldVirtualize` /
  `expandAction` / `lazyHintLabel` / `ensureVisible`。
- `api/search.ts` + `api/catalog.listByOrg`；`utils/search.ts` 增 `hitFromDto`（DTO→SearchHit 翻译）与
  Service 深链的 `org` 提示。
- ⌘K 改造：`composables/useGlobalSearch.ts` 改**服务端优先、客户端索引兜底**；`CommandPalette.vue` 增降级提示条。
- 门禁：`scripts/service-tree-smoke.mjs`（22 条断言）。

### 6.2 门禁（全绿）

```
（hub）go build / go vet / go test                      ✅
（console）vue-tsc --noEmit / vite build                ✅
pnpm test:runcenter  16/16 · test:theme-search 25/25
pnpm test:pipeline   41/41 · test:service-tree  22/22   ✅
```

### 6.3 顺带修掉的真实缺陷（均不在原清单）

1. **虚拟滚动窗口"滚过头"时区间反转**（`start > end`）→ 上层 `slice` 得空数组 → **整棵树白掉**。
   写冒烟断言时被抓到，已改为"吸附到最后一屏"。
2. **⌘K 客户端索引有语料上限**：每层 `pageSize:100`，单服务超 100 组件时**静默漏搜**。
   服务端搜索的 `limit` 是**结果**上限而非**语料**上限 —— 这是把非空查询切到服务端的实质收益。
3. **包级错误单例被就地改写**：`common.ErrBadRequest.WithError(...)` 会污染共享变量（并发下互相覆盖消息）。
   新模块改用"只读模板 + 值拷贝"，并写断言钉住。**既有 `common/handler.go` 的同类写法列为待清理项。**

### 6.4 本轮明确未做

- 服务端搜索**不做权限过滤**（只回导航信息）——等 Epic C 的 D1–D6 拍板后按 `ACCOUNT-PERMISSION-MODEL.md` §10 收窄。
- 单层 100 条上限仍在（行尾显示「已加载 N/M」不静默），彻底解决需服务端分页 + 滚动加载。
- `?node=` 深链只承载 Service id（组件/流水线命中有各自的目标页）。

### 6.5 下一步

**Epic C（账号权限）** —— D1–D6 的决策材料**已升级为双向钢人版并收敛为「0 项阻塞」**（`plans/ACCOUNT-PERMISSION-DECISIONS.md` v2→v3：4 项由规范正文裁定、2 项按可逆默认自决；复核上游事实后**推翻自身 v1 的 3 处结论**，见 §7.5），**可直接开工**；其中 **§10 第 14 行已提前修完**（不依赖 D1–D6）。R-8 已不再阻塞（端点由本轮自行定形并实现）。

---

## 7. Epic C 第一步：D1–D6 决策材料 + §10 #14 预修（2026-09-22）

### 7.1 为什么不直接开工

Epic C 的三项（C-10 端点 / PermissionsTab 功能化 / §10 那 15 行缺口）**依赖 D1–D6**。第二轮复核后 **D1 已不再「落库难回头」**：组织键统一取 alias 且组织不作 RBAC 主体 ⇒ **换载体无需数据迁移**（`ACCOUNT-PERMISSION-MODEL.md` §2.3 / DECISIONS §1.5）。**唯一真正不可逆的是 D3 的删 `users` 表**，故执行顺序上把它排在主体语义改造（`sub` 化）之后并保留回滚点；其余五项均已定或可逆，**不再阻塞开工**。

### 7.2 本轮交付

| 交付 | 位置 |
| --- | --- |
| **D1–D6 决策请求**：每项给备选 / 推荐 / 理由 / 连锁改动 / **不可逆性分级** | `plans/ACCOUNT-PERMISSION-DECISIONS.md` |
| **（第四批追加）D1–D6 双向钢人版**：每项五段（事实 → 钢人 → 假钢人 → 分歧+关键变量 → 判定）+ 上游事实置信度表 + **14 处文档修正清单** | 同上（v2），复核记录见本文 §7.5 |
| **（第四批追加·2）收敛为 0 项阻塞**：回答「钢人已做为何仍需拍板」⇒ **钢人 = 论点，决策 = 论点 + 偏好**；按「文档已定 / 可逆自决 / 真需人」重分类 ⇒ **真需人 = 空**；**D1 默认由 ① 翻为 ②** | `plans/ACCOUNT-PERMISSION-DECISIONS.md` §0.1 / §7.5（v3），第二轮 6 项修正 |
| 规范侧回填：§10 第 14 行转 ✅、§11 步骤 4 标注、§12 加决策材料指针 | `hub/ACCOUNT-PERMISSION-MODEL.md` |
| 事项登记 | `hub/STORY-BACKLOG.md` B-18 |

**D3 的现状核对修正**（读实际代码所得，纠正文档「4 处同质改动」的说法）：真正需要改表的是 **2 处**（`components.owner_user` 的 UUID → 主体字符串；`component_role_bindings.user_id` 遗留列弃用）；`pipeline_approvals.approver` **已是 `string`，类型上已合规**（只需核对写入值是否 `sub`）；第 4 处（console 用户列表来源）是**来源决策**而非字段改造。**文档漏掉的第 5 处才是大头**：`users` 表本身 + `UserContext` 每请求 provision + `CurrentUserID` 返回本地 `uuid.UUID`（全仓读取点）。

### 7.3 顺手清掉的既有 §10 #14 缺口（**不等拍板**）

它修的是「路径 id 是哪种资源」，与 D1–D6 无关：

- `middleware/rbac.go`：`RequirePermission(checker, locator, Requirement{Resource, Param, Permission})`；新增 `Resource`（component / pipeline / run）、`Locator`、`PermissionChecker`（后者让拒 / 放分支**脱库可测**）。
- `internal/permission/service/locator.go`：pipeline id 反查所属 component；run id 走 **run → pipeline → component** 两跳；GORM not-found 归一为 `common.ErrResourceNotFound`（其余错误透传，**不把故障报成 404**）。
- 拒码语义固定：401 无身份 / 400 参数非 UUID / 404 反查不到 / 403 确实无权限 / **500 查询本身失败（故障 ≠ 无权限）**。
- 测试：`internal/middleware/rbac_test.go`（10 例：三种资源种类 + 5 种拒码 + 无 locator 的接线缺口）、`internal/permission/service/locator_test.go`（6 例，含「库故障不得映射成 404」）。
- 同批修正 `internal/middleware/WIRING.md` 的错误示例：它示范了同一个 bug —— `/pipelines/:pipelineId/runs` 却传 `"componentId"` 参数名，而那个参数**根本不存在**（读出来是空串 ⇒ 400）。

**gate**：`gofmt -l`（全仓干净）+ `go build ./...` + `go vet ./...` + `go test ./...` 全绿；顺带清掉 3 个**既有** gofmt 漂移（`middleware/user_context.go`、`permission/models/{binding,role}.go`，均为纯空白）。

### 7.4 下一步

**D1–D6 已闭（0 项阻塞）**，可直接开工（分级见 `plans/ACCOUNT-PERMISSION-DECISIONS.md` §0.1）。按 `ACCOUNT-PERMISSION-MODEL.md` §11 步骤 1–4 走（**已按本轮复核修订**）：realm 落地（**默认载体 ②**：预置组织组 `/org:<slug>` + 预置账号，groups mapper 已挂 ⇒ **无需开 Organizations**；**仅当**日后切 ①（federation）才需**实测组织集能否随 realm JSON 导入**）→ 表结构（**同批做 C-10**，否则 D2① 落地后无人是平台管理员）→ 中间件重排 + **D3 主体语义改造（5 处）** → D2 判定落表（**已定**，见 `ACCOUNT-PERMISSION-MODEL.md` §12）。

### 7.5 D1–D6 双向钢人复核（2026-09-22 第四批）

按仓内既有体例（`hub/DELETE-CONTRACT.md` §6.6 / `console/CONSOLE-UI-DESIGN.md` 附 B）为 D1–D6 每项补**双向钢人论证**，并**逐条复核上游事实**。复核**推翻了本文件上一版的三处结论**：

| 被推翻的说法（v1） | 复核结果 | 现结论 |
| --- | --- | --- |
| D1 推荐 ① 的两条理由：「两者都能进 realm JSON 受 git 管理」「原生能力零成本」 | 前者**未证实**（`RealmRepresentation` 有 `organizationsEnabled` / `organizations` 字段，但社区证据称 realm 导入不带 organizations）；后者**不成立**（启用会把浏览器登录流改为 identity-first） | **仍推荐 ①，但理由换成「语义隔离 + 可被独立审阅」**，两条成本写进落地清单与 gate |
| **D1 不可逆性 = 高**（绑定表要与 realm 一起迁） | 组织键若统一取 alias 字符串、且组织不作 RBAC 主体，则换载体**不需要数据迁移**，只改中间件解析 | **降为「中」**（并写入 §2.3 的硬约定） |
| D5 否决 BFF 的理由：「Cookie/BFF 需要 hub 持会话，与 §2.4.6 冲突」 | **不必然**：BFF 可以是独立薄组件，hub 仍无状态；§2.4.6 约束的是 hub | **维持 localStorage，但理由换成「本期无 XSS 威胁模型 + 不引入新部署面」**，并明确「将来重估不要再用这句错误论据」 |

**另一项实质性修正**：§12 D3 记「连锁改动 4 处」，实际为 **5 处** —— 漏掉的第 5 处（`users` 表 + `UserContext` 每请求 provision + `CurrentUserID` 签名，全仓 7 个读取点）恰好是「删表不可逆」的所在。

**文档修正共 14 项**（清单见 `plans/ACCOUNT-PERMISSION-DECISIONS.md` §7，按清单行计），分布：`hub/ACCOUNT-PERMISSION-MODEL.md` **9**、`hub/KEYCLOAK.md` **1**、`hub/STORY-BACKLOG.md` **2**、本文件 **1**、`README.md` **1**；另加 `hub/DATA-MODEL.md` 1 处指针更新（不在 14 项内）。

**本轮新增登记**：`hub/STORY-BACKLOG.md` **B-19**（复杂策略引擎需求点 —— 把 D4 判定里承诺的「登记」真正落实；此前规范提了要求、backlog 无落点）。

**未做（如实标注）**：`plans/ACCOUNT-PERMISSION-DECISIONS.md` §10 表里标「需实测」的两项（26.7.4 上 realm 导入是否带 organizations、既有 realm 开启后是否自动补 scope / 改登录流）**本轮未验** —— 本机无 PG / Docker / 集群；这两项已写成 §8 步骤 2 的 gate。**（v3 后：默认载体 ② 走 `groups` 命名约定，这两项仅在日后切 ① 时才是 gate。）**

---

## 8. Epic C 第一批（C-10 平台级端点 + `expires_at` ×2）落地结果与验证（2026-09-22）

> 规格权威：`hub/ACCOUNT-PERMISSION-MODEL.md` §5.1 / §5.3 / §7.4 / §10 #15 / §11 步骤 3；端点清单见 `hub/API-REFERENCE.md`「权限」小节。

### 8.1 交付清单

| 项 | 落地物（`software-distribution-platform-hub`） |
| --- | --- |
| C-10 · repo | `internal/permission/repository/platform_role.go` 扩 `Create` / `Update` / `Delete` / `CountBindings`；`platform_role_binding.go` 扩 `List` / `GetByID` / `Create` / `Delete` / `ExistsActive` |
| C-10 · service | 新增 `service/platform_role.go`（`PlatformRoleService`）与 `service/platform_binding.go`（`PlatformBindingService` + `NormalizeSubject`）。**窄接口**（`PlatformRoleStore` / `PlatformBindingStore` / `PlatformRoleLookup`）⇒ 全部校验分支脱库可测 |
| C-10 · handler | 新增 `handler/platform_role.go` / `platform_binding.go`；`cmd/hub/main.go` 注册 `/platform-roles`（GET/POST/GET·PUT·DELETE `:id`）与 `/platform-role-bindings`（GET/POST/DELETE `:id`） |
| `expires_at` ×2 | 两个 models 加 `ExpiresAt *time.Time`；`migrations/0011` 补列 + 索引 + §5.3 的 DDL CHECK；**`ListMatching` 两侧（platform / component）加 `expires_at IS NULL OR expires_at > now()`** |
| 种子 | `cmd/hub/conf/09_rbac_multiorg.sql` 种入 `/sdp-admin` 组 → `sdp-admin` 角色绑定（用**组**：用户绑定的主体是 `sub`，运行时才生成，写不进静态 SQL） |

### 8.2 门禁（全绿）

```
（hub）go build ./...   ✅
（hub）go vet ./...     ✅ clean
（hub）go test ./...    ✅ 全部 ok
gofmt -l（本轮触碰文件） ✅ clean
新增测试 47 例（24 顶层 + 23 子用例）  ✅
```

### 8.3 关键设计决定（逐条对应规范）

1. **到期语义必须落在 `ListMatching`**，不能只在 API 边界过滤 —— 它是鉴权中间件**唯一**的绑定解析路径。
   只过滤 API 的话，过期绑定**仍然授权**，`expires_at` 就成了装饰品。**过期行不删**（审计要能回答"曾经授过什么"）。
   反方向也钉住了：管理面 `List` **不过滤**过期，否则管理员看不到、也就无法清理。
2. **`/org:` 保留前缀禁止作绑定主体** —— 落实 D1 硬约定「**组织不作 RBAC 主体**」，
   使组织载体日后可换而**无需数据迁移**（`ACCOUNT-PERMISSION-MODEL.md` §2.3）。
3. **组主体强制前导斜杠**（本 realm `groups` mapper 为 `full.path=true`）：§5.3 的反例
   「写 `sdp-admins` 而 claim 是 `/sdp-admins` ⇒ **静默不匹配**」被变成 `400`，而不是存下一行永不生效的绑定。
4. **内置角色不可改不可删** + **角色被引用时拒删（`409 + {reasons}`）** —— 防「一次误操作清空 `sdp-admin`，
   于是所有人都进不去平台」；拒删而非留孤儿，与仓内其它删除契约同形。
5. **错误构造改为函数**（每次返回新的 `*APIError`）—— 避免复用包级单例被 `WithError` 就地改写（§6.3 记过的并发互踩）。
6. **`isSystem` 由服务端强制置 `false`** —— 调用方无法经 POST 伪造一个"不可改删"的内置角色。
7. **重复授予前置校验**（`ExistsActive`，只看**仍生效**的绑定）—— 否则一条今天过期的绑定会永久挡住重新授予。

### 8.4 如实标注：仍未做

- **平台级路由的权限守卫**：端点与其它管理面一样**裸挂**（鉴权默认关闭）。按 `ACCOUNT-PERMISSION-MODEL.md` §11，守卫随**步骤 4（中间件重排）**收口。
- **`resource_ownership` / 角色↔接口映射表 / `audit_log` / `permission_request`** 四张表未做（§11 步骤 3 的其余部分）。
- **到期回收作业**（§7.4）：查询层已过滤，但**没有**定时物理清理过期行。
- **console 侧权限管理 UI** 已做（2026-09-22 第七批）：组件级 PermissionsTab 绑定 CRUD 早已就位；本轮补齐**平台级**「用户与平台权限」页（平台角色 CRUD + 平台绑定 CRUD，消费 C-10 端点，见 §8.5）。
- **未跑真实库**：`migrations/0011` 需手跑 psql（AutoMigrate 会加列 / 建索引；**CHECK 约束只在迁移里**）。
- **种子的前置**：`/sdp-admin` 组需先在 realm 里建出来（当前 realm **无任何组** ⇒ `groups` claim 为空，见 §5.3）。

### 8.5 Epic C 第二批（console 平台级权限管理 UI）落地结果与验证（2026-09-22 第七批）

> 背景：C-10 后端端点（第六批）落地后，console 无任何 client / UI 消费它 ——
> `PlatformAdminView.vue` 仍是只读列出 users + V1 roles，「平台级授权无出路」（日志 09:00 记录）。本轮补齐。

#### 8.5.1 交付清单
| 层 | 落地物（`software-distribution-platform-console/src/`） |
| --- | --- |
| API | `api/permission.ts` 新增 `PlatformRole` / `PlatformRoleBinding` 类型 + `platformRoles`（`createCrud` + `list`）+ `platformBindings`（list/create/remove） |
| 纯逻辑 | `utils/permission.ts`（零 import）：`parseActions`（权限点文本 → 数组）、`formatExpiryISO`（datetime-local → RFC3339，防 Go time.Time 反序列化 400）、`subjectLabel` |
| 页面 | `views/PlatformAdminView.vue` 权限段重写为三块：平台角色（CRUD，内置角色禁删、引用时 409 显示 reasons）/ 平台绑定（CRUD，user 选择器 + group 自由文本 + 可选过期）/ 用户（只读，绑定选择器来源） |

#### 8.5.2 门禁（全绿）
```
vue-tsc --noEmit            ✅
vite build                  ✅（PlatformAdminView 11.62 kB 分包）
pnpm test:platform-perm     ✅ 10/10（新增）
pnpm test                   ✅ 全量五套冒烟无回归
```

#### 8.5.3 如实标注
- 平台级路由**仍裸挂**（鉴权默认关闭），守卫随 §11 步骤 4 收口。
- 组主体须带前导斜杠（full.path），UI 已提示；但 realm 当前**无组**，故 group 绑定只能手填组名，无法从目录选。
- 过期回收作业 / `resource_ownership` / `audit_log` / `permission_request` 四表 / D3 删 `users` 表 仍未做（见下一步）。

## 9. Epic C 第三批（权限模型后端收口：四表 + 审计 + D3 可逆部分）落地结果与验证（2026-09-22 第八批）

> 规格权威：`hub/ACCOUNT-PERMISSION-MODEL.md` §3 / §4 / §5.1③ / §6 / §7.2 / §11 步骤 3–7；D1–D6 见 `plans/ACCOUNT-PERMISSION-DECISIONS.md`。

### 9.1 交付清单（`software-distribution-platform-hub`）

| 项 | 落地物 |
| --- | --- |
| §3 资源归属表 | `internal/permission/models/resource_ownership.go`（`IsAllowed` 纯逻辑 + JSON share 集）、`repository/resource_ownership.go`、`service/resource_ownership.go`、`handler/resource_ownership.go` |
| §5.1③ 角色→接口映射 | `models/role_api_mapping.go`、`repository/role_api_mapping.go`、`service/role_api_mapping.go`（`ActionsForRole` / `SetActions` / `SyncFromRoles`）、`handler/role_api_mapping.go`；**并注入 `BindingService`**：生效动作集 = 角色 `actions` JSON ∪ 映射表（窄接口 `RoleActionLookup`，nil 安全） |
| §6 审计 | `models/audit_log.go`、`repository/audit_log.go`、`service/audit.go`（`AuditReporter`，best-effort 降级为告警）、`middleware/audit.go`（**只记写操作**，业务零手写） |
| §7.2 审批流 | `models/permission_request.go`、`repository/permission_request.go`、`service/permission_request.go`（状态机 + `GrantWriter` 钩子）、`service/grant_writer.go`（审批通过 → 写绑定带 `expires_at`）、`handler/permission_request.go` |
| §7.4 到期回收作业 | `service/reclaim.go`（`BindingReaper.ReapOnce` / `Run`）+ 两个 repo 的 `DeleteExpired` + `config.BindingReapInterval`（env `BINDING_REAP_INTERVAL`，默认 1h；≤0 关闭）+ main.go 后台 goroutine |
| §8 #12 `/api/userinfo` | `handler/userinfo.go`（subject / username / groups / **orgs**（`/org:` 载体解析）/ roles） |
| §11 步骤 4 platform 守卫 | `middleware/rbac.go` 新增 `PlatformPermissionChecker` + `RequirePlatformPermission`；`/platform-roles`、`/platform-role-bindings`、`/resource-ownership`、`/role-api-mappings`、`/permission-requests` 在**开启鉴权后**要求平台级 `user:manage`（鉴权关闭仍裸挂，与其余管理面一致） |
| **D3 主体语义（可逆部分）** | `middleware/user_context.go` 新增 `CurrentSubject`（token `sub`，dev 为 `dev`）；`RequirePermission` / `PermissionChecker` / `BindingService.HasPermission` / 两个 `ListMatching` 改为按 **subject** 匹配；**V1 `user_id` 遗留分支保留**（迁移窗口不破）；`component.owner_user` 的 owner override 仍按本地 UUID |
| 迁移 | `migrations/0012_permission_model_tables.sql`（四表 + 索引 + CHECK，幂等；AutoMigrate 亦建表） |

### 9.2 门禁（全绿）
```
（hub）go build ./...   ✅
（hub）go vet ./...     ✅ clean
（hub）go test ./...    ✅ 全部 ok
gofmt -l（本轮触碰文件） ✅ clean
```
新增测试：ownership `IsAllowed` / share 集 3 例 · `OrgsFromGroups` 6 例 · 审计中间件（写才记 / 只记写 / 状态码 / nil sink 安全）· 审批状态机 6 例（含 grant 失败上抛）· 回收谓词渲染 2 例；既有 rbac / dryrun 测试随签名同步更新。

### 9.3 如实标注（仍未做）
- ~~**D3 唯一不可逆项 = 删 `users` 表**~~ → ✅ **已执行（2026-09-23，见 §14）**：第八批只做了可逆的 `sub` 主体语义；本批在确认 scope + 备份后完成删表（迁移 `0015`）。
- ~~**`resource_ownership` 未在鉴权链强制生效**~~ → ✅ **已接（2026-09-22 第十一批，见 §12）**：`middleware/RequireResourceOwnership` + `CurrentOrgs`（`/org:<slug>` → `orgs.id`）。仍未建的是 **realm 侧的组织组本身**（DB 驱动，须按库逐条建）。
- ~~**`component.owner_user` 仍按本地 UUID 做 owner override**~~ → ✅ **已切 `sub`（2026-09-23，见 §14）**：`owner_user` → `owner_sub`（text），owner override 改为与请求 `sub` 直接比对。
- **Casbin（D4）** 仍延后（已登记 B-19）。
- **未跑真实库**：`migrations/0012` 与 0011 均需手跑 psql；种子 `/sdp-admin` 组需先在 realm 建立。
- **审计无保留期 / 归档**：单表 append，长期增长需后续 GC（与 B-16 对账同族）。

### 下一步（第九批）

Epic C 后端已收口到「可逆边界」。剩余：① ~~**D3 删 `users` 表**~~ → ✅ **已执行（2026-09-23，§14）**；② realm 侧 `/org:<slug>` 组 + 组织 claim 落中间件（解 `resource_ownership` 强制点）；③ Casbin（D4，条件触发）。**转向 Epic D / E**：runner 执行后端（Epic D，已见 §10）与流水线版本历史/对比/回滚（C-09）、制品孤儿对账（B-16 对账）。

---

## 10. Epic D 落地结果与验证（2026-09-22）

> 全部 10 项（B-02 / B-04 / B-05 / B-06 / B-08 / B-09 / C-03 / C-05 / C-06 / C-07 / C-13）在 `software-distribution-platform-runner` 模块实现，遵循仓库既有模式（共享 `api/v1alpha1` 线协议、controller-runtime 纯函数调度核心、fake client 单测）。

### 10.1 交付清单

| 编号 | 落地物（`software-distribution-platform-runner`） |
| --- | --- |
| B-02 | `pkg/logstream`（行分块 + `Sender` 接口）、`TaskRunReconciler.maybeStreamLogs` 起 goroutine 抓 Pod 日志经 `connector.Send(MessageLogChunk, …)`；受 `metrics.LogStreamingEnabled`（`SDP_LOG_STREAMING` 开关）控制 |
| B-04 | `RolloutReconciler.ensureCanaryIngress`（`networkingv1.Ingress` + `nginx.ingress.kubernetes.io/canary-weight` 注解，随步进阶更新）+ `Owns(&networkingv1.Ingress{})`；仅 `TrafficRouting==IngressCanary` 且 `SDP_CANARY_INGRESS` 开时生效 |
| B-05 | `pkg/health`（`HTTPProbe` / `PrometheusQueryOK` / 纯函数 `ThresholdMet`）；`canary.Evaluate` 增 `healthy` 入参，探针失败计入 `ConsecutiveFailures` 并在超阈值（`FailureThreshold`）时回滚 |
| B-06 | `RolloutSpec.Replicas *int32`（CRD 类型 + deepcopy 更新）；`resolveTotalReplicas(spec, live)` 优先级：spec → 在线 Deployment `spec.replicas` → 默认 2 |
| B-08 | 单测：`canary/engine_test.go`（缩放/等健康/探针失败计数/回滚/完成）、`health/health_test.go`（阈值+HTTP 探针 httptest）、`logstream/logstream_test.go`（分块边界）、`dispatch/snapshot_test.go` + `rerun_handler_test.go`（级联下游+重置）、`controller/pipelinerun_controller_test.go`（串行+resync）、`controller/rollout_controller_test.go`（副本解析）、`api/v1alpha1/pipelinerun_types_test.go`（环境模型） |
| B-09 | `pkg/metrics`（Prometheus 计数器/仪表 + `Alert` 告警，`metrics.Register()` 在 main 调用）；降级开关 `SDP_LOG_STREAMING` / `SDP_CANARY_INGRESS` / `SDP_ALERTING` |
| C-03 | `ApplyPipelineRunPayload.PublishVersion` + `dispatch.SnapshotSpec`（内容哈希，顺序无关、字段敏感）；Apply 时落 `sdp.io/spec-snapshot` / `sdp.io/publish-version` 注解 |
| C-05 | `connector.OnConnect` 钩子 + `controller.ResyncAll`（重连后回灌在途 PipelineRun 状态，仅非终态、仅本 target） |
| C-06 | `PipelineTaskSpec.ExecutionMode`（`Parallel`/`Serial`）+ `findRunnableTasks` 串行判定（`serialBlocked`：同阶段 Serial 任务须前序 Succeeded） |
| C-07 | `MessageRerunTask` / `RerunTaskPayload` + `dispatch.RerunHandler`：重置单任务状态、删其 Job/Rollout、级联删下游 TaskRun（`DownstreamTasks` 纯函数，BFS 反向依赖边） |
| C-13 | `TaskTypeTest`（按 Build 同路执行 Job）+ `EnvironmentType` 六类（dev/test/staging/prod/canary/bluegreen）及 `IsValidEnvironment` 校验 |

### 10.2 门禁（全绿）

| Gate | 命令 | 结果 |
| --- | --- | --- |
| 构建 | `go build ./...` | ✅ |
| 静态检查 | `go vet ./...` | ✅ clean |
| 单测 | `go test ./...` | ✅ 全绿（新增 30+ 例） |
| 格式 | `gofmt -l`（本轮触碰文件） | ✅ clean |

### 10.3 明确未做 / 如实标注

- **e2e 未跑**：无运行集群 / kind / Postgres，所有 K8s 交互（日志抓取、Ingress 创建、副本读真实 Deployment、探针真实命中）仅经编译 + 纯逻辑单测 + fake client 验证，未做端到端联调。
- **IngressCanary 为 M1 降级**：canary Ingress 资源已建并随权重更新，但真实百分比路由仍需配套主 Ingress 与相同 host（ingress-nginx 约束），副本切分仍是无主 Ingress 时的实际分流手段。
- **PrometheusQuery 端点**：`RolloutReconciler.PrometheusEndpoint` 由 `cmd/runner/main.go` 从环境注入；未配置时探针 fail-safe 为「保持当前权重不前进」，不盲进。
- **未改 hub/console**：本批仅限 runner 模块，hub 侧 `MessageRerunTask` 下发、C-13 环境模型在 hub 的落库为后续项。
- **CRD YAML 未重新生成**：新增字段（`RolloutSpec.replicas`、`PipelineTaskSpec.executionMode`、`PipelineRunSpec`/payload 字段）已更新 `zz_generated.deepcopy.go`，但 `config/crd/bases/*.yaml` 与 `build/runner/charts/.../crds/` 需 `controller-gen` 重新生成（本机未跑，属文档已声明的手动步骤）。

---

## 11. Epic E 落地结果与验证（2026-09-22 第十批）

> 范围：`software-distribution-platform-hub`（Go）+ `software-distribution-platform-console`（Vue 3 + TS）。
> 权威规格：`hub/STORY-BACKLOG.md` B-11 / B-16 / C-09、`hub/API-REFERENCE.md`、`console/CONSOLE-UI-DESIGN.md` §7.10、`hub/DATA-MODEL.md` §7.3。
> 原则：先读真实代码再动手；**不臆造**端点 / 路径 / 字段；单元测试走仓内既有手法（hub = 窄接口 + 表驱动 + DryRun 钉 DDL；console = `scripts/*-smoke.mjs` 纯逻辑断言）。

### 11.1 B-11 主规格细化（5 个子项逐条结清）

| 子项 | 结论 | 落地物 |
| --- | --- | --- |
| 审批超时 | ✅ **新写** | `internal/run/service/approval_timeout.go`：纯谓词 `ApprovalExpired` / `HasApprovalGate`、`SweepApprovalTimeouts(ctx, now)` / `RunApprovalTimeouts(ctx, interval)`；`run/repository/approval.go` 增 `ListPending`；`config.ApprovalTimeoutInterval`（env `APPROVAL_TIMEOUT_INTERVAL`，默认 60s）；main.go 后台 goroutine |
| 生产强审批 | ✅ **新写** | `internal/run/service/production_guard.go`：`ProductionPolicy` 窄接口 + `enforceProductionApproval`（**fail-closed**，错误 `ERR.08409005`）；`environment/repository/environment.go` 增 `ProductionTargets(targetIDs)` 批量判定；`Trigger` / `triggerFanout` 在 `buildSpec` 之后、建 Run 之前校验 |
| 产物签名下载 | ✅ **核对后确认既有实现已完整**（本轮未改代码） | hub：`storage.Client.PresignDownload`（S3 presigned / Local HMAC 签名回源）+ `ArtifactService.DownloadURL` + `GET /artifacts/:id/download`；console：`artifactApi.getDownloadUrl` → `ArtifactsTab` 「下载」。**仅 `hub/user-stories.md` 的 ⬜ 是过时标记，已更正** |
| 版本对比 | ✅ **由 C-09 一并交付** | 见 §11.2（`GET /pipelines/:id/versions/:version/diff?against=`） |
| 自定义角色 | ✅ **补齐组件级缺口** | 平台级插件早由 C-10 落地；本轮补组件级：`permission/service/component_role.go`（`ComponentRoleService`）+ `repository/component_role.go`（`Create`/`Update`/`Delete`/`GetByNameInOrg`/`CountBindings`）+ `handler/component_role.go`（**读挂裸 api、写挂 platformGroup**）+ `models/component_role.go` 两条 partial unique index 标签 + `migrations/0014` |

**关键设计决定**
- **自定义角色唯一键 = (org_id, name)，内置角色名全局唯一**，且必须是**两条 partial index**。写成 `unique (org_id, name)` 一条对内置角色（`org_id is null`）**完全无效** —— Postgres 的 unique 里 NULL 互不相等，可插入任意多条 `(null,'component-admin')`，而 `GetByName("component-admin")` 正是 owner 引导与绑定校验的解析入口，二义会随查询计划漂移。由 DryRun 测试钉住。
- **组件级角色的读写在两个中间件组**：读留在裸 `api`（console 角色选择器要它），写挂 `platformGroup`（开启鉴权后要求平台级 `user:manage`）。**能改角色 = 能给自己加权限**，写端点不能只靠"已登录"。由 `platform_routes_test.go` 反向断言"写端点不得出现在读组"。
- **生产强审批 fail-closed**：目标环境类型解析不出来时**拒绝触发**，而不是放行 —— 放行等于静默绕过审批。
- **审批超时的顺序**：先派发 runner 拒绝、再记 hub 侧关闭（状态 `Cancelled`）；目标离线则**顺延**，不写坏状态。

### 11.2 C-09 流水线版本历史 / 对比 / 回滚

| 层 | 落地物 |
| --- | --- |
| hub 模型 | `pipeline/models/version.go`：`Snapshot`/`SnapshotStage`/`SnapshotTask` + `BuildSnapshot`/`DecodeSnapshot`/`CanonicalJSON` + 纯 diff `DiffSnapshots`（**按 name 而非 row id 对齐** —— id 跨版本必然变化）+ `SnapshotDiff`/`DiffSummary` |
| hub 仓储 | `PipelineVersionRepository` 增 `GetByVersion` / `Latest` / `ListByPipelineID(pipelineID, limit)` |
| hub 服务 | `pipeline/service/version.go`：`Publish`（**唯一**的版本号推进点；body 逐字相同则去重 —— console 一次 [保存] 会发多条 no-op PUT）、`List`/`Get`/`Compare`/`Rollback`/`clearStructure`；窄接口 `VersionPublisher` / `VersionRepo` / `VersionPipelineStore` / `VersionStageStore` / `VersionTaskStore` |
| hub 挂钩 | `pipeline.go` `Update` 委托 `versions.Publish`；`stage.go`/`task_template.go` 增 `SetVersionPublisher` + `publishVersion`（best-effort，结构改动即留档） |
| hub 端点 | `pipeline/handler/version.go`：`GET /pipelines/:id/versions`、`GET .../versions/:version`、`GET .../versions/:version/diff?against=N`、`POST .../versions/:version/rollback`。diff 挂 `:version` 之下而非 `compare?from&to=`：后者会让 gin 同层出现静态段与参数段（路由树冲突） |
| 迁移 | `migrations/0013_pipeline_versions.sql`（`unique (pipeline_id, version)` + 审计索引） |
| console | `api/pipeline.ts` 4 个方法；`utils/pipeline.ts` §6（`versionLabel`/`changeLabel`/`changeClass`/`fieldLabel`/`showFieldValue`/`versionOrigin`/`identicalMark`/`summarizeDiff`/`diffRows`/`isNoopRollback`/`rollbackWarning`）；`components/PipelineVersionPanel.vue`（对比选择器 + 差异表 + 版本列表 + 结构预览 + 回滚二次确认）；`PipelineEditorView.vue` 挂载 + 「版本历史」入口 + `@rolled-back` 重载 |

**关键设计决定**
- **回滚 = 结构回填 + 追加新版本，绝不重写历史**：hub 不删旧行、不改元信息（name/kind/description 受 partial unique index 约束，改名回滚会撞键）。文案据实写"结构替换、元信息不受影响、旧版本不会删除"。
- **diff 判定全在 hub，前端零判断**：前端不自己比两份快照（两份实现必然漂移），`diffRows` 只做呈现、且**不重排**（后端已按名称稳定排序），由冒烟测试反向断言。

### 11.3 B-16(对账) Artifact 孤儿对象对账（周期性、仅报告）

| 层 | 落地物 |
| --- | --- |
| storage | `storage.ObjectInfo` + **`Enumerator` 独立接口**（`ListObjects(prefix, limit) (objs, truncated, err)`）；`s3.go` / `local.go` 各自实现（local 走 `WalkDir`、跳过 `.part`） |
| 仓储 | `artifact/repository` 增 `ListStorageKeys()`（Pluck，有序） |
| 服务 | `artifact/service/reconcile.go`：`ArtifactReconciler.RunOnce(now)` / `Run(ctx, interval)`，纯 `DiffStorageKeys`（报告 DB 有行无对象 / 有对象无行），`ReconciliationReport`（`Clean()`）、`StorageKeySource` |
| 配置 | `config.ArtifactReconcileInterval`（env `ARTIFACT_RECONCILE_INTERVAL`，**默认 0 = 关闭**）、`ArtifactReconcilePrefix` |
| 装配 | `cmd/hub/main.go` 以**类型断言**接入：驱动实现 `Enumerator` 才起作业，否则如实告警"未启用" |

**关键设计决定**
- **只报告，绝不删除**：孤儿可能来自正在进行的上传 / 尚未落库的写入，自动 GC 会删掉活数据。
- **`Enumerator` 与 `Client` 分离**（接口隔离）：列举整桶是低频运维动作且成本随桶增长，不该让每个驱动都被迫实现；更重要的是**不能假装支持**——驱动不支持时若返回空列表，"0 个孤儿"会与"根本查不了"混淆。调用方用类型断言判断，不支持就如实报"跳过"。另有结构性测试确保 `Enumerator` 无法满足 `Client`。
- **默认关闭、开启即日报**：对账是运维动作，不该在所有人开发时随进程空转。

### 11.4 门禁（全绿）

```
（hub）      go build ./...            ✅
（hub）      go vet ./...              ✅ clean
（hub）      go test ./...             ✅ 16 个包全部 ok
（hub）      gofmt -l（本轮触碰文件）   ✅ clean
（console）  pnpm build               ✅ vue-tsc --noEmit + vite build
（console）  pnpm test                ✅ 5 套冒烟全绿：16 / 25 / 63 / 22 / 10
```

新增测试：版本 diff 纯逻辑 8 例 · 版本服务 9 例（发布/去重/结构变更/列表/取单/对比/回滚）· 版本 DDL DryRun 1 例 · 对账纯 diff 表驱动 + 只读结构断言 + 真实 Local 驱动 1 组 · 审批超时谓词/编排 + 生产强审批守卫 ~15 例 · 组件角色服务 9 例 + 路由读写分离 1 例 + 角色 DDL DryRun 1 例 · console 版本/回滚/B-11 拒绝呈现共 23 条新断言（`pipeline-editor-smoke.mjs` 由 40 → **63**）。

### 11.5 如实标注（仍未做 / 未跑）

- ⛔ **B-07 端到端验证仍未跑**：本机 `kind` 未安装、`kubectl` 无 current-context、无可用集群与 Postgres ⇒ 一切"跨进程 / 跨集群"的链路（触发→runner→Pod→日志回流、制品上传下载真链路、审批超时真派发）**只经编译 + 单测验证，未做端到端联调**。**未伪造任何 e2e 结果**。跑法见 `plans/E2E-VERIFY-PLAN.md` + `plans/e2e-smoke.sh`。
- **未跑真实库**：`migrations/0013` / `0014` 与其余迁移同路径，需手跑 psql；`0014` 若库中已有重名角色会报 duplicate key（文件内附查重 SQL 与处置步骤）。AutoMigrate 亦会建同等索引，两条建库路径已收敛。
- **对账默认关闭、且依赖驱动实现 `Enumerator`**：`S3` / `Local` 已实现；未实现或未配置对象存储时，作业**不会**报"干净"，而是告警"未启用"，避免把"查不了"读成"没问题"。
- **生产强审批依赖环境的 `EnvType` 标注**：判定依据是环境的 production 类型；未标注为生产的环境不会被拦（这是数据问题，不是代码问题）。
- **自定义角色 console UI 未做**：hub 侧 CRUD 端点已完整可用，管理界面留待 console 排期（与 §8.5 平台级权限页不是同一处）。
- **组件级自定义角色的生效范围**：~~`resource_ownership` 未在鉴权链强制生效这一前提不变~~→ **该前提已于第十一批解除（见 §12）**：归属强制点已接。仍缺的是 realm 侧组织组（DB 驱动）。自定义角色本身已可被绑定消费。

---

## 12. Epic C 收尾（组织 claim + 资源归属强制点）落地结果与验证（2026-09-22 第十一批）

> 规格权威：`hub/ACCOUNT-PERMISSION-MODEL.md` §2.3 / §3 / §4 / §5.3 / §11 步骤 2–4。
> 本批把 §4 中间件链的**第 3 步（鉴权 a：资源归属）**真正接上，并补齐它唯一的输入缺口 —— realm 侧的组载体。

### 12.1 交付清单

| 层 | 落地物 |
| --- | --- |
| 组织解析 | `middleware/user_context.go`：`UserContext` 用 `service.OrgsFromGroups` 把 `groups` claim 中的 `/org:<slug>` 解析进 `contextKeyOrgs`，新增 `CurrentOrgs(c)`（dev 模式**显式置空** —— 语义是「看过、没有」，而不是「中间件没跑」） |
| 归属判定 | `permission/service/resource_ownership.go`：`OwnershipStore` **窄接口**（构造签名由具体 repo 改为接口，`main.go` 零改动 —— Go 隐式满足）+ `AllowsComponent(componentID, orgIDs)` 实现 §3 判定式全表 |
| 归属门 | `middleware/ownership.go`：`OwnershipChecker` / `OrgAliasResolver` 两个窄接口 + `RequireResourceOwnership`；别名→`orgs.id` 解析留在中间件（`resolveOrgIDs`：未知别名丢弃、nil resolver 不算错） |
| 别名解析 | `org/repository/org.go`：`IDsBySlugs` —— `/org:<slug>` 与 `resource_ownership` 的 uuid 列之间**唯一**的连接点，一条 `slug IN (...)` 批量解析 |
| 装配 | `cmd/hub/main.go` 的 `wrap()`：组件作用域路由现在是**两层**（a 归属 → b RBAC），共用同一个 `Requirement`；`auth == nil`（dev）仍全裸挂 |
| realm 载体 | realm JSON 增**顶层 `groups`**（`/sdp-admin`）且预置用户 `admin` 已入组 —— 关掉 `09_rbac_multiorg.sql` 里「未完成时本行不生效」的前置警告 |
| 迁移 | 无新增表（复用 `0012` 的 `resource_ownership`） |

### 12.2 关键设计决定（含双向钢人）

**① 归属判定的空值语义（本批唯一真正有争议的点）**

- **方案 A（严格 fail-closed）**：`token.组织 ∈ {owner} ∪ allowed` 不成立即 403，**包括请求不带任何组织时**。
- **方案 B（无组织即放行）**：请求不带组织 ⇒ 本段无输入 ⇒ 放行，交给 b 段 RBAC 细判。
- **钢人 A**：§3 写的就是集合判定，没有「缺省放行」这一档。资源一旦登记了归属，任何不在集合内的请求都该拒；若登记之后还能凭「我没有组织」通过，等于归属声明可以被绕过。
- **钢人 B**：组织载体是**增量配置**（realm 至今零个 `/org:` 组）。把「我还没配组织」读成「你不许访问」，会让全部尚未纳入组织体系的用户突然 403，而错误信息只有一句 403，排查成本极高。
- **裁定 = A 的严格性 + B 的不误伤，用「资源是否已登记归属」这一维度切开**：
  - **未登记归属的资源 → 放行**（当前**全部**资源都在此列 ⇒ 上线零回归，b 段 RBAC 照常生效）；
  - **已登记归属的资源 → 严格**：组织不相交 **或** 请求不带组织，都拒。
  - 于是「登记归属」成为一个**显式的收紧动作**：不需要开关、不需要迁移窗口、也不会静默放宽。
- **配套：两种 403 必须可区分**。归属拒用独立错误 `errOutOfOrg`（`“resource is not owned by any of the subject's organizations”`），不与 RBAC 的 `errForbidden` 混用 —— 两者修法完全不同（改归属行 vs 改角色绑定），共用一句话会把排查者送去查错的表。

**② 归属只在组件粒度登记**：流水线 / 运行**继承**其组件的归属。`wrap()` 已把路径 id 经 `permLocator` 解析到 owning component，两段守卫复用它 ⇒ 运维登记一次，而不是每个 pipeline 一行。

**③ dev 模式整体不装**：`auth == nil` 时 `wrap()` 直接返回裸 handler，与 `RequirePermission`、平台级守卫完全一致 —— 逃生口只有一个，且是既有的那个。

### 12.3 门禁（全绿）

```
（hub）go build ./...   ✅
（hub）go vet ./...     ✅ clean
（hub）go test ./...    ✅ 17 个包全部 ok
（hub）gofmt -l         ✅ clean
```

新增测试：`resource_ownership_test.go` 8 例（含**未登记即放行**与**已登记+无组织即拒**两条隐含情形、`uuid.Nil` 不当通配、非 `component` 类型的行不被误读为组件归属）· `ownership_test.go` 11 例（别名解析 + 未知别名丢弃、无组织时不查解析器、nil 解析器不算错、pipeline/run 走 owning component、403 文案指向归属、解析器失败 500 且不再查归属、无 locator 500）· `org_slug_test.go` 2 例（DryRun 钉 SQL 形状：一条 `slug IN` 查询 + `deleted_at IS NULL`；空别名零查询）。

### 12.4 如实标注（仍未做 / 未跑）

- ⛔ **realm 侧组织组 `/org:<slug>` 仍未建**：本批只补了 **RBAC 维度**的组 `/sdp-admin`。组织组要**按库里的 orgs 逐条建**（DB 驱动，写不进静态 realm JSON），故仍是待办；在它到位前 `CurrentOrgs` 恒为空 ⇒ 归属门对**已登记归属**的资源一律拒（这是设计意图，不是缺陷）。
- ⛔ **未跑真实库 / 真实 Keycloak**：`--import-realm` 只对**新建** realm 生效，既有安装需手工建组加人；本批两组新测试均为 DryRun / 纯逻辑，未经真实 Postgres 与真实 token 验证。
- **`resource_ownership` 的 CRUD 仍只挂在平台级守卫下**（`RequirePlatformPermission`），未按 org 细分。
- ~~**D3 删 `users` 表** 仍为唯一不可逆待办（见 §9.3）~~ → ✅ **已执行（2026-09-23，见 §14）**。

---

## 13. 环境服务可测化 + 顺带修掉一个真实缺陷（2026-09-22 第十二批）

> 规格权威：`console/CONSOLE-UI-DESIGN.md` §7.12.5（连接测试清单）/ §7.12.6（环境状态机）+ `hub/DELETE-CONTRACT.md` §6.4 #8（删环境只告警不阻断）。
> 动因：§3.1 遗留的「`EnvironmentService.Delete` 覆盖计数无单测」。要给它写单测，前提是服务能脱库 —— 于是本批先窄接口化，再补测试，**测试立刻挖出一个生产缺陷**。

### 13.1 交付清单（`software-distribution-platform-hub`）

| 项 | 落地物 |
| --- | --- |
| 窄接口化 | `internal/environment/service/environment.go`：新增 `EnvironmentStore`（`Create`/`GetByID`/`FindByComponentID`/`Update`/`Delete`）与 `TargetLookup`（`GetByID`）；`NewEnvironmentService` 形参由具体 repo 改为接口。两个 `*repository.X` **隐式满足** ⇒ **`cmd/hub/main.go` 零改动** |
| 新增测试 | `internal/environment/service/environment_test.go`（18 例）：Delete 审计不阻断 4 例（有覆盖 / 计数失败 / 未接计数器 / 存储失败）· Create 状态派生 · Update key 字段降级 **5 子例**（target / namespace / access / kubeCredRef / sshSecretRef 各清 `lastTestAt` + `lastTestResult`）· Update 非 key 字段保持已验证 · 旧行缺失不 panic · `Test()` 报告与落库 5 例（新鲜心跳 → verified、离线 → failed、心跳过期 30min 视为离线、目标查不到按失败项而非 500、环境不存在报错）· `deriveStatus` 8 子例 · `keyFieldChanged` 2 例 |

### 13.2 顺带修掉一个真实缺陷：`report.Status` 恒为空

**发现方式**：给 `Test()` 写断言时期望 `report.Status == verified`，实测得到 `""`。

**根因**：`EnvironmentService.Test` 把判定结果只写进 `env.Status`，**从未写进 `report.Status`**；且 `report.TestedAt` 在 `json.Marshal(report)` **之后**才赋值 ⇒ 归档进 `last_test_result` 的快照里既没有 `status` 也没有 `testedAt`。

**影响面（用户可见）**：console `components/environment/ConnectionTest.vue` 直接读 `report.status` 决定徽标样式（verified / failed / 其他→pending）与提示文案、读 `report.testedAt` 渲染「最近测试：」。所以该缺陷表现为**连接测试面板徽标无状态、时间显示为空**，而库里 `environments.status` 却是对的 —— 典型的「写对了库、答错了人」。`EnvAccessPanel.vue` 还把返回的 report 原文 `JSON.stringify` 存回 `lastTestResult`，于是空状态被一并写进前端草稿。

**修法**：判定结果先写进 `report.Status`、再序列化、最后落库；使「调用方拿到的对象」与「归档快照」是同一个对象（`testedAt` 同步前移）。

**为何值得记**：这是本批唯一由「补测试」直接挖出的生产缺陷。该分支此前没有测试，原因正是服务依赖具体 repo、无法脱库 —— 把依赖换成窄接口是**发现它的前提**，不是顺带的美化。

### 13.3 门禁（全绿）

```
（hub）go build ./...   ✅
（hub）go vet ./...     ✅ clean
（hub）go test ./...    ✅ 18 个包全部 ok
（hub）gofmt -l         ✅ clean
```

### 13.4 如实标注（仍未做 / 未跑）

- **未跑真实库 / 未打真实 HTTP**：全部为脱库单测，`GET /environments/:id/test` 的响应体形状由服务层单测间接保证，未经真实请求验证。
- **`ListByComponent` 未补测试**（本批聚焦 Delete / Update / Test 三条分支）。
- **console 侧无改动**：缺陷在 hub 响应体，前端本就是按契约读 `status`/`testedAt`。
- 既有的 **Artifact GC**、**§6.4 域内级联软删**、**run 触发路径走 pipeline service 校验** 仍未做（见 §3.1 / §9.3）；~~**D3 删 `users` 表**~~ → ✅ **已执行，见 §14**。

---

## 14. D3 全量执行：删 `users` 表 + 主体语义收口（2026-09-23 第十四批）

> 规格权威：`hub/ACCOUNT-PERMISSION-MODEL.md` §2.2 / §5.3 / §12 D3；执行清单 `plans/ACCOUNT-PERMISSION-DECISIONS.md` §3.5。
> **这是本仓第一份「删列 + 删表」的变更**（迁移 `0015`），也是 D3 里唯一不可逆的一步 —— 本轮由用户明确拍板执行。

### 14.1 交付清单

| 处 | 落地物 |
| --- | --- |
| ➎ `users` 表 + provision + `CurrentUserID` | 删 `permission/{models,repository,service,handler}/user.go`；`UserContext()` 改为**纯解析**（无库、无 `GetOrProvisionByKeycloakID`、去掉 `contextKeyUserID`）；`CurrentUserID` 删除，**原 7 个读取点**（component ×1 / config ×2 / pipeline ×1 / run ×2 / rbac ×1）全部改用 `CurrentSubject`；`db.go` AutoMigrate 去掉 `User` |
| ① owner | `components.owner_user *uuid.UUID` → **`owner_sub *string`**（存 token `sub`）：`component/handler` 落 owner 改 `CurrentSubject`；`component/service.bindOwner` 直接用 `*OwnerSub`；`BindingService.ownerActions` 的 owner override 改为**字符串相等** |
| ② V1 遗留列 | `component_role_bindings.user_id` / `role_id` 删列 + V1 解析分支移除；`BindingService` 不再依赖 V1 `roles` 仓储；`bindingRepo.GetByComponentAndUser`（只服务 V1）删除；DryRun 测试改成**反向断言** —— `user_id` 不得再出现在生成的 SQL 里 |
| ③ approver / operator | approver（审批）、operator（rollout 控制）、`pipeline.CreatedBy` 一律改取 `sub` |
| 附带（规范没列的同类写入点） | `component_configs.created_by` / `updated_by`、`component_config_history.changed_by`、`component_role_bindings.granted_by` 原本是 `uuid` 且唯一写入源是 `CurrentUserID` —— 一并改为 `*string`（subject），否则删表后这几处**没有值可写** |
| ④ console | 去掉 `GET /users` / `permissionApi.users`；授权表单改为「**下拉已绑定主体（绑定表派生）+ 手输 `sub` / 组路径**」；`utils/permission.ts` 新增纯函数 `knownSubjects` / `validateSubjectInput` / `subjectInputHint` / `failMsg`；「用户」只读表改为「**已绑定主体**」表 |
| 迁移 | `migrations/0015_d3_drop_users_and_legacy_columns.sql`：**先**回填（`owner_sub` ← `users.keycloak_id`，作者类列同法）**→** 对映射不到的残留显式置空 + `RAISE WARNING` **→** 再删列删表；整份包在一个事务里；幂等 |
| 种子 | `cmd/hub/conf/06_permissions.sql` 去掉 `users` 插入，绑定改走 §7（`subject_type`/`subject_id` + `component_role_id`）；`conf/README.md` 同步 |

### 14.2 门禁（全绿）

```
（hub）go build ./...  ✅    go vet ./...  ✅ clean    go test ./...  ✅ 18 包 ok    gofmt -l  ✅ clean
（console）pnpm build ✅（vue-tsc + vite）    pnpm test ✅ 16/16 · 25/25 · 63/63 · 22/22 · 21/21
```

权限侧冒烟从 10 例扩到 **21 例**：新增 `knownSubjects` 去重/排序、`validateSubjectInput`（组必须带前导斜杠 —— §5.3 的真实踩坑点）、`subjectInputHint`（非阻塞提醒）、`failMsg`（409 `reasons` 优先）；并把 `subjectLabel` 的断言从「会补全成 `张三（z@sdp.io）`」改成「**只显示真值，不截断、不补名**」。

### 14.3 双向钢人（本批唯一有争议的取舍）

**① 手输主体会不会把授权闭环打断？**（决策文档「假钢人第 1 条」正是最硬的反驳）
删表后 hub 说不出「系统里有哪些人」，控制台选不到新人 ⇒ **新主体无法被授权**。
- **裁定**：取 (b′)，并承认反驳成立**但前提可拆** —— 它成立的前提是「只能从列表里选」。加上**手输 `sub`** 后，管理员从 Keycloak 复制 `sub` 即可授权新人，**不需要对方先登录一次**（而这恰恰是删表堵死的那条路）。
- 闭环由**输入**补，不靠 Admin API 补 ⇒ 不新增「hub 持有一把 Keycloak 管理凭据」这个新安全面。记为**暂时**而非永远：一旦出现「必须展示全量用户目录」的产品要求，按决策 §3.5 第 3 条重估 (a) 并独立评审。

**② 旧 `owner_user` 回填失败的组件怎么办？** —— 留 NULL 还是阻断迁移？
- **裁定**：**留 NULL + `RAISE WARNING`**。owner override 只是「绑定被删后的兜底」，而 P3b 在创建组件时已把 owner 绑成 `component-admin`（**那条绑定不受影响**）。为一个兜底字段中断删表不值当；但静默丢弃也不可接受 —— 所以告警必须打出来。

**③ 作者类列要不要一起切？**（规范 D3 只列 5 处，没提这几列）
- **裁定**：一起切，并**清掉映射不到的残留**。它们是 `uuid`、唯一写入源是 `CurrentUserID`，不切等于删表后在审计里留白。而残留的旧 uuid 是个「看起来像主体、实际解析不到人」的值，留着比清掉更危险 ⇒ 显式置 NULL 并告警。

### 14.4 如实标注（仍未做 / 不在本批范围）

- ⛔ **`migrations/0015` 未在真实库跑过**：本机无 Postgres。SQL 已按「先回填、后删列」的依赖顺序写并加了 `to_regclass` 守卫，但**未经真实执行验证**；部署侧请**先备份再手工 psql**（命令见迁移文件头部）。
- ⛔ **V1 `roles` 表未删**：`role_id` 列已删（本批范围），但「删 `roles` 表」**不在已确认的 D3 scope 内** ⇒ 属单独一件事。现状：`GET /roles` 仍可读，但**已不可被任何绑定引用**。
- ⛔ **realm 侧 `/org:<slug>` 组织组未建**（DB 驱动，须按库中 orgs 逐条建）。
- ⛔ **B-07 端到端验证** 仍不可运行（无集群）。
- **`owner_sub` 的 owner override 无回归测试**：判定逻辑由 uuid 相等改成字符串相等，但 `BindingService` 的 owner 分支仍未被单测覆盖（**既有缺口**，非本批引入）。
- **console 的 IA 命名未动**：左栏仍叫「用户与权限」。页面内容已改为「主体 + 已绑定主体」，菜单名保留以免动 IA（`CONSOLE-UI-DESIGN.md` 铁律）。**是否改名（→「主体与权限」）留作独立小决策。**
- **`component_configs.created_by` / `updated_by` 仍可由请求体直接写入**（handler 把 JSON 绑进 model）：这是 D3 之前就存在的「客户端可自报作者」面，本批只把类型从 `uuid` 放宽为 `string`、**未新增校验也未收紧**，留给后续单独处理。

---

## 15. Epic E 收尾（第十五批）：Artifact 保留期 GC —— 让 `expires_at` 真正生效（2026-09-23）

> 关闭 B-16 最后一个**功能**缺口（`expires_at` 无读取点 + 无 `cleanup_state`）。规格：`hub/DELETE-CONTRACT.md` §6.6-4；契约：`hub/API-REFERENCE.md`（制品段新增 GC 小节）。

### 15.1 交付清单（hub）

| 处 | 落地物 |
| --- | --- |
| 模型 | `artifact/models/artifact.go`：新增 `cleanup_state`（`active` \| `pending_deletion`）+ 两个常量 —— 用常量而非字面量，防止 GC 谓词与列表谓词各自悄悄改字 |
| 仓储 | `artifact/repository/artifact.go`：`liveForComponent`（**列表**谓词，排除 `pending_deletion`）、`expiredQuery`/`FindExpired`（**GC**谓词，**包含** `pending_deletion`）、`MarkCleanupPending` |
| 服务 | `artifact/service/gc.go`（新）：`ArtifactGC` + 窄接口 `ExpiredArtifactSource`/`ObjectDeleter` + `GCReport`；`RunOnce` **先删对象、后删行**；`Run` 默认关闭（interval≤0 立即返回） |
| 配置 | `internal/config/config.go`：`ARTIFACT_GC_INTERVAL`（秒，默认 `0` = 关）、`ARTIFACT_GC_BATCH`（默认 `100`，≤0 落回 `DefaultArtifactGCBatch`） |
| 装配 | `cmd/hub/main.go`：GC 与对账**分开**装配；显式处理 **typed-nil**（把 `storage.Client(nil)` 直接转 `ObjectDeleter` 会得到**非 nil** 接口 ⇒ `store != nil` 误判 ⇒ 在 `Delete` 上 panic） |
| 迁移 | `migrations/0016_artifact_cleanup_state.sql`：补列 + `CHECK (cleanup_state IN (...))` + 两条索引（`expires_at` 部分索引、`(component_id, cleanup_state)`）；**须手跑 psql** |

### 15.2 门禁（全绿）

```
（hub）go build ./... ✅   go vet ./... ✅ clean   go test ./... ✅ 19 包 ok   gofmt -l ✅ clean
```

新增测试 **14 例**（计数命令：`go test ./internal/artifact/... -run 'ArtifactGC|QueryShape' -v | grep -c '^=== RUN'`）：
- `artifact/service/gc_test.go`（**10** 个用例）：删除顺序 / 对象失败⇒保留行+标记 pending / **pending 行下轮重试成功后删行（自愈）** / 无对象存储仍删行且零对象调用 / 行删失败单独计数 / `FindExpired` 错误上抛 / batch 默认与覆盖 / 失败样本封顶 / interval≤0 不触库 / **结构断言 GC 无列举能力**。
- `artifact/repository/artifact_dryrun_test.go`（**4** 个用例，逐条钉住）：**列表与 GC 谓词必须不同**（本批最容易在重构中被抹平的差异）、过期判定落 SQL 且时钟为参数（同例内还断言 oldest-first 与批量闸门）、limit≤0 时无 LIMIT 子句。

### 15.3 双向钢人（本批唯一争议：GC 该不该**自动删**？）

- **正方**：`expires_at` 是运维写下的保留期声明。全仓无读取点 ⇒ 这列是一句空话，存储单调增长 —— 表结构承诺了保留策略而功能不存在，**比没有更糟**（让人误以为已有策略）。
- **反方**：对象删除不可逆；同类问题（对账）已被用户拍板为"仅报告"（`DELETE-CONTRACT` §6.5 决策 4「少删优于多删」）⇒ 应同解。
- **裁定：自动删，但仅在输入无歧义时。** 反方的漏洞是**借用结论却没借用前提**：对账的输入（DB 行集合 vs 对象集合的差集）**有合法歧义** —— 归档任务刚上传完对象、行还没落库的那一瞬间，"有对象无行"完全正常，自动删会把在途制品抹掉。GC 的输入（`expires_at < now()`）**没有歧义**：它不推断任何意图，只执行运维**已经写下**的意图。⇒ **危险的是推断，不是执行。**
- 由裁定推出两条硬约束：①**默认关闭**（会删数据的作业不该由一次部署悄悄打开）；②**先删对象、后删行**（与 `ArtifactService.Delete` 相反且刻意）—— 即时删除时元数据是权威记录，先删它、失败剩孤儿由对账兜底；GC 是回收存储，若先删行则对象删失败就**没有行可用于重试**，只能留孤儿等人读报告；先删对象则行还在、本轮标记 pending、下轮重试，**失败被自动修复**，不需要人。两个驱动的 `Delete` 对不存在的键都幂等（Local 容忍 `os.IsNotExist`、S3 `RemoveObject` 成功返回），故重试安全。

### 15.4 顺手修掉的**文档假绿**（真实缺陷）

`hub/STORY-BACKLOG.md` 的 B-16 行把「(c) 级联 + `cleanup_state` 清理标记 + `expires_at` 生效：**已随 Epic A / B-16(源头) 落地**」记成了完成 —— 实测三项里**两项根本不存在**（`cleanup_state` 列不存在、`expires_at` 全仓无读取点）。本批既补了实现，也把那行改成如实描述（并标注"此前误记"）；`DELETE-CONTRACT.md` 的 B-16 状态行、`DATA-MODEL.md` 的相关行同步。

### 15.5 如实标注（仍未做 / 未跑）

- ⛔ **`migrations/0016` 未在真实 Postgres 跑过**（本机无 PG）。列本身会由 AutoMigrate 补上，但 **CHECK 约束与两条索引只存在于本 SQL**，落库前请先备份再手工 `psql`。
- **Artifact 的域内级联软删（§6.4）仍未做** —— 这是 B-16 的最后一项（删 org→service→component→pipeline 时对制品/对象的处理）。
- GC **不做**对象存储分层（"热层 90 天 → 冷归档 1 年"属 bucket 生命周期规则，不在 hub 内）。
- console **无改动**：制品页本就不提供删除入口；`pending_deletion` 的隐藏发生在 hub 的列表端点。

---

## 16. 部署验证遗留缺陷登记（2026-09-23 第十六批）

> 来源：2026-09-23 上午 Envoy Gateway 迁移 + kind 集群重建 + 三服务全量部署 + §6.4 级联删除**真集群**端到端验证。部署链路本身已全绿（console/https 200、hub API 经网关 200、keycloak realm 导入成功、runner 心跳 online），本节登记验证过程**新暴露**的缺陷与勘误。

### 16.1 新发现缺陷（本轮验证直接暴露）

| 编号 | 缺陷 | 现象 / 根因（source-grounded） | 影响 | 建议修法 | 优先级 |
| --- | --- | --- | --- | --- | --- |
| **D-01** | runner 断连恢复路径缺陷 | hub `rollout restart` → runner websocket 断开 → controller-runtime manager **重建** → TaskRun/PipelineRun informer `cache sync` 超时 → 进程退出 CrashLoop。**首启路径正常**（CRD 首次 sync 成功过），k8s 自动重启容器后可自愈 —— 但恢复依赖容器重启而非进程内重连 | hub 任何滚动重启都会引发 runner 短暂 CrashLoop（自愈窗口 ≈ 重启周期） | 恢复路径复用首启的 informer 容错 / 退避重试，**不要整建 manager**；或对 cache sync 失败做有界重试后再退出 | 高 |
| **D-02** | `POST /services` 不校验 `serviceTreeId` 存在性 | 传**不存在的** `serviceTreeId` 仍返回 201，产生悬挂引用（本轮验证时顺带发现） | 脏数据可入库存；后续按树遍历/级联时行为未定义 | service 层对 `serviceTreeId` 做 `ExistsActive` 校验（对齐 B-15 封父存在性校验套路）+ DryRun 查询形状测试 | 中 |

> **闭环（2026-09-23 第十七批 · 收口）**：D-01、D-02 已于「继续全量补齐开发」本轮修复。D-01＝runner 断连后复用首启 informer 容错、以指数退避重连而非整建 manager，并设 `maxManagerStartAttempts` 有界重试（`cmd/runner/main.go`）；D-02＝`catalog/service` 在 `Create` 前对 `serviceTreeId` 做 `ExistsActive` 校验，悬挂引用返回 400（`internal/catalog/service/service.go` + `create_test.go`）。处置汇总见 §16.4。

### 16.2 在册遗留项汇总（截至 2026-09-23，勿误报完成）

以下项为 §16 原登记项的处置结果（与 §16.1 D-01/D-02 一并于本轮「继续全量补齐开发」收口，2026-09-23 第十七批）：

| 原项 | 缺陷 | 处置 | 状态 |
| --- | --- | --- | --- |
| 1 | run 触发路径直读 repo、不绕 pipeline service 校验 | 触发统一经 `PipelineRunService.Trigger`（service 层）：`buildSpec`→`enforceProductionApproval`→`pipelineRepo.GetByID`→`createRun`→`repo.Create`，不再直写 repo（`internal/run/service/pipeline_run.go`） | ✅ 已修（Task #1） |
| 2 | realm 组织组 `/org:<slug>` 未建 | `orgsvc` 在 `Create` 后 `provisionOrgGroup` 幂等建组；启动 `ReconcileGroups` 回填存量；依赖可测 Keycloak Admin 客户端（`internal/keycloak`）+ realm 赋 `manage-users`/`query-groups` 最小集（Task #4） | ✅ 已修 |
| 3 | console 组件级自定义角色管理 UI 未做 | `PlatformAdminView.vue` 增「组件角色」区块 + CRUD Modal，`utils/permission.ts` 导出 `COMPONENT_ROLE_ACTION_GROUPS`（与 hub `component:*` 等逐字对齐），`api/permission.ts` 增 create/update/remove（Task #5） | ✅ 已修 |
| 4 | V1 `roles` 表未删 | **双向钢人裁定保留**：全仓仍有 model `TableName()="roles"`、`RoleRepository`、`RoleService`、`GET /roles`、`AutoMigrate`、`conf/06_permissions.sql` 引用；DROP 不可逆且会破坏既有端点，按 plan「有引用则停手记录」。真删需用户显式确认（Task #6） | ⚠️ 裁定保留 |
| 5 | `credentials` 无种子 + 明文存储 | 新增 `credentials/codec` AES-GCM 信封加密（写加密/读解密，明文兼容 legacy），`10_credentials.sql` 幂等种子，service 层改造（`internal/credentials`，Task #7） | ✅ 已修 |

> 注：原项 1 与 §16.1 的 D-02、原项 2 与 D-01 属同一批修复，统一汇总见 §16.4。

### 16.3 勘误（随本轮验证更新既有记录）

- §15.5 曾记「Artifact 的域内级联软删（§6.4）**仍未做**」——**service→component 部分已落地并真集群验证（2026-09-23）**：`DELETE /services/:id` 在同一事务内级联软删 component、硬删 `component_role_bindings`（DB 侧两表 `deleted_at` 时间戳一致、bindings 零残留）；`hub/DELETE-CONTRACT.md` §1.3 状态行同步更新。org→service 及制品/对象在级联中的处理范围仍以该文档 §6.4 后续落地记录为准。
- 部署/网关侧新沉淀的**工程约定**（EG v1.6 的 envoy svc 建在 `envoy-gateway-system` ns、BackendTLSPolicy(v1) 必填 `validation.hostname`、KC26 须 `KC_HOSTNAME_STRICT=false` 且 realm JSON 禁引 `uma_authorization`、keycloakx OnDelete 须手动删 pod、registry 旧镜像致部署跳过重建、本机 `https_proxy` 劫持 `curl --resolve`）不属代码缺陷，已记入项目工作记忆，此处仅留索引。

### 16.4 本轮闭环汇总（2026-09-23 第十七批 · 继续全量补齐开发收口）

本轮按「继续全量补齐开发，不确定的使用双向钢人论证」指令，将 §16 登记的全部 7 项遗留收口（代码侧 + 单元/构建 gate 全绿；真集群端到端未重跑）：

| 任务 | 对应缺陷 | 落点 | gate |
| --- | --- | --- | --- |
| #1 | §16.2 项 1（run 触发直读 repo） | `internal/run/service/pipeline_run.go` Trigger 走 service 校验 | hub build/vet/test |
| #2 | §16.1 D-02 | `internal/catalog/service/service.go` serviceTreeId `ExistsActive` 校验 + `create_test.go` | hub build/vet/test |
| #3 | §16.1 D-01 | `cmd/runner/main.go` 重连退避 + `maxManagerStartAttempts` | runner build/vet/test |
| #4 | §16.2 项 2 | `internal/keycloak` + `internal/org/service/org.go` + realm `manage-users`/`query-groups` | hub build/vet/test + keycloak httptest |
| #5 | §16.2 项 3 | console `PlatformAdminView.vue` / `api/permission.ts` / `utils/permission.ts` | console pnpm build/test |
| #6 | §16.2 项 4 | V1 `roles` 表 **裁定保留**（不删），写入 MEMORY.md | —（决策类） |
| #7 | §16.2 项 5 | `internal/credentials/codec` AES-GCM + `10_credentials.sql` 种子 | hub build/vet/test + codec_test |

**关键裁定（双向钢人论证）**
- Task #4 实现自带可测 Keycloak Admin 客户端（`net/http` + `httptest`），而非引外部 SDK——保证零外部依赖即可单测。
- Task #7 选 AES-GCM 信封加密（而非「只存引用名」）——项目无外部 secret store，引用名方案无法落地；明文兼容 legacy 以保迁移安全。
- Task #6 保留 V1 `roles` 表——全仓活引用 + DROP 不可逆，按 plan「有引用则停手记录」；删除须用户显式确认。

**遗留 / 未跑**
- ~~keycloak 组建、凭据加密的真集群端到端验证按惯例记为「未跑」~~ → **凭据加密已真集群验证（2026-09-23，docker/kind 就位后补跑）**：本地 kind 集群 hub 设 `CREDENTIAL_ENCRYPTION_KEY`（32B）→ `POST /credentials` 201 → PG 原始列为 `enc:v1:` 前缀 AES-GCM 密文、API 仅回 `valueSet:true`。keycloak 组建（Task #4）的真集群全链路受 dev 部署姿态耦合（`KEYCLOAK_ISSUER` 空 ⇒ auth 与组预置同关）限制未跑；客户端逻辑由 5 个 httptest 用例覆盖，全链路验证需 issuer-enabled 部署 + realm 用户，记为 follow-up。
- V1 `roles` 表如后续确认可删，需先清全部引用（model/repo/service/handler/AutoMigrate/seed）再 DROP。

**Phase-2 补齐（2026-09-23 下午，同日第二轮）**
- §16.2 之外的 API-REFERENCE「待补端点」逐项**按实际代码审计**后收口：`parse-kubeconfig`、`/targets` CRUD、`/environments/:id/test` **代码早已落地**（文档 stale，非新开发）；本轮新开发 = `GET /package-versions`、`GET /runs/:id/stage-progress`、serial 调度（C-06 闭口）、`POST /environments/:id/exec` + `POST /targets/:id/install|upgrade`（hub 层：校验 + `agent_ops` 台账 + 202 句柄；**runner 侧执行 + SSE 流式为明确 follow-up**，非静默缺口）。
- 真集群验证（kind sdp-dev，docker 就绪后）：Task #7 凭据加密 ✅（见上）；新端点真集群 E2E 见同日记录（package-versions / parse-kubeconfig / exec / install 直接可达，stage-progress 需真实 run 数据）。
- **E2E 结果（2026-09-23 13:2x，第三/四次镜像重建后全量 curl）**：
  - `GET /package-versions` → `{console:v0.0.1, hub:v0.0.1, runner:v0.0.1}`（CM 注入生效）✅
  - `POST /credentials/parse-kubeconfig`：合法 kubeconfig → 结构化回显 + `errors:[]`；`exec:` 插件 → 明确拒绝 ✅
  - `POST /environments/:id/exec`：202 + op 句柄；PG `agent_ops` 表落 `exec|queued|<command>` ✅；空请求体 400「command 或 script 至少其一必填」✅
  - `POST /targets/:id/install|upgrade`：202 + `detail:v0.0.1` ✅
  - `GET /runs/:id/stage-progress`：不存在 run → 404 形状 ✅（200 聚合形状由 `pipeline_run_serial_test.go` 单测覆盖，真集群 200 需触发真实 run，记 follow-up）
- **E2E 揪出并修复的 2 个真 bug**：
  1. `environments.status` 列 `varchar(16)` 装不下状态机自身值 `configured_unverified`（21 字符）——任何 key-field 变更回落都触发 SQLSTATE 22001。修复：模型 `size:16→32`（`environment.go`）+ `migrations/0017_environments_status_widen.sql`（AutoMigrate 不改列宽，需手工 ALTER），现库已 ALTER 并复验 PUT 成功落 `configured_unverified`。
  2. `parseKubeconfig` 的 `reHasClusters` 缺 `(?m)` 多行标志——真实 kubeconfig（`clusters:` 前有其他顶层键）恒误报「缺少 clusters 段」。修复：加 `(?m)`；新增回归测试 `credential_test.go`（clusters 非首段 / exec 拒绝 / 缺 clusters 三例）。
  - 验证 gate：hub `go build/vet/test`（24 包 ok）+ `gofmt -l` clean；修复经 `docker rmi` + 重部署后真集群复验通过（另见镜像陈旧陷阱：E2E 首跑 INSERT 明文即此坑复现）。
- **Task #4 真集群 E2E ✅（2026-09-23 13:36–13:41，临时接线后还原）**：
  - 铺路：kcadm（KC26 须 `--server http://localhost:8080/keycloak`）清 e2e 用户 requiredActions + 补 firstName/lastName（声明式 profile 缺姓名 ⇒ password grant 报 `Account is not fully set up`）；集群内 password grant 取 token（port-forward 取的 token issuer 不匹配）。
  - hub 临时注入 `KEYCLOAK_ISSUER=http://hub-keycloak-http/keycloak/realms/sdp`（KC 通告短名 svc、默认端口被剥）+ `KEYCLOAK_ADMIN_CLIENT_SECRET` → 未认证 401 ✅ → `POST /orgs` 201 ✅。
  - **组预置闭环验证**：首次 org 创建暴露 403 —— realm JSON 把 `query-groups`/`manage-users` 写在 SA 的 `realmRoles` 里被 `--import-realm` 静默丢弃（它们是 realm-management 客户端角色）；REST 补授后二次 `POST /orgs` 201 → KC 组列表出现 **`org:e2e-org2`** ✅（provisioner 非失败即告警语义也得到真实验证）。
  - 收尾：还原 env（dev 姿态 `AuthDisabled` 恢复，无认证 API 可用 ✅）；realm JSON 修复为 `clientRoles` 映射（`build/hub/charts/.../keycloak-realm-configmap.yaml`，仅新 realm 首次导入生效，存量 realm 靠手工/kcadm 补授）。

**文档勘误索引（本轮收口推翻的早期陈述）**
- §10/§11/§13 中「realm 侧 `/org:<slug>` 组织组未建 / 仍为零」等历史陈述：已被 Task #4（hub 运行时自动预置）推翻，以 §16.4 与 `hub/KEYCLOAK.md`、`hub/ACCOUNT-PERMISSION-MODEL.md` 第 2/6 行现状为准。
- `hub/API-REFERENCE.md`「待补端点」表中 `POST /credentials` 等由 ❌未实现 改为 ✅已落地（加密落库，Task #7）；~~同表其余 `kubeconfig`/`ssh` 直连端点仍 ❌ 未实现~~ → **Phase-2（2026-09-23）已全部收口**：`parse-kubeconfig`、`/targets` CRUD、`/environments/:id/test` 为审计确认的既有实现（文档 stale），`package-versions`、`stage-progress`、`exec`、`install/upgrade` 为本轮新开发（后三者 runner 侧执行为 follow-up），以 `hub/API-REFERENCE.md` 现表为准。
- `hub/DATA-MODEL.md` §9.7「凭据只存引用、物理位置尚未定」改为「AES-GCM 加密落库已定」（与原 ref 铁律偏离，见 Task #7 裁定）。

### 16.5 第十八批：agent_ops 全链路补齐（2026-09-23 傍晚 · 「继续全量补齐开发」）

§16.4 遗留的「runner 侧 exec/install/upgrade 执行 + SSE 流式」本轮立项收口。**exec 全链路已落地**；install/upgrade 经钢人裁定留守 queued（理由见下）。

**双向钢人裁定（四点）**

1. **协议形态**：复用 `status_update`/`log_chunk`（加 OpID）被反钢人否决——hub 的 statusH 直接写 `pipeline_runs`、logH 按 `PipelineRunName` 索引，混入 op 语义会污染两条既有管道 → **新增 `agent_op` / `agent_op_status` / `agent_op_log` 三类专用消息**（runner `api/v1alpha1`，双端唯一 wire format）。
2. **exec 执行语义**：进程内 pod exec 有「exec 到哪个 pod」语义空洞且无留痕 → **目标集群创建 Job（`sh -c`）**：K8s 原生留痕 + batchv1 超时语义 + 与 TaskRun 执行模型同构。`agent` access 用 in-cluster 凭据；`kubeconfig` access 由 hub 派发时解密 `KubeCredRef` 凭据随 payload 下发（runner 是直连执行器、合法需要；信任边界 = 已认证 gateway WS；hub 自身仍零 client-go）。
3. **install/upgrade 边界**：install 存在**引导鸡生蛋**（目标无 runner 连接则 op 无处投递，数据模型亦无「引导执行器」登记位）；upgrade 需**图表来源**（版本矩阵只有版本号）+ **runner 自升级 SA 权限**两个产品级前置 → **本轮留守 queued 不派发**，执行器属 §9.9 接入引导特性（enroll-token 凭据流转）单独立项。
4. **SSE 形态**：follow-up 明确要求流式 → **SSE（事件 `status`/`log`/`end`，先重放持久化日志再推增量，15s 心跳）+ `GET /agent-ops/:id` 轮询兜底**。订阅为进程内态 ⇒ 单实例 hub 假设记录在案；多实例回退轮询+重放（该回退路径本就存在，故重放优先设计成立）。

**落点**

| 端 | 文件 | 内容 |
| --- | --- | --- |
| 协议 | runner `api/v1alpha1/{protocol,gateway_payloads}.go`、`pkg/connector/client.go` | 3 类消息 + `AgentOpDispatchPayload`（OpID/Detail/Namespace/Kubeconfig）/`AgentOpStatusPayload`/`AgentOpLogPayload` + re-export |
| hub 模型 | `internal/target/models/agent_op.go` | 状态机四态 + `IsValidAgentOpTransition`（只前进、终态不可变）+ `AgentOpLog`；`detail` size:1024→text |
| hub 迁移 | `migrations/0018_agent_op_logs.sql` | `agent_op_logs` 建表（幂等）+ `agent_ops.detail` ALTER text（AutoMigrate 不改列类型/宽度） |
| hub repo | `internal/target/repository/agent_op.go` | `UpdateStatus`（WHERE status=from 防回退竞态）/`AppendLog`（seq=MAX+1）/`ListLogs`/`ListQueuedByTarget`（仅 queued exec） |
| hub service | `internal/target/service/{agent_op,op_stream}.go` | `ApplyStatus`（409 守卫）/`AppendLog`/`DrainTarget`/`SetDispatcher`/`SetStream` + `OpStream` SSE 扇出（满则丢、不阻塞回传路径） |
| hub 派发 | `cmd/hub/agentop_dispatcher.go` + main.go 接线 | payload 组装（env namespace + kubeconfig 解密）→ `gw.DispatchAgentOp`；connect drain 并联 agent-op 排水；`agent_op_status/log` 回调 → ApplyStatus/AppendLog |
| hub SSE | `internal/target/handler/agent_op.go` | `GET /agent-ops/:id`（轮询）/`GET /targets/:id/agent-ops`（台账）/`GET /agent-ops/:id/stream`（SSE：状态→重放→增量→end） |
| runner | `internal/agentops/handler.go` + `cmd/runner/main.go` | 异步执行（不阻塞 readLoop）：in-cluster / kubeconfig 双路 clientset → Job（GenerateName、BackoffLimit 0、TTL 1h）→ Job 轮询 + pod 日志差量回传 → 终态回传；`SDP_AGENT_EXEC_IMAGE`（默认 `busybox:1.36`）、`SDP_AGENT_EXEC_TIMEOUT`（默认 10m） |
| docs | `hub/API-REFERENCE.md`（exec 行改全链路 + 3 个新端点 + install/upgrade 裁定注记）、`hub/DATA-MODEL.md` §9.5（台账/日志表/双路执行）、`hub/README.md`（模块图 + follow-up 行改为全链路说明） | — |

**gate**：hub `go build/vet/test`（全量零失败）+ `gofmt -l` clean；runner `go build/vet/test`（全量零失败）+ `gofmt -l` clean。单测新增：hub 状态流转守卫（409）/创建即派发/离线留守/install·upgrade 不派发/日志落库+扇出/排水；runner Job 信封（命名空间回退/命令逐字/审计标签/TTL/BackoffLimit）。

**E2E 揪出并修复的 1 个真 bug（D-01 补丁缺陷）**：manager 启动重试（D-01）在同一进程里重建 manager，controller-runtime 默认按 controller 名做进程内唯一性校验，第二次 Setup 起恒报 `controller with name pipelinerun already exists`——把一次瞬时 cache-sync 超时（runner 先于 CRD ready）放大成**永久 CrashLoop**（实测 21 次重启）。修复：三个 reconciler 的 builder 加 `WithOptions(controller.Options{SkipNameValidation: &skipNameValidation})`（旧 manager 已停、无双跑风险）。修复经 `docker rmi` + 重部署后 runner manager 正常启动。

**意外获得的排水路径真实验证**：存量 queued exec op（昨日 E2E 留下）在新 runner 重连时被 hub DrainTarget 补派 → 目标集群 Job 创建并执行（busybox 无 kubectl 而失败，符合预期）→ 日志分片落 `agent_op_logs`（seq=1，stdout `sh: kubectl: not found`）→ 状态回写 `failed` + message「Job has reached the specified backoff limit」；install/upgrade 如裁定留守 queued。**排水 → 派发 → Job 执行 → 日志落库 → 状态回转全链路被现实验证**。

**遗留**：install/upgrade 执行器（§9.9 bootstrap 特性，见裁定 3）；真集群 E2E（exec 全链路，视集群状态执行）；console 侧 agent op 台账 UI / SSE 消费端未做（API 已就绪，属 console 迭代）。


