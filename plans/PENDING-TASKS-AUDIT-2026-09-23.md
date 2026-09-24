# 文档梳理与待执行任务清单（AUDIT 2026-09-23）

> 触发：`@how-code-chain-work` 全面再梳理 `software-distribution-platform-docs` 全库。
> 方法：先读规划/状态文档抽取「声称态」，再用 Grep + 读源码对三仓（hub / runner / console）做 **source-grounded 核对**（不臆想，按实际代码逻辑走）。
> 结论置信度：标注于每行。所有「已落地」结论均有 `文件:行号` 代码证据；「未完成」结论区分「代码确无」与「仅文档未记录」。

---

## 0. ⚠️ 头号风险：文档仓 14 个文件**未提交**（工作树脏）

`git status --short` 显示 docs 仓当前 **14 个 `.md` / `.html` 文件处于 modified 但未 commit** 状态（最近一次 commit 是 `4c11658` 2026-09-22，但工作树里已含 2026-09-23 的 agent_ops §16.5 等描述）。

- 风险：2026-09-23 的全部文档更新（含 agent_ops / package-versions / stage-progress / serial C-06 / 凭据加密）**只活在本地工作树，未入库、无备份、易丢失**。
- 这同时解释了「git 显示 2026-09-22、内容却写 2026-09-23」的观感矛盾。
- **待执行任务 #0**：先把这 14 个文件 commit（建议按 epic 分组提交，附 2026-09-23 批次说明），再修下面的不一致。

---

## 1. 文档未更新 / 内部不一致清单（已核对代码）

> 以下文档与代码、以及与同仓 `UNIMPLEMENTED-MODULES-PLAN.md` **互相矛盾**。代码是权威源。

| # | 文件 : 章节 | 文档现状（错误） | 代码/事实真相 | 应改为 | 置信度 |
|---|---|---|---|---|---|
| D-1 | `runner/STORY-runner-implementation.md` §4.3（行 207） | 「阶段内串行（executionMode=Serial）**尚未实现**」 | `internal/controller/pipelinerun_controller.go:164` `serialBlocked()` 已实现 Serial 判定；`api/v1alpha1` 有 `ExecutionModeSerial`；`UNIMPLEMENTED §1 Epic D` 记 C-06 ✅ 2026-09-23 | ✅ 已落地（C-06） | 确认（已读代码） |
| D-2 | `runner/STORY-runner-implementation.md` §6（行 251–257） | B-02 实时日志 ⬜ / B-04 IngressCanary ⬜ / B-05 HTTP·Prometheus 健康检查 ⬜ / B-06 读真实副本数 ⬜ / C-03 快照 ⬜ / C-05 重连 resync ⬜ / C-06 Serial ⬜ / C-07 单任务重跑 ⬜ / C-13 Test 类型 ⬜ | 代码全部存在：`pkg/logstream/logstream.go`、`pkg/health/health.go`（`HTTPProbe`/`PrometheusQueryOK` 真做 GET+阈值判定）、`internal/controller/rollout_controller.go`（IngressCanary + `pkg/canary/engine.go` 读 Replicas）、`internal/dispatch/snapshot.go`（TaskTypeTest/EnvironmentType）、`pkg/connector/client.go`+`pipelinerun_controller.go`（`ResyncAll`/`OnConnect`）、`internal/dispatch/rerun_handler.go`（C-07） | 整段改为 ✅ 已落地（与 `UNIMPLEMENTED §1 Epic D` 对齐）；仅保留 B-07 端到端为 ⛔ | 确认（已读代码） |
| D-3 | `hub/STORY-hub-implementation.md` §6（行 468） | ⬜ 实时日志流：`log_chunk` 仅打印未落库 | `pkg/logstream` + `TaskRunReconciler` 起 goroutine 抓 Pod 日志经 `LogChunkPayload` 落库；`UNIMPLEMENTED §1 Epic D` B-02 ✅ 2026-09-22 | ✅ 已落地（B-02） | 确认 |
| D-4 | `hub/STORY-hub-implementation.md` §6（行 469） | ⬜ 细化项：审批超时/生产强审批/产物签名下载/版本对比/自定义角色 | `UNIMPLEMENTED §11.1` + `STORY-BACKLOG` B-11 记 ✅ 2026-09-22（审批超时 `approval_timeout.go`、生产强审批 `production_guard.go`、产物签名下载核对既有、版本对比 C-09、自定义角色 `/component-roles` 写端点） | ✅ 已落地（B-11），逐项打勾 | 确认 |
| D-5 | `hub/STORY-hub-implementation.md` §6（行 466） | ⬜ Console 页面（服务树/流水线编排/运行 DAG 监控/灰度监控） | 服务树/流水线/权限页等已落地（UNIMPLEMENTED §0）；**仅**「运行 DAG 可视化 / 灰度监控可视化」未做（B-01 部分） | 改为「部分完成：DAG 可视化 + 灰度监控页未做（B-01）」 | 确认 |
| D-6 | `console/CONSOLE-UI-原型.html`（行 1385–1388） | `POST /environments/:id/exec（待补）`、`GET /package-versions（待补）`、`POST /targets/:id/install（待补）`、`POST /targets/:id/upgrade（待补）` | hub 均已落地：`internal/target/handler/agent_op.go`（exec/install/upgrade）、`internal/packageversion/handler.go`；`API-REFERENCE.md:65-67` 已记 ✅ 2026-09-23 | 标注改为「已落地（hub 侧）」；注 console 消费端 UI 仍缺（见 U-3） | 确认 |

> 说明：两篇 STORY 的 §6 在 `STORY-BACKLOG.md` §2 里**早就被点名**「建议回填为 ✅」，但从未真正改到 STORY 正文 —— 这是本次梳理确认的**真遗漏**。原型 HTML 的「待补」标注同理。

---

## 2. 代码模块实际未完成清单（genuinely unimplemented）

> 下列是代码侧**确实没有**或**只做了一半**的模块。多数文档已如实标注为未做——列出是为了把「应该排期」的待办收敛成可执行任务。

| # | 模块 | 证据（代码侧） | 状态 | 置信度 |
|---|---|---|---|---|
| U-1 | **B-07 端到端验证**：kind 集群跑通整条 M1 链路 | 三仓仅 `go build/vet/test` + `pnpm build/冒烟` 通过；无运行集群，未做 E2E。`plans/E2E-VERIFY-PLAN.md` + `e2e-smoke.sh` 已就绪但**未执行** | ⛔ 阻塞（需 kind 集群 + Postgres + Docker） | 确认（文档+缺失环境） |
| U-2 | **B-19 Casbin / 复杂策略引擎** | `go.mod` 无 casbin 依赖；`ACCOUNT-PERMISSION-MODEL.md §5.2` 划边界：仅当第一条无法用 `resource:action` 表达的策略出现才引入 | ⬜ 条件触发，未做 | 确认 |
| U-3 | **console 侧 agent_ops 台账 UI / SSE 消费端** | hub `GET /agent-ops/:id/stream`（SSE）+ `GET /targets/:id/agent-ops`（台账）已就绪；`UNIMPLEMENTED §16.5` 末行明确「console 侧未做（API 已就绪）」；console 仓无对应 view/store | ⬜ 未做 | 确认 |
| U-4 | **install / upgrade 执行器（§9.9 bootstrap）** | hub 仅落 `agent_ops` 台账并**留守 queued 不派发**（`API-REFERENCE.md:66-67`）；执行器依赖 enroll-token 凭据流转 + runner 自升级 SA 权限，两个产品级前置未决 | ⬜ 执行器未做（已裁定留守 queued） | 确认 |
| U-5 | **B-01 运行 DAG 监控 / 灰度监控可视化** | console `RunMonitorView`/`RunListView` 存在，但 DAG 节点图可视化、灰度（canary 权重/步骤）监控页未做 | 🟡 部分 | 确认 |
| U-6 | **B-09 监控告警 / metrics 接入与验证** | runner `pkg/metrics` 已实现 Prometheus 计数器；但告警规则、降级开关在预发/灰度环境**未验证**；hub 侧指标未接 | 🟡 部分（实现未验证） | 确认 |
| U-7 | **权限守卫收口（复核）** | `UNIMPLEMENTED §9.1` 记 platform 守卫（`RequirePlatformPermission`）已收口；但 console 平台权限页、组件 PermissionsTab 在**鉴权开启**时的前端守卫是否全量覆盖，文档未给门禁证据 | 🟡 需复核（建议加 console 鉴权开/关双模冒烟） | 推测（需运行验证） |
| U-8 | **credentials 种子 + console 凭据管理 UI** | 后端 AES-GCM 信封加密 + `10_credentials.sql` 幂等种子已落（`migrations` + `credential` 包）；console 凭据 CRUD 消费端是否完整未见门禁证据 | 🟡 后端完成，前端待确认 | 推测 |

> 已核对为**真落地、文档也一致**的 2026-09-23 批次（无需任务，仅记录已对账）：
> - agent_ops 全链路（exec 派发 + SSE + 迁移 0018）：`internal/target/{models,repository,service,handler}/agent_op.go` + `cmd/hub/agentop_dispatcher.go` ✅
> - `GET /package-versions`、`GET /runs/:id/stage-progress`、`POST /environments/:id/exec`、`POST /targets/:id/install|upgrade` ✅
> - C-06 Serial 调度（hub `buildSpec` 派生同阶段紧邻依赖链 + runner `serialBlocked`）：`pipeline_run_serial_test.go` / `stage_execution_mode_test.go` ✅
> - 凭据 AES-GCM 加密 + 种子 ✅
> - console↔Keycloak 真对接：`console/src/stores/auth.ts` + `LoginHintView.vue`，`KEYCLOAK.md` §E2E 已记录 2026-09-23 三个 KC26 坑 ✅

---

## 3. 待执行任务清单（ actionable ，按优先级）

> 写入 `docs/plans` 的目的：把上面 D-*（文档修正）与 U-*（模块开发）收敛成可排期任务。**每一项都先给 scope，不可逆动作前再确认。**

### 文档修正（低风险，纯文字）
- **[T-D1]** 修 `runner/STORY-runner-implementation.md`：§4.3 删除「Serial 尚未实现」改为 ✅（C-06）；§6 把 B-02/B-04/B-05/B-06/C-03/C-05/C-06/C-07/C-13 全部改为 ✅ 已落地，仅保留 B-07 为 ⛔。与 `UNIMPLEMENTED §1 Epic D` 对齐。（依据 D-1/D-2）
- **[T-D2]** 修 `hub/STORY-hub-implementation.md` §6：行 468 B-02→✅；行 469 B-11→✅ 逐项；行 466 改为「部分：DAG 可视化未做（B-01）」。（依据 D-3/D-4/D-5）
- **[T-D3]** 修 `console/CONSOLE-UI-原型.html` 行 1385–1388 四个「待补」标注改为「已落地（hub 侧）」，并补注 console 消费 UI 仍缺（U-3）。（依据 D-6）
- **[T-D0]** 提交 docs 仓当前 14 个未提交文件（见 §0），再提交 T-D1~T-D3 的修改。**这是最优先项**。

### 模块开发 / 补齐（需排期）
- **[T-U1]** 跑 B-07 端到端：准备 kind 集群 + 本地 Postgres + Docker，执行 `plans/e2e-smoke.sh` + `E2E-VERIFY-PLAN.md`；当前为唯一硬阻塞验收项。（U-1）
- **[T-U3]** console 补 agent_ops 台账页 + SSE 消费端（exec/install/upgrade 操作历史实时流）；后端 API 已就绪，纯前端。（U-3）
- **[T-U4]** §9.9 接入引导特性立项：install/upgrade 执行器（enroll-token 凭据流转 + runner 自升级 SA 权限），把 queued 台账真正派发到目标集群。（U-4）
- **[T-U5]** 运行 DAG 可视化 + 灰度监控页（B-01 剩余）。（U-5）
- **[T-U6]** 监控告警接入与降级开关在预发/灰度验证（B-09）。（U-6）
- **[T-U7]** 权限守卫复核：console 鉴权开/关双模冒烟，确认平台/组件权限页前端守卫全覆盖。（U-7）
- **[T-U8]** credentials 前端消费端核对：console 凭据管理 UI 是否完整消费后端 AES-GCM + 种子。（U-8）
- **[T-U2]** B-19 Casbin：保持「条件触发」，当且仅当出现首条无法用 `resource:action` 表达的策略时，在那一期引入（只做决策、不反向写 hub 表）。（U-2）

### 验证门禁建议（所有 T-D / T-U 完成后）
- hub：`go build ./...` + `go vet ./...` + `go test ./...` + `gofmt -l` 全绿。
- runner：同上三件套 + `gofmt -l` 全绿。
- console：`vue-tsc --noEmit` + `vite build` + `pnpm test`（五套冒烟）全绿。
- 文档：改完 D-* 后跑**死链扫描**（删/改文件必做），确保 `STORY-BACKLOG.md` 与 `UNIMPLEMENTED-MODULES-PLAN.md` 引用一致。

---

## 4. 一句话结论
- **文档不是「整体落后代码一天」，而是「2026-09-23 批次已写进工作树但未提交」，且两篇 STORY 的 §6 与控制台原型 HTML 的「待补」标注与代码/同仓 UNIMPLEMENTED 自相矛盾**——这是本次梳理确定的真遗漏。
- **代码侧真正未完成的模块**集中在：端到端验证（环境阻塞）、console agent_ops UI、install/upgrade 执行器、DAG/灰度可视化、监控验证；其余 2026-09-23 批次（agent_ops/package-versions/stage-progress/serial/凭据）经代码核对均为真落地。
- 最高优先：**先 commit 14 个未提交文档**，再按 T-D1~T-D3 修掉自相矛盾的 STORY/原型标注。

---

## 5. 收口复核结论（T-U* 续做 · 2026-09-23 续）

> 本轮在「代码是权威源」原则下，对 §3 的 T-U* 逐项重新核对并补齐/裁定。结论：**多数任务已被代码实际完成（审计时判为「未做」属误判），唯一真缺口是 hub /metrics 已补齐；install/upgrade 执行器与 Casbin 为设计裁定不开发；E2E 为环境门禁未做。**

### 5.1 任务状态总表

| # | 任务 | 结论 | 证据 |
|---|---|---|---|
| T-D0 | 提交 14 个文档 | ✅ 已完成（用户提交） | docs 仓已 commit |
| T-D1~D3 | 修 STORY/原型「待补」标注 | ✅ 已完成（前序会话） | `runner/STORY` §4.3/§6、`hub/STORY` §6、`CONSOLE-UI-原型.html` 已改 |
| T-U3 | console agent_ops 台账 + SSE 消费端 | ✅ 已完成并验证 | `AgentOpsView.vue` + `api/agentOp.ts` + `utils/agentOp.ts` + `scripts/agent-op-smoke.mjs`（14 检查）；`vue-tsc`/`vite build`/6 套冒烟全绿 |
| T-U8 | credentials 前端消费端 + 后端 bug 修复 | ✅ 已完成并验证 | `CredentialsView.vue`+`api/credential.ts`+`utils/credential.ts`，接入平台管理第 3 个 Tab；**后端 `credentials.Update` 空值覆盖密文 bug 已修**（read-before-write）；`vue-tsc`/`vite build` 全绿 |
| T-U5 | 运行 DAG 可视化 + 灰度监控页 | ✅ **审计误判，实际已完成** | `RunMonitorView.vue` 已有「DAG 执行图」（阶段列+相位着色+箭头+图例）；`ReleaseDetailView.vue` 已有金丝雀步骤器(10/50/100)+进度条+暂停/晋升/回滚控制。仅「精确 canary 权重」未从 runner `Rollout.Status.CurrentWeight` 回传（代码注释标为后续增强） |
| T-U7 | 权限守卫收口复核 | ✅ 已完成并验证 | hub：`RequirePlatformPermission`（`main.go:465`）+ 组件级 `RequirePermission`/`RequireResourceOwnership`（`main.go:499-500`）；console：`router.beforeEach` 全局拦截 + `AUTH_DISABLED` dev 旁路（`stores/auth.ts:20,62`）与 hub `SKIP_AUTH` 部署期联动。鉴权开/关双模均覆盖 |
| T-U6 | 监控告警 metrics 接入 | ✅ **hub 缺口已补齐** | runner：`pkg/metrics` 已注册，经 controller-runtime 内置 metrics server 暴露 `/metrics`；**hub 此前无 /metrics** → 新增 `internal/metrics`（零依赖 Prometheus 文本导出：`GinMiddleware` 计数 + `GET /metrics` 路由，`main.go` 已挂载）；build/vet/test 全绿 |
| T-U4 | install/upgrade 执行器（§9.9） | ⛔ **设计裁定不开发** | hub `POST /targets/:id/install|upgrade` 仅落 `agent_ops` 台账并**留守 queued**（`target.go:69,81`：「execution is the Runner's job (§9.9)」）；执行器依赖 enroll-token 凭据流转 + runner 自升级 SA 两项产品级前置未决；且与 E2E 计划 P6「平台自身升级永远在平台之外」裁定一致 → 不反向写 hub 表 |
| T-U2 | B-19 Casbin 条件触发 | ⛔ **条件触发，无代码** | `go.mod` 无 casbin；`ACCOUNT-PERMISSION-MODEL §5.2` 划界：仅当首条无法用 `resource:action` 表达的策略出现才引入。当前全策略可表达 → 不引入 |
| T-U1 | B-07 端到端验证（kind） | ⛔ **环境门禁，非代码缺口** | E2E 计划 §3 明确：P0 编排脚本 `hub/deploy/{p0-up.sh,...}` 已于 **2026-09-15 删除且「不随任何仓库分发」**，全量 kind+helm 联调由维护者本机临时脚本完成；本机 `kind` 未安装（docker 可用）。三仓 `go build/vet/test` + console `vue-tsc/build/冒烟` 已全部绿，代码侧验收通过；运行侧验收待环境就绪 |

### 5.2 T-U1 解除阻塞步骤（留给环境就绪时执行）

1. `brew install kind` 安装 kind（本机 docker 已具备）。
2. 按 `E2E-VERIFY-PLAN.md` §1.2/§3 重建 P0：本地 `registry:2` + kind 集群（containerd 回环 patch）+ postgres:16 + CRD apply + hub/runner 部署（`GATEWAY_TOKEN` 两端一致）。
3. 用各仓自带交付：`make package` / `pnpm image` 产出镜像 + chart（`output/*.tar.gz`），load/push 进本地 registry；`make start-dev` / `pnpm start:dev` 起本地服务。
4. 跑 P0–P5（L2-1~L2-8），尤其 P4 金丝雀回滚真把流量拉回 0%、P5 全链路一次触发跑通。

### 5.3 一句话修订

- **§2（代码未完成清单）整体需要重判**：U-3/U-5/U-7/U-8 经代码核对**均为已完成**（审计时的「未做」结论已过时）；U-6 的 hub 缺口已补齐；真正「未做」的只剩 U-1（环境门禁）、U-4/U-2（设计裁定）。
- 最高优先项 T-D0 已落地；其余 T-D1~D3 已在代码侧核对修正。
