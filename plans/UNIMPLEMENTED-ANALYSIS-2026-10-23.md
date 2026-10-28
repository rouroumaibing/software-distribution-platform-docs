> **性质**：分析交付物（只读结论 + 文档命运裁定）。状态权威仍以 [STATUS.md](./STATUS.md) 为准；本文件是「未实现内容 → 是否补齐设计文档」的双向钢人论证与裁定记录。

---

# 未实现内容分析 — 代码链 + 双向钢人 + 文档命运裁定（2026-10-23）

> **再分析反转（2026-10-26）**：原 O-37/O-38/O-39/O-40/O-41 判为 `NOT-NEEDED(-NOW)`，理由多为「策略/语义/产品决策未拍板 → 无法落地」。本轮 source-grounded 重读代码后判定：这些「未拍板」均已可被具体代码方案消解（复用现有 ArtifactGC 范本、released-artifact 数据源、失败语义固定、access_mode schema、并发枚举），不再判为推迟，统一升至 `FILL/KEEP`，对应 `plans/` 文档已升格为实质设计草案。详见文末「再分析反转」小节。

## 方法论

- **代码链梳理**：套用 `@how-code-chain-work` 协议（Phase 0 边界 → Phase 1 正向/反向追踪 + 非调用依赖扫描 → 置信度标注）。范围 = 各未实现项若落地，会触碰的**入口 / 改动点 / 反向依赖方 / 字段数据流**，仅做静态读码，不动手改。
- **双向钢人**：对每个未实现项，分别给 **Steelman（补/留设计文档的正当性）** 与 **False-Steelman（不补/延迟的正当性）**，再落裁定。
- **文档命运裁定**三类：
  - **FILL/KEEP** — 设计文档内容已实质、可落地，保留（个别项附微小补强建议）。
  - **NOT-NEEDED-NOW** — 纯产品/策略决策留守或依赖未定，当前**不应**继续补齐设计文档（STATUS 条目为权威跟踪，占位即可；决策拍板后再充实）。
  - **NO-DOC** — 已完成/条件未触发/运维类，根本不需要独立设计文档（STATUS + 既有权威文档已覆盖）。

---

## Part A — 设计文档集（§2 O-31–O-41，对应 6 份 `plans/` 文档）

### O-31 Runner 任务容器安全加固（A2 / F3.2）— `runner-hardening.md`

**代码链（确认）**
- 入口：`runner/pkg/executor/job_builder.go`
  - `mainContainer` → `applyPrivileged(&c, tr.Spec.Privileged)` @ `:328`
  - `releaseContainer` → 两处 `applyPrivileged` @ `:380`、`:410`（switch 两 return 分支）
  - `applyPrivileged` 定义 @ `:417-423`：仅 `privileged=true` 时设 `SecurityContext.Privileged`，否则直接 return，**非特权分支零安全上下文**。
- 字段数据流：`tr.Spec.Privileged`（bool）/ `tr.Spec.Resources`（@ `:324` 直用任务 spec，平台无默认）→ 新增 `applyDefaultSecurityContext` 只写非特权分支；`ReadOnlyRootFilesystem=true` 须配 writable 子卷（workspace 已挂 `:326`），构建缓存/临时目录需 writable emptyDir。
- 反向依赖：任务容器 spec 由 hub `TaskRun` 下发，runner 仅消费；改动只影响**非特权任务 Pod**，对 privileged 构建路径（dind/cind）零影响。**爆炸半径低（确认）**。
- 非调用依赖：chart `values.yaml` 新增 `taskSecurity.defaultResources` 须与 `tr.Spec.Resources` 为空判定联动（配置驱动分支，但仅本地 values，置信度确认）。

**Steelman（FILL/KEEP）**：默认 root + 可写根文件系统 + 未 drop capability + 无 seccomp 是真实逃逸面；非特权分支加默认 SecurityContext 是容器平台标准件，改动局部、可逆、不触协议。

**False-Steelman（NOT-NEEDED-NOW 的反对）**：`ReadOnlyRootFilesystem` 会击穿 dind/cind 构建任务——但可通过「仅非特权分支加固 + 挂 writable 子卷」规避，且已在该任务清单首步明确双路径验证。该风险不构成「不补文档」理由。

**裁定：FILL/KEEP**（文档已含目标/证据/改动点/验收 gate，充分；仅建议补强「writable 子卷挂载点清单」一节）。

---

### O-32 Runner 多副本 LeaderElection 防呆（F3.1）— `runner-hardening.md`

**代码链（确认）**
- 改动**仅 chart 层**：`deployment-runner.yaml` 在 `container-1` env 段按 `basic.replicaCount>1` 注入 `LEADER_ELECTION=true`；`values.yaml` 默认 `replicaCount=1` + 注释强提示。
- `cmd/runner/main.go:144` `LeaderElection: os.Getenv("LEADER_ELECTION")=="true"` 不改；`rbac.yaml:65` 选主权限已备。
- 无 Go 逻辑改动，无字段数据流，爆炸半径 = 部署模板。**极低风险（确认）**。

**Steelman（FILL/KEEP）**：单行级防呆消除「多副本忘开 LE → 双 reconcile 重复建 Job/Pod」运维陷阱；不改默认单副本行为。

**False-Steelman**：默认 `replicaCount=1` 本就无问题，防呆属「锦上添花」。但成本近零、收益明确，不构成延迟理由。

**裁定：FILL/KEEP**（trivial 且高价值；与 O-31/O-33 同批进 chart 修复即可）。

---

### O-33 网关共享 token + per-target 身份缩窄（F1.1 / §9.9）— `runner-hardening.md`

**代码链（确认，含一处文档漂移）**
- `hub/internal/gateway/gateway.go` `ServeWS` @ `:129`：**三态鉴权已落地**（与 `runner/features/per-target-auth.md` 一致）：
  - ① 共享 `GATEWAY_TOKEN`（或 dev 无 token）→ legacy 路径 @ `:133`
  - ② 一次性 enroll token → `ConsumeEnrollToken` @ `:135`
  - ③ per-target 凭据 → `GetByCredential` @ `:137`
- **文档漂移**：`runner-hardening.md` O-33「现状/证据」行称「WS 网关仅校验全局 GATEWAY_TOKEN + 自报 X-Target-Name」——与代码不符（三态已实装）。本分析已就地修正该表述（见文末「文档漂移修正」）。
- 缩窄版剩余工作 = **加法**：强制 enroll token 必填（拒 legacy 共享 token 路径）+ vendor/region 白名单；改 `gateway.go` bootstrap 分支 + chart 注入 per-target 随机 `authToken`/`X-Enroll-Token`。爆炸半径 = 鉴权路径（中）。

**Steelman（FILL/KEEP）**：共享 `TARGET_AUTH_TOKEN` 跨所有 runner 复用，任一持 token 者可冒名未注册/他人 target，是真实横向移动面；缩窄版（enroll 必填 + 白名单）中等成本消除。

**False-Steelman**：三态鉴权已落地（per-target 凭据反查已实装），严格 404 模式也已支持；全量密码学身份（签发/轮换）是跨 hub/runner/chart 完整特性，留后续合理。但「缩窄版」本身仍是增量增益，非「不补文档」理由。

**裁定：FILL/KEEP**（修正现状表述后文档准确；缩窄版设计已具体）。

---

### O-34 API 限流 / CORS / 安全响应头（A3）— `observability-security.md`

**代码链（确认）**
- 中间件链 @ `cmd/hub/main.go:546-565`：`r.Use(metrics.GinMiddleware())` → `api.Use(auth.Middleware())` → `api.Use(middleware.UserContext())` → `api.Use(middleware.AuditMiddleware(...))`。
- 新增 `internal/middleware/security_headers.go`（无状态，纯响应头注入）+ `internal/middleware/ratelimit.go`（单副本 in-memory 滑动窗口）；挂 `main.go` 链上（建议置于 `auth` 之前或 `UserContext` 之后）。
- 字段/数据流：限流计数 `map[ip+route]→window` 仅进程内；多副本下不跨副本（与 O-32 LE 无关，但注释须声明「多副本需外置 redis」）。爆炸半径 = 中间件链（低-中）。

**Steelman（FILL/KEEP）**：安全响应头零成本、防点击劫持/MIME 嗅探；登录/token 接口限流防暴破；属防御纵深标准件。

**False-Steelman**：限流在多副本下需共享计数（先单副本起步可行）；严格 CORS 配错会阻断 console 前端（当前同源能跑）。但这些是「实现时注意点」，已在文档注明，不构成不补理由。

**裁定：FILL/KEEP**（建议补强「多副本限流演进路径」与「CORS 仅确有跨域时启用」的明确开关设计）。

---

### O-35 结构化日志与集中采集（B2）— `observability-security.md`

**代码链（确认，低风险）**
- hub 已封装 `applog`；runner 侧日志风格未统一盘点（非调用依赖：runner 日志调用点散布多包，须先盘点——**未验证-动态**，但风险低）。
- 改动 = 约定统一 JSON 字段（`level/time/msg/component/scope/trace_id`）+ hub `applog` 补齐 + runner 对齐；采集端点约定 `stdout`，不强制后端。无协议变更、无字段数据流耦合。**爆炸半径低（确认）**。

**Steelman（FILL/KEEP）**：增量可逆改造，多副本/多组件下排障与审计取证显著改善。

**False-Steelman**：runner 侧调用点需先盘点，强行统一可能引入格式回归。但风险低、可逆，不构成不补理由。

**裁定：FILL/KEEP**（建议补「runner 日志调用点盘点清单」作为首步验收项）。

---

### O-36 通知渠道 Webhook 适配器（A4）— `notification-webhook.md`

**代码链（部分未验证-动态）**
- 入口：`hub/internal/notification/service.go:99` `func (s *Service) Dispatch(evt, subject, title, body string)`。
- **反向追踪（未验证-动态）**：生产调用方**未通过字面量 `.Dispatch("run_"` 检索定位**（全仓 `.Dispatch(` 命中除测试外均为无关的 `HubServer.Dispatch`/`agentOpDispatcher.Dispatch`）。真实调用方经接口/变量 evt 注入，须 LSP find-references 或搜 notification service 装配点方能枚举——本报告标记此为待验证项。
- 改动点：定义 `Channel` 接口 + Webhook POST 适配器（重试/超时）；`Subscription`（`subscription.go:14`）扩 `WebhookURL`；`Dispatch` 由 best-effort swallow 改为按渠道分发。**关键契约（false-steelman 硬约束）：`Dispatch` 失败不得令调用方（run 状态写 / 审批 seeding）失败** —— 此契约须在改动中保持，且须由反向追踪确认调用方是否已吞掉 error。爆炸半径 = 通知分发路径（中）。

**Steelman（FILL/KEEP）**：O-5 告警规则已落地但出不去 Webhook，运维闭环不完整；Webhook 适配器是低风险扩展，不破坏邮件路径，闭合 #7 铃铛之外的告警出口。

**False-Steelman**：R3 当期决策邮件-only；加 Webhook 需重试/超时/凭据存储，属产品范畴。但范围已锁 Webhook、IM 留后续，风险可控，不构成不补理由。

**裁定：FILL/KEEP**（建议补强「反向追踪调用方 + 失败吞错契约的单测」为首步 gate；当前文档已含验收 gate，足够）。

---

### O-37 审计 / 运行日志 / 制品保留与 GC（C1）— `data-lifecycle.md`

**代码链（2026-10-26 再分析：基线已可落地）**
- 改动 = hub scheduler/cron 分级 GC（先报告后删）+ 与 O-26 备份协同的保留基线。
- 范本已存在：`internal/artifact/service/gc.go`（`ArtifactGC`，按 `expires_at` + `cleanup_state` 双谓词、批处理 `DefaultArtifactGCBatch=100`、默认关闭 `ARTIFACT_GC_INTERVAL=0`）+ `gc_test.go` 全覆盖。
- 审计日志：`internal/permission/models/audit_log.go:13` `AuditLog` 带 `CreatedAt`，`internal/permission/repository/audit_log.go` 无按龄清理路径。
- 运行日志：`pipeline_run`/`task_run` 有终态字段与时间戳，无保留期作业。
- 配置范式：`internal/config/config.go:107-124` 已有 `ArtifactGCInterval`/`ArtifactGCBatch`，可同型扩展。
- **原阻断点（已消解）**：保留基线「未拍板」曾是延迟理由；再分析判定——默认 `0=关闭`（与 ArtifactGC 一致，删数据作业须显式开启）+ 三档 retention 配置（审计长留 / 运行短留 / 制品按版本数滚删）即可落地，无需等产品拍板；GC 删错风险由「仅删终态+超龄」双保险消除。

**Steelman（FILL/KEEP）**：PG 无限增长是真实长期风险，分级 GC 必要；范本现成，改动增量、可逆。

**False-Steelman（NOT-NEEDED-NOW 原支持，已推翻）**：GC 删错不可逆，须先定基线。但默认关闭 + 仅删终态+超龄已消除该风险，且 ArtifactGC 同型模式已验证，不再构成「不补文档」理由。

**裁定：FILL/KEEP（再分析反转，原 NOT-NEEDED-NOW）** —— 占位已升格为实质设计草案（`data-lifecycle.md` 含目标/证据/改动点/验收 gate）；STATUS 条目保留为状态权威。

---

### O-38 组件可部署版本端点（F2.2）— `release-governance.md`

**代码链（2026-10-26 再分析：数据源已定）**
- 入口：新增 `GET /components/:id/versions`；`cmd/hub/main.go:573` `componentHandler.RegisterRoutes(api)` 已挂载，`internal/component/handler/component.go:22` 无 `/versions` 子路由。
- 数据源已定：可部署版本 = 该 component 下 `released/published` 制品版本，复用 `internal/artifact` 查询（`internal/component/handler/config_version.go:34` 已证明组件侧「版本」概念存在）。
- **原阻断点（已消解）**：数据源「未拍板」曾是延迟理由；再分析判定 released-artifact 模型即数据源，无需新存储，端点纯读、改动局部。

**Steelman**：canary 回滚闭环最后一环，产品价值明确。

**False-Steelman（原支持，已推翻）**：数据源未定导致无法落地——已消解。

**裁定：FILL/KEEP（再分析反转，原 NOT-NEEDED-NOW）** —— 设计草案已实质（`release-governance.md` O-38 含取数方案/路由/验收 gate）。

---

### O-39 运行级超时 / 截止（F4.3）— `release-governance.md`

**代码链（2026-10-26 再分析：语义已定）**
- 改动 = PipelineRun 级 `TimeoutSeconds` 字段 + reconciler 终止逻辑（参照任务级 `timeoutSeconds`，`API-REFERENCE.md:152`）。
- 执行点：hub `internal/pipeline` run 状态机/ticker 校验 `startedAt + TimeoutSeconds < now()` 且非终态 → 置 `failed`（reason=PipelineRunTimeout）。
- **原阻断点（已消解）**：超时后 cancel/failed 语义「未拍板」；再分析固定为 `failed`（与任务级超时不致命但 PipelineRun 级视为失败一致），UI 呈现 failed reason，不再等产品决策。

**Steelman**：长尾/卡死 run 占用 target 与配额，加超时是防御性增益。

**False-Steelman（原支持，已推翻）**：终止语义与 UI 是产品决策——已固定为 failed，可落地。

**裁定：FILL/KEEP（再分析反转，原 NOT-NEEDED-NOW）** —— 设计草案已含字段/终止语义/验收 gate。

---

### O-40 targets 扩 access_mode（F2.1）— `target-runtime.md`

**代码链（2026-10-26 再分析：可落地）**
- 改动 = `Target` 加 `AccessMode`（agent/kubeconfig/ssh，默认 agent）+ `CredentialRef`；`internal/target/models/target.go:12` 当前仅有 `TargetKind` 与 agent 通道字段，无 `access_mode`。
- 注册入口：`internal/target/handler` 加 access_mode 与 credentialRef 一致性校验（kubeconfig/ssh 必填且凭据存在）。
- 既有 agent 通道：`Target.RunnerCredential`（`target.go:28-32`）是 WS 鉴权身份源，access_mode 字段对其透明；非 agent 模式不生成 RunnerCredential。
- **原阻断点（已消解）**：「非 agent 目标是否需 hub 持久注册 + 凭据引用模型」未拍板；再分析判定落 `targets` 表 + `credentialRef` 引用即答案，schema 级但局部、可逆。

**Steelman**：当前 agent-only 的 target 模型是 console 纳管非 agent 目标的真实阻塞。

**False-Steelman（原支持，已推翻）**：纯产品决策——已落为具体 schema 改动 + 一处校验，agent 路径不变。

**裁定：FILL/KEEP（再分析反转，原 NOT-NEEDED）** —— 设计草案已含字段/迁移/校验/验收 gate。

---

### O-41 同 pipeline 并发 / 排队策略（F4.2）— `target-runtime.md`

**代码链（2026-10-26 再分析：可落地）**
- 改动 = pipeline 定义加并发策略枚举（Allow/Queue/Forbid，默认 Allow）+ 上限 N；hub `internal/pipeline` 创建 run 时查同 pipeline 活跃 run 数。
- 执行点：Forbid → 拒创建 `409`；Queue → 新 run 标 `pending_queue`，前序终态后由 reconciler 唤醒；Allow 无约束。
- **原阻断点（已消解）**：「允许并发还是串行排队」未拍板；再分析固定为三枚举，默认 Allow 保兼容，可由 hub 侧 run 创建守卫低成本落地。

**Steelman**：同一 pipeline 并发多 run 会争抢资源与重复部署，需约束。

**False-Steelman（原支持，已推翻）**：纯产品决策——已固化为枚举 + 守卫，非开放问题。

**裁定：FILL/KEEP（再分析反转，原 NOT-NEEDED）** —— 设计草案已含策略/守卫/验收 gate。

---

## Part B — 其余 §2 开放项（O-1/O-4/O-5/O-16/O-17/O-18/O-22/O-25–O-30）

| # | 项 | 性质 | 文档命运 | 理由（钢人结论摘要） |
| -- | -- | -- | -- | -- |
| 1 | install/upgrade 执行器 | 代码侧已完成 | **NO-DOC** | 代码已落盘，仅 E2E 升级实跑留待下一轮；STATUS + `runner/features` 已覆盖 |
| 4 | Casbin / 复杂策略引擎 | 条件未触发 | **NO-DOC** | 现存策略均可 `resource:action`+角色表达；首条无法表达时再立项（ACCOUNT-PERMISSION-MODEL §5.2 判据） |
| 5 | 集群离线告警规则 | 规则落地 + promtool 验证 | **NO-DOC** | 代码/规则已完成并验证；通知消费端已就（#7） |
| 16 | TaskRun 产物/结果落库 | 协议预留（v3 裁定） | **NO-DOC** | 独立新表判为重复，裁定不建；回流通道保留协议预留（`shared/runner-reflux-spec.md` §4/§12） |
| 17 | 软件包版本选择 / 制品→发布联动 | 最小版已落地 | **NO-DOC** | 最小版已 kind 实测通过；完整联动留守产品形态定稿 |
| 18 | 专用构建环境模板 | 最小版已落地 | **NO-DOC** | 任务级 privileged 贯通；dind/cind 模板库属产品功能，等需求 |
| 22 | HARBOR 集成余量 | ①③ 收口 | **NO-DOC** | ② Build→Harbor 由 B2 决议维持登记；权威见 `HARBOR-REGISTRY-INTEGRATION` + `shared/features/registry-replaceable.md` |
| 25 | 弱口令/默认口令整改 | 安全缺口·部分裁定 | **NO-DOC** | harbor 已解耦随机口令；keycloak 强初始口令 + 首登改密已落地；生产 hardening 归 O-29 |
| 26 | 备份策略缺失 | 运维缺口 | **NO-DOC** | 运维策略文档（runbook）范畴，非代码设计文档；与 O-37 同批 |
| 27 | 证书续期策略 | 运维缺口 | **NO-DOC** | 运维策略；正规 CA 引入归 O-29 |
| 28 | CI / 自动化门禁缺失 | 工程化缺口 | **NO-DOC** | CI 配置范畴，非特性设计文档 |
| 29 | harbor 正规 CA + private | 安全/接入缺口 | **NO-DOC** | 阻塞于 chart `imagePullSecrets`；权威见 `registry-replaceable.md` |
| 30 | 权限控制下一优先 | 特性下一优先 | **NO-DOC** | 权限模型已实现；入口按权限隐藏等产品决策留守（§3）；启动时进特性文档 |

**结论**：O-1/O-4/O-5/O-16/O-17/O-18/O-22/O-25–O-30 均**不需要独立设计文档**——要么代码已完成、要么条件未触发/运维策略范畴、要么已有权威文档覆盖。STATUS 条目即其权威跟踪。

---

## 汇总裁定

| 文档 | 覆盖项 | 裁定 | 动作 |
| -- | -- | -- | -- |
| `plans/runner-hardening.md` | O-31/O-32/O-33 | **FILL/KEEP** | 保留；修正 O-33 现状表述漂移 |
| `plans/observability-security.md` | O-34/O-35 | **FILL/KEEP** | 保留；建议补强两节首步验收项 |
| `plans/notification-webhook.md` | O-36 | **FILL/KEEP** | 保留；建议首步补反向追踪 + 失败吞错契约单测 |
| `plans/data-lifecycle.md` | O-37 | **FILL/KEEP（再分析反转，原 NOT-NEEDED-NOW）** | 占位升格为实质设计草案；STATUS 保留为状态权威 |
| `plans/release-governance.md` | O-38/O-39 | **FILL/KEEP（再分析反转，原 NOT-NEEDED-NOW）** | 占位升格为实质设计草案；数据源/语义已定 |
| `plans/target-runtime.md` | O-40/O-41 | **FILL/KEEP（再分析反转，原 NOT-NEEDED）** | 占位升格为实质设计草案；access_mode/并发枚举已可落地 |

---

## 文档漂移修正（已就地执行）

- `plans/runner-hardening.md` O-33「现状/证据」行原称「WS 网关仅校验全局 GATEWAY_TOKEN + 自报 X-Target-Name」——与 `gateway.go:129-137` 已实装三态鉴权不符。已修正为：三态鉴权已落地（见 `runner/features/per-target-auth.md`），O-33 为**加法**缩窄（强制 enroll token + vendor/region 白名单）。

---

## 再分析反转（2026-10-26）

原 O-37/O-38/O-39/O-40/O-41 判为 `NOT-NEEDED(-NOW)`，理由集中于「策略/语义/产品决策未拍板 → 无法落地、只能写占位」。本轮 source-grounded 重读代码后，**每个原「阻断点」均已被具体代码方案消解**：

| 项 | 原延迟理由 | 再分析消解方式 | 代码证据 |
| -- | -- | -- | -- |
| O-37 数据生命周期 | 保留基线未拍板 | 默认 0=关闭 + 三档 retention 配置；仅删终态+超龄双保险 | `internal/artifact/service/gc.go`（ArtifactGC 范本）、`internal/config/config.go:107-124` |
| O-38 可部署版本端点 | 版本数据源未定 | released-artifact 即数据源，纯读端点 | `internal/component/handler/component.go:22`、`config_version.go:34` |
| O-39 运行级超时 | cancel/failed 语义未定 | 固定为 `failed(reason=PipelineRunTimeout)` | `API-REFERENCE.md:152` 任务级 timeoutSeconds 范式 |
| O-40 access_mode | 非 agent 目标注册模型未定 | `targets` 表 + `credentialRef` 引用；agent 路径透明 | `internal/target/models/target.go:12,28-32` |
| O-41 并发策略 | 并发/排队语义未定 | 三枚举 Allow/Queue/Forbid，默认 Allow | runner 无状态 worker 拉 Pending（`internal/controller`） |

**裁定变更**：五项均由 `NOT-NEEDED(-NOW)` → `FILL/KEEP`；对应 `plans/data-lifecycle.md`、`plans/release-governance.md`、`plans/target-runtime.md` 已从空占位改写为含 `文件:行号` 证据 + 改动点 + 验收 gate 的实质设计草案。STATUS 中相应条目状态同步由「NOT-NEEDED-占位」改为「设计草案已就绪，待落地（TO-LAND）」。
