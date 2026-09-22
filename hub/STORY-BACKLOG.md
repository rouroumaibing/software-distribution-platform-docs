# STORY 设计文档待办汇总（BACKLOG）

> 收集自 `docs/STORY-DESIGN/` 下两篇实现 Story：
> - `STORY-hub-implementation.md`（SDP-HUB-001）
> - [STORY-runner-implementation.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md)（SDP-RUNNER-001）
>
> 收集口径：提取两文档中标记为 ⬜ / 🚧 / TODO / "后续待办" / "未做" / "待补" 的项，按功能域去重合并，并对照实际代码（source-grounded）标注真实状态。
> 生成时间：2026-08-15

---

## 1. 真实未做项（去重后，按功能域）

| # | 功能域 | 待办项 | 状态 | 来源 | 关联 Epic |
|---|--------|--------|------|------|-----------|
| B-01 | **Console 前端** | 服务树导航、流水线可视化编排、运行 DAG 监控、灰度监控页面 | ⬜ 未做 | hub §6:381 | Epic 2/4/5/6 |
| B-02 | **实时日志流** | `log_chunk` 仅打印未落库；Runner 侧 Pod 日志抓取与发送未实现（类型/`LogChunkPayload` 已定义） | ⬜ 未做 | hub §6:383, runner §6:193 | Epic 7 |
| B-03 | **审批下发闭环** | Hub 侧补齐 approve_task 决策发送：新增 `POST /pipelines/:id/runs/:runId/tasks/:taskName/decision`，经 `gateway.Approve` → `MessageApproveTask` 下发，接上 Runner 已就绪的 `ApproveTask` handler | ✅ 已完成 | hub gateway/run svc+handler + main | Epic 7 |
| B-04 | **IngressCanary 路由** | `TrafficRoutingIngressCanary` 已记录，M1 降级为副本切分；专用 canary Ingress 资源为后续项 | ⬜ 未做 | runner §6:194 | Epic 6 |
| B-05 | **HTTP/Prometheus 健康检查** | M1 实际只校验 `PodReady`；`HTTPProbe`/`PrometheusQuery` 引擎分支已留但未接真实探测 | ⬜ 未做 | runner §6:195 | Epic 6 |
| B-06 | **Rollout 副本数读取真实 Deployment** | M1 默认 `total=2`，未读线上 Deployment 的 `spec.replicas` | ⬜ 未做 | runner §6:196 | — |
| B-07 | **端到端验证** | ⛔ **仍未跑（2026-09-22 复核）** —— 本机**无集群**：`kind` 未安装、`kubectl` 无 current-context、无可用 Postgres。Hub/Console/Runner 三仓仅经 `go build` + `go vet` + 单测 / `pnpm build` + 冒烟验证，**整条 M1 链路未做端到端联调，且未伪造结果**。跑法见 `plans/E2E-VERIFY-PLAN.md` + `plans/e2e-smoke.sh` | ⛔ 阻塞（需集群） | runner §6:197 | M1 验收 |
| B-08 | **单元测试** | 核心逻辑（`buildSpec`/`selectTarget`/`ApplyStatus`/canary 引擎）具备单测条件，M1 未补用例，当前以 `go build`+`go vet` 作门禁 | ⬜ 待补 | hub §5:371, runner §5:185 | 质量基线 |
| B-09 | **监控告警与降级开关验证** | 依赖后续 Epic 5 离线告警与 console 灰度监控；Prometheus 指标埋点未接入 | ⬜ 未做 | hub §5:374, runner §5:187, hub §3:66 | Epic 5 |
| B-10 | **QA 负责人待补** | Story 责任人 QA 字段、（3-Corner 澄清）QA 待补 | ⬜ 待补 | hub §1:13, hub §5:370 | 协作流程 |
| B-11 | **主规格细化项** | ✅ **已完成（2026-09-22，Epic E）** —— ① **审批超时**：`run/service/approval_timeout.go`（超时判负，先派发 runner 拒绝再记 hub 侧 `Cancelled`，目标离线顺延；env `APPROVAL_TIMEOUT_INTERVAL` 默认 60s）；② **生产强审批**：`run/service/production_guard.go`（**fail-closed**，`409 + reasons`，`ERR.08409005`）+ `environment/repository.ProductionTargets` + console 触发对话框原样渲染拒绝；③ **产物签名下载**：核对待办为**过时标记** —— `GET /artifacts/:id/download` → `DownloadURL` → `PresignDownload`（S3 presigned / Local HMAC）与 console 下载入口**早已完整**，本轮仅更正文档；④ **版本对比**：由 C-09 交付；⑤ **自定义角色**：平台级 = C-10，组件级本轮补齐 `POST/PUT/DELETE /component-roles`（**读挂裸 `api`、写要求平台级 `user:manage`**）+ `(org_id, name)` 唯一（`migrations/0014`）。见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §11.1 | ✅ 已完成 | hub §6:384 | 多 Epic |
| B-12 | **后端 DELETE 级联校验** | ✅ **已完成（2026-09-22）** —— 协议层 `APIError.Reasons` + `Envelope.reasons` 已落地；`PipelineService.Delete` 收窄为"仅活跃 phase（Pending/Running/WaitingApproval）拒绝、历史放行"；Component/Service 注入活跃运行计数 → `409 + {reasons}`；Environment.Delete 改为"删前统计配置覆盖并写审计日志"（不拒绝，§6.4 #8）。**本轮未做**：§6.4 的"域内级联软删"（org→service→component→pipeline 的子资源物理清理）按 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §3.3 留作独立任务 | ✅ 已完成 | DELETE-CONTRACT §4 | N-15 / N-5 |
| B-13 | **环境分组落库** | ✅ **已完成（2026-09-22）** —— 新表 `environment_groups` + `environments.group_id`（可空）已落地；删非空分组 `409 + {reasons}`，空组硬删。DDL + 删除语义 + gate 见 `hub/DATA-MODEL.md` §8 | ✅ 已完成 | DATA-MODEL §8 | 环境/配置 |
| B-14 | **`component_config_history` 去 FK + 快照列** | ✅ **已完成（2026-09-22）** —— 模型加 `EnvironmentKey`；config 服务经窄接口 `EnvKeyResolver` 在写历史时落快照（解析失败降级为 `""`，**不阻断配置写入**）；`migrations/0008_config_history_env_key.sql` 摘除 `component_config_history_environment_id_fkey` 并补列（AutoMigrate 只加列、不删约束，故去 FK 必须手跑 SQL）。`environment_id` 保留为"尽力引用"，列不删 | ✅ 已完成 | DELETE-CONTRACT §6.6-2 | 配置审计 |
| B-15 | **stages/templates 软删标记 + 父存在性校验 + `pipelines` 唯一约束** | ✅ **已完成** —— (a) 父存在性校验、(b) `pipelines` 改 partial unique index、(c) 模型时间列映射：**2026-09-16**；`deleted_at`（原"待拍板"项）：**2026-09-22** —— 两模型 `BaseNoSoftDelete` → `common.Base`，`StageService.Delete` 做服务层级联软删模板（DDL cascade 对软删不触发），旧 `unique(pipeline_id,sequence)` / `unique(stage_id,name)` 改为 `where deleted_at is null` 的 partial unique index（`migrations/0009`） | ✅ 已完成 | DELETE-CONTRACT §6.6-3 | 流水线定义 |
| B-16 | **Artifact 治理（源头 + 对账）** | ✅ **已完成（2026-09-22）** —— (a) **已堵源头**：`ArtifactService.Delete` 不再吞错，对象清理失败记结构化日志；元数据删除即成功，**不**把对象删除失败升级成 API 错误（行已不在，返回失败等于对调用方撒谎）。(c) 级联 + `cleanup_state` 清理标记 + `expires_at` 生效：已随 Epic A / B-16(源头) 落地。(d) **周期性孤儿对账已落地（Epic E，2026-09-22）**：`artifact/service/reconcile.go`（`ArtifactReconciler.Run` / `RunOnce` + 纯 `DiffStorageKeys`）+ 驱动侧 `Enumerator` 接口（S3/Local 各自 `ListObjects`）+ env `ARTIFACT_RECONCILE_INTERVAL`（**默认 0 = 关闭**）/ `ARTIFACT_RECONCILE_PREFIX`。**只报告、绝不删除**；驱动不支持列举时**告警"未启用"而非报"干净"**。见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §11.3 | ✅ 已完成 | DELETE-CONTRACT §6.6-4 | 产物管理 |
| B-17 | **跨资源搜索端点** | ✅ **已完成（2026-09-22）** —— 新模块 `internal/search` + `GET /search?q=&type=&limit=`（附 A N-8）：service / component / pipeline 三类各取 `limit` 条，`ILIKE` 匹配名称与 key（**转义 LIKE 元字符**），排序为「精确命中 > 名称前缀 > 名称包含」，JOIN 出展示路径（`组织 / 服务 / 组件`），逐表过滤软删；`type` 未知取值与超上限的 `limit` 均 **400 而不是静默降级**。同批补 `GET /orgs/:id/services`（附 A N-9）。查询形状由 DB-free 回归测试钉住（`internal/search/repository/search_dryrun_test.go`）。**刻意未做**：权限过滤（等账号权限模型 D1–D6 拍板）。端点清单见 `hub/API-REFERENCE.md` §2「跨资源搜索」 | ✅ 已完成 | console R-8 / 附 A N-8·N-9 | Console 前端 / 账号权限 |
| B-18 | **鉴权强制点 id 反查** | ✅ **已完成（2026-09-22）** —— `ACCOUNT-PERMISSION-MODEL.md` §10 第 14 行：4 条强制点路由的 `:id` 实为 **pipeline/run id**，却被当 component id 查绑定 ⇒ 开鉴权后**恒 403**。修法：`middleware.RequirePermission` 改为按 `Requirement.Resource`（component / pipeline / run）解析，`internal/permission/service/locator.go` 负责反查（run 走 run → pipeline → component 两跳）；拒码语义固定为 401 / 400 / 404 / 403 / **500（查询失败 ≠ 无权限）**。单测 16 例（`rbac_test.go` 10 + `locator_test.go` 6，全部 DB-free）。**注意**：本次**未动**「主体 = 本地 `users.id` 还是 token `sub`」——那属 §12 D3（Epic C） | ✅ 已完成 | ACCOUNT-PERMISSION-MODEL §10 #14 | 账号权限（Epic C 前置） |
| B-19 | **复杂策略引擎（Casbin / OPA）需求点登记** | ⬜ **未做（条件触发；登记本身即交付）** —— `hub/ACCOUNT-PERMISSION-MODEL.md` §5.2 已划边界：简单 `resource:action`（有/无）走 hub 内置判定，**字段级 / 角色继承 / 临时条件策略**才归 Casbin；`hub/DATA-MODEL.md` §7.6 亦记为「不在本期」。当前仓库只有简单判定（`go.mod` **无** casbin 依赖），故 **D4 判定 = 延后**。**触发条件（写死）**：出现第一条**无法用 `resource:action` 表达**的策略（典型：仅工作时间可发生产、环境/金额阈值以上需双人审批）时，**在那一期**引入。**引入时的硬约束（写死）**：Casbin **只做决策**；策略**由 hub 表导出、不得反向写** hub 表（保持不动式②「hub 是唯一权限权威」）；不替代 §6 审计与 §7 审批流。论证见 `plans/ACCOUNT-PERMISSION-DECISIONS.md` §4 | ⬜ 未做 | ACCOUNT-PERMISSION-MODEL §5.2 / D4 | 账号权限（Epic C） |

---

## 2. 已被消化、但文档待回填的过时期待办

> 以下两项出现在 `[STORY-hub-implementation.md §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-hub-implementation.md)`，但写于 Runner 实现之前。经 source-grounded 核对实际代码，**本轮 Runner 实现（SDP-RUNNER-001）已实际完成**，Hub 文档 §6 需回填修正。

| 文档原待办（行号） | 实际状态 | 证据 |
|--------------------|----------|------|
| "Runner 端 handler 注册：`cmd/runner/main.go:52` 的 `MessageApplyPipelineRun` 回调未接实际逻辑" (hub §6:380) | ✅ 已注册 | `cmd/runner/main.go:53` 注册 `MessageApplyPipelineRun` → `applyHandler.Handle`；`:55` 注册 `MessageApproveTask`；`:70` 注册 `RolloutReconciler` |
| "灰度发布补全：`runner/pkg/canary/` 为空，`rollout_runs` 暂无写入来源" (hub §6:382) | ✅ 已实现 | `pkg/canary/engine.go` 已创建；`rollout_controller.go` 管理 stable/canary Deployment 并回填 Rollout/TaskRun 状态 |

**建议**：将 `[STORY-hub-implementation.md §6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/STORY-hub-implementation.md)` 第 380、382 行删除或改为"✅ 已在 SDP-RUNNER-001 完成"，避免 backlog 误读。

---

## 3. 汇总统计

- **真实未做项**：19 项（B-01 ~ B-19）。其中 ✅ 已完成 7 项（B-03 审批下发；B-12 后端 DELETE 级联校验；B-13 环境分组落库；B-14 config_history 去 FK + 快照列；B-15 全部含 `deleted_at`；B-17 跨资源搜索端点；B-18 鉴权强制点 id 反查）、🟡 部分完成 1 项（B-16：源头已堵，级联 + 清理标记 + 对账未做）、⬜ 未做/待补 11 项（含 **B-19**，属**条件触发**而非待排期）。
  - **本轮（2026-09-22）落地**：B-12（含协议层 `reasons`）、B-13、B-14、B-15 剩余的 `deleted_at`、B-16 的 (a) 源头堵漏；同批新增未落地总表 `plans/UNIMPLEMENTED-MODULES-PLAN.md`（含 Epic 分组、执行顺序与验证 gate）。
  - **本轮（2026-09-22）第二批**：B-17（跨资源搜索端点，R-8 的后端部分）—— hub `internal/search` + `GET /search` + `GET /orgs/:id/services`；console 侧四项规模机制（懒加载 / 服务端搜索 / 虚拟滚动 / 独立滚动容器）同批落地，见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §6 与 `console/CONSOLE-UI-DESIGN.md` 附 I。
  - **本轮（2026-09-22）第三批**：B-18（鉴权强制点 id 反查，`ACCOUNT-PERMISSION-MODEL.md` §10 第 14 行）；同批产出 Epic C 的 D1–D6 决策材料 `plans/ACCOUNT-PERMISSION-DECISIONS.md`（备选 / 推荐 / 连锁改动 / 不可逆性分级），下一步见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §7。
  - **本轮（2026-09-22）第四批**：**B-19**（复杂策略需求点登记 —— 把 D4 判定里的「登记」真正落实）；同批把 D1–D6 决策材料升级为**双向钢人版**（`plans/ACCOUNT-PERMISSION-DECISIONS.md` v2），复核上游事实后**推翻自身上一版的三处结论**（D1 的推荐理由与不可逆性分级、D5 的否决理由、D3 的处数），并修正 `hub/ACCOUNT-PERMISSION-MODEL.md` / `hub/KEYCLOAK.md` / 本文 / `hub/DATA-MODEL.md` / `plans/UNIMPLEMENTED-MODULES-PLAN.md` / `README.md` 共 **14 处**文档缺陷。
  - **同批修正的陈旧状态**：§4 的 **C-01 / C-02 / C-12** 三行此前仍记「⬜ 未做 / 🟡 部分」，而 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §4/§5 已记 2026-09-22 完成 —— 已同步（产物与门禁均存在）。
  - **本轮（2026-09-22）第五批**：**C-10**（平台级 RBAC HTTP 端点）落地 —— repo 扩 CRUD、新增 `PlatformRoleService` / `PlatformBindingService`（§5.3 主体校验 + `/org:` 保留前缀 + 到期校验）、两个 handler 与 `main.go` 注册；**同批补 `expires_at` ×2**（`migrations/0011`）并让 `ListMatching` 排除过期授权（否则 TTL 只是装饰）；种入 `/sdp-admin` 组 → `sdp-admin` 绑定；新增 **47 条测试**（服务层脱库 24 + 子 23，含 handler 路由断言）。见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §8。
  - **本轮（2026-09-16）新增 4 项**：B-13 ~ B-16，来源为删除检查项梳理 + 三项双向钢人论证（`hub/DELETE-CONTRACT.md` §6.5~§6.7、`hub/DATA-MODEL.md` §8.8）。
  - **2026-09-16 落地**：B-15 的 (a) 父存在性校验 + (b) `pipelines` 改 partial unique index + (c) 模型时间列映射，见 `hub/DELETE-CONTRACT.md` §6.6-3「落地记录」。
- **过时期待办**：2 项（已在 Runner 实现中消化，待回填 Hub 文档）。
- **优先级提示**（按 M1 验收阻塞程度）：
  - 阻塞 M1 端到端验收：B-07（端到端验证）、B-03（审批下发，若用审批任务）。
  - 影响可观测/质量基线：B-08（单测）、B-09（监控告警）。
  - **数据模型/一致性：已清空** —— B-14 / B-15 已完成；B-16 仅剩"源头残余（级联 + 清理标记 + `expires_at` 生效）+ 对账（仅报告）"，见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` Epic E。
  - 功能完整性：B-01/B-02/B-04/B-05/B-06/B-11（B-12/B-13 已完成，移出）。
  - 协作流程：B-10（QA 待补）。

---

## 4. 补充缺口（合并自 FEATURE-GAP-BACKLOG.html，2026-09-19 快照）

> 该 HTML 已删除，其未覆盖于 B-01~B-16 的缺口并入此处。P0-1（Releases 端点）、P0-2（全局 `/pipelines`）**已实现**（2026-09-15 后代码新增，见 `hub/API-REFERENCE.md`），不重复列；P1-4/1-5、P2-1~5/12 已分别含于 B-01/B-02/B-05/B-11/B-16。

| # | 功能域 | 待办项 | 状态 | 原编号 |
| --- | --- | --- | --- | --- |
| C-01 | Console | ⌘K 全局搜索（Cmd/Ctrl+K 浮层，资源直达） | ✅ **已完成（2026-09-22）** —— `components/CommandPalette.vue`（四态 + ↑↓/Enter/Esc，上限 20）+ `utils/search.ts`（**零 import** 分档打分：全等 > 名称前缀 > 名称子串 > 路径 > 类型 > 别名）+ `composables/useGlobalSearch.ts`（索引 / 200ms 防抖 / 请求序号丢弃过期响应）；浮层已改「**服务端优先、客户端索引兜底**」并在降级时明示（不静默）。门禁 `pnpm test:theme-search` 25 条 | P1-2 |
| C-02 | Console | 暗色主题（dark token 集 + 切换开关 + WCAG AA 对比度） | ✅ **已完成（2026-09-22）** —— `styles/tokens.css` 重写为双主题（`:root` + `:root[data-theme="dark"]`，§9.2 权威名与工程别名同值并存）+ `utils/theme.ts`（**零 import**：归一 / 优先级 / 切换 / 灰阶）+ `composables/useTheme.ts`；首屏防白闪用 `index.html` 内联脚本（其键名与 `theme.ts` 的同步由静态断言钉住） | P1-3 |
| C-03 | Hub | Pipeline 触发时 stages/tasks 快照序列化固化 | ⬜ 未做 | P1-7 |
| C-04 | Hub | 清理未调用的 `PipelineRunHandler.RegisterRoutes`（冗余/遗留代码） | ⬜ 待清 | P1-8 |
| C-05 | Runner | connector 重连后 resync（在途 PipelineRun 重新对账，TODO） | ⬜ 未做 | P1-6 |
| C-06 | Runner | ExecutionMode=Serial（阶段内串行，当前仅 Parallel） | ⬜ 未做 | P2-10 |
| C-07 | Runner | 失败节点单任务重跑（当前仅整 run redispatch） | ⬜ 未做 | P2-9 |
| C-08 | Console | DAG 自由画布编辑器（当前 stage/task 列表式编排） | ⬜ 未做 | P2-6 |
| C-09 | Hub/Console | 流水线版本历史 / 对比 / 回滚 | ✅ **已完成（2026-09-22，Epic E）** —— hub：结构性保存自动留档（stage/task 增删改挂 `VersionPublisher`，去重同 body）+ `GET /pipelines/:id/versions` · `GET .../versions/:version` · `GET .../versions/:version/diff?against=` · `POST .../versions/:version/rollback`；diff **按对象名**对齐（不按 row id），**回滚 = 结构回填 + 追加新版本，绝不重写历史**（`migrations/0013`）。console：`PipelineVersionPanel.vue`（对比选择器 + 差异表 + 版本列表 + 结构预览 + 回滚二次确认）+ 编辑器「版本历史」入口。见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §11.2 | ✅ 已完成 | P2-7/P2-8 |
| C-10 | Hub | 平台级 RBAC HTTP 端点（`/platform-roles`、`/platform-role-bindings`） | ✅ **已完成（2026-09-22）** —— repo 扩 CRUD（含 `ExistsActive` / `CountBindings`）+ `PlatformRoleService` / `PlatformBindingService`（§5.3 主体校验 + `/org:` 保留前缀 + 到期校验）+ 两个 handler + `main.go` 注册；**同批加 `expires_at` ×2**（`migrations/0011`）并让 `ListMatching` 排除过期授权；种入 `/sdp-admin` 组 → `sdp-admin` 绑定；47 条新测试。见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §8 | P1-1 / DATA-MODEL §7 |
| C-11 | Hub/Runner | 目标离线告警 + Helm 一键接入 + runner 重连对账（**2026-09-21 二次裁定：安装/升级逻辑落 hub、console 只调 API；版本按版本矩阵 CM 取；前置 = `agent_version` 上报 + per-target 身份 + hub 引入 k8s 客户端**）。**版本矩阵的发布链路已于 2026-09-21 落地**（hub 仓 `build/hub/versions.yaml` → `build.sh` 校验并渲染 → CM `package-versions` + env `PACKAGE_VERSION_*`；三仓 `imageAddr` 硬编码缺口同批修复）——**端点与编排仍待实现**（`hub/DATA-MODEL.md` §9.10） | ⬜ 未做 | P2-11 |
| C-12 | Console | 流水线全生命周期 UI（新建/删除入口、编辑器支持 build/release/approval 编排） | ✅ **已完成（2026-09-22）** —— 列表五列 + `＋ 新建流水线` + 删除强确认（输入名称）+ 渲染 `409 + {reasons}`；编辑器支持阶段 `◀ ▶` / 子任务 `▲▼` 重排、阶段 `executionMode` 切换、保存前弹 JSON/YAML 预览与实际调用序列；子任务表单改为**配置派生**（去掉违反 §7.4 的三选一）；删掉过时的 `kind !== 'build'` 客户端闸门（N-7）。落地记录见 `plans/UNIMPLEMENTED-MODULES-PLAN.md` §5（`pnpm test:pipeline` 41 条） | P0-3 |
| C-13 | Runner | Test 类型 / 环境模型（daily/版本归档/转测/生产环境语义） | ⬜ 未做 | P2-1 |
