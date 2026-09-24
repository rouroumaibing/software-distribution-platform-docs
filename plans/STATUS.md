# 平台状态总览（STATUS）— 已完成 / 未完成 / 刻意不做

> **本文件是全平台唯一的完成状态权威。** 其余任何文档（STORY / BACKLOG / 计划 / 设计文档）里的 ⬜ / 待补 / follow-up 标记，凡与本清单冲突，**以本清单为准**；文档各自只维护「行为规格」，不再维护状态判断。
> 来源：三轮 source-grounded 复核（2026-09-23 审计 → 2026-09-24 第二轮全量复核 → 2026-09-24 第三轮收口），全部结论均有 `文件:行号` 级代码证据或真集群 E2E 记录（历史过程见 `UNIMPLEMENTED-MODULES-PLAN.md` §16–§18）。
> 最后核验：2026-09-24。

---

## 1. 已完成清单

### 1.1 hub（控制面）

| 域 | 已完成项 | 证据落点 |
| --- | --- | --- |
| 服务树/组织 | 组织 CRUD + 自动建服务树；`GET /search`（N-8）+ `GET /orgs/:id/services`（N-9）；org 删除挂平台守卫 | `internal/org`、`internal/catalog`；audit §6.1 |
| 组件/环境 | 组件 CRUD + 自动 Admin 权限；删除级联校验 `409+{reasons}`；环境对接（test/exec/connection-test/parse-kubeconfig/enroll-token）；环境分组落库 | `DELETE-CONTRACT.md` §6.1、§7.12 |
| 流水线 | 版本快照 + `GET /pipelines/:id/versions/:v/diff`（C-09）；Serial 调度（C-06，hub `buildSpec` 派生紧邻依赖链）；触发走 service 校验 | `pipeline_run_serial_test.go` |
| 运行 | **取消运行中流水线**（`POST /runs/:id/cancel`，注解→reconciler 落 `Cancelled`）；**单任务重跑**（`POST /runs/:id/tasks/:name/rerun`，Failed→Running）；`GET /runs/:id/stage-progress` 聚合 | UNIMPLEMENTED §18；`e2e-cancel-rerun.sh` 真集群过 |
| 审批 | 审批下发闭环 + 防自审 + `pipeline_approvals` 审计；审批超时自动判负（B-11）；生产环境强制审批 fail-closed（B-11） | `run/service/approval_timeout.go`、`production_guard.go` |
| 日志/监控 | 实时日志落库（`pkg/logstream` 对应 hub 侧接收）；hub `GET /metrics`（`internal/metrics`） | audit §5.1 T-U6 |
| agent_ops | exec 全链路（派发→目标集群 Job→状态/日志回传→SSE `GET /agent-ops/:id/stream` + 台账 + 轮询）；install/upgrade 台账受理（202 句柄） | `internal/target/*` + `cmd/hub/agentop_dispatcher.go`；migration 0018 |
| 制品 | 签名下载（presigned / Local HMAC）；`expires_at` 保留期 GC + 孤儿对账（仅报告） | B-16；`DELETE-CONTRACT` §6.6-4 |
| 账号权限 | Keycloak 身份 + hub 唯一权限权威（D1–D6 闭，D3 删 users 表）；两层 RBAC + 平台/组件自定义角色；四张权限表 + 审计 + 权限申请审批 + 到期回收；组织 claim 接入 + 资源归属强制点；`§10 #14` 403 缺口修复 | `ACCOUNT-PERMISSION-MODEL.md`；UNIMPLEMENTED §8/§9/§12/§14 |
| 凭据 | AES-GCM 信封加密 + `10_credentials.sql` 幂等种子；Update 空值覆盖密文 bug 已修 | audit §5.1 T-U8 |
| 认证 | console↔Keycloak 真对接（公网 issuer 三方一致 + 临时密码 + 强制改密）；`GET /api/userinfo` | `KEYCLOAK.md` §6.5 |
| 版本矩阵 | `GET /package-versions`（console/hub/runner 三版本） | `internal/packageversion` |
| 数据一致性 | schema SSOT（AutoMigrate + migrations 手工层）；Artifact GC；§6.4 service→component 级联软删（真集群验证） | `DATA-MODEL.md` §9.0 |

### 1.2 runner（执行引擎）

| 域 | 已完成项 | 证据落点 |
| --- | --- | --- |
| DAG 调度 | Reconcile 增量推进；失败短路；Serial/Parallel（C-06）；Test/Release/Approval 四型任务 | `internal/controller` |
| 日志 | Pod 日志实时抓取 → `log_chunk` 回流（B-02，`SDP_LOG_STREAMING` 降级开关） | `pkg/logstream` |
| 灰度 | IngressCanary（canary Ingress 权重注解，B-04）；副本切分；健康检查 HTTP/Prometheus + 连败自动回滚（B-05）；真实副本数（B-06）；暂停/晋升/回滚 | `pkg/canary` + `rollout_controller.go` |
| 协议 | 取消（`cancel_pipeline_run` 注解模式）；单任务重跑（含下游 + Failed 复活）；重连对账 ResyncAll（C-05）；快照固化（C-03） | `api/v1alpha1` + `internal/dispatch` |
| agent_ops | exec 执行器（目标集群 Job + 日志差量回传 + 状态机回传）；`SDP_AGENT_EXEC_IMAGE/TIMEOUT` 可配 | `internal/agentops` |
| 运维 | `pkg/metrics` Prometheus 埋点；RBAC 含 ingresses（E2E 揪出的起不来 bug 已修）；manager 重试 SkipNameValidation（D-01 修复）；取消/重跑/日志/agent_ops 真集群 E2E 全过 | UNIMPLEMENTED §16/§18 |

### 1.3 console（前端）

| 域 | 已完成项 | 证据落点 |
| --- | --- | --- |
| 导航/搜索 | 服务树懒加载 + ⌘K 全局搜索（C-01）；暗色主题（C-02） | `ServiceTreeView`、`CommandPalette.vue` |
| 流水线 | 全生命周期 UI（C-12）；配置派生表单；版本历史/对比面板（C-09） | `pnpm test:pipeline` 41 条 |
| 运行监控 | DAG 执行图 + 实时日志面板 + 运行页审批；取消/重跑按钮 | `RunMonitorView.vue` |
| 灰度监控 | 金丝雀步骤器（10/50/100）+ 暂停/晋升/回滚 | `ReleaseDetailView.vue` |
| agent_ops | 台账页 + SSE 消费端（T-U3） | `AgentOpsView.vue` + `agent-op-smoke.mjs` 14 检查 |
| 凭据 | 凭据管理 UI（平台管理第 3 Tab，T-U8） | `CredentialsView.vue` |
| 认证 | Keycloak 登录 + 路由守卫双模；`/login-hint` 临时密码说明页 | `stores/auth.ts`、`LoginHintView.vue` |
| 权限 UI | 平台权限页（PlatformAdminView）+ 组件 PermissionsTab；敏感配置打码 | C-10/B-11 消费端 |

### 1.4 跨组件验证

| 项 | 结果 |
| --- | --- |
| B-07 端到端（kind 实跑） | ✅ `e2e-smoke.sh` PASS=15 FAIL=0；run `Running→Succeeded`；揪出并修复 3 个真 bug |
| 取消/重跑 E2E | ✅ 真集群验证（`e2e-cancel-rerun.sh`） |
| agent_ops exec E2E | ✅ 202→Job→succeeded→SSE 重放/实时推流→PG 落库 |
| console↔Keycloak E2E | ✅ auth ON 全链（401/200/组预置/临时密码拦截） |
| gate | hub/runner `go build/vet/test`+gofmt 全绿；console `vue-tsc/build`+7 套冒烟全绿 |

---

## 2. 未完成清单（已登记，非静默缺口）

| # | 项 | 性质 | 前置 / 处置 |
| --- | --- | --- | --- |
| 1 | **install/upgrade 执行器**（§9.9 接入引导） | 设计裁定留守 | 台账已受理（queued）；执行器依赖 enroll-token 凭据流转 + runner 自升级 SA 权限两个产品级前置 → 需单独立项 |
| 2 | **Agent 版本兼容性检查 / per-target 身份** | 登记 | 前置 = 版本矩阵（已落）+ `agent_version` 上报 |
| 3 | **平台自升级审批流 + 到期回收**（E2E P6 残留） | 登记 | 与 #1 同域（§9.9）；C-10 已提供平台 RBAC 表达能力 |
| 4 | **Casbin / 复杂策略引擎**（B-19） | 条件触发 | 当且仅当出现首条 `resource:action` 无法表达的策略才引入（`ACCOUNT-PERMISSION-MODEL` §5.2） |
| 5 | **集群离线告警规则 + 降级开关预发/灰度验证** | 运维环境项 | 埋点已接入（hub+runner `/metrics`）；规则与验证属部署环境 |
| 6 | **console token 静默刷新** | 登记 | 现依赖 Keycloak SSO 会话 |
| 7 | **通知中心**（顶栏铃铛） | 登记 | 需后端通知端点 |
| 8 | **canary 精确权重回传**（`Rollout.Status.CurrentWeight` → console） | 增强项 | 现为步骤器近似展示；代码注释已标后续增强 |
| 9 | **域内级联软删上层**（org→service→制品/对象） | 部分 | service→component 已落并真集群验证；上层以 `DELETE-CONTRACT` §6.4 为准 |
| 10 | **金丝雀 P4 真流量回 0% / P5 全链路灰度** | 验证项 | 需目标集群带真实 workload |
| 11 | **swagger 新端点再生成** | 工具项 | 本机无 swag CLI；不影响编译，下次有 CLI 环境跑 `swag init` |
| 12 | **删除校验同事务化**（`DELETE-CONTRACT` §4.2 步骤 5） | 加固项 | 校验与删除现不在同一事务，并发插入理论上可绕过校验；窗口小、登记待排期 |
| 13 | **console 服务树删除入口 UI** | 登记 | 后端契约已备（`409+{reasons}`，`DELETE-CONTRACT` §1.3）；新 console（Vue3）无删除入口（old 版 `delDetail`/`mockDeleteNode` 已随重写移除） |
| 14 | **releases 视图筛选后端支持**（`scope` / `state=paused`） | 登记 | `GET /releases` 已存在但仅支持 `pipelineRunId`；`paused` 属 Rollout 任务级状态、不在 `PipelineRunPhase` 枚举，需设计（CONSOLE-UI-DESIGN §7.6 / 附 A N-3） |
| 15 | **「待我审批」身份下推（N-2 `assignee=me`）+ 运行时间窗过滤** | 登记 | 现退化为全部待审批（CONSOLE-UI-DESIGN 附 A N-1/N-2） |
| 16 | **TaskRun 产物/结果落库**（`ResultRef`/`ArtifactRefs`） | 登记 | 跨模块：TaskRun 字段 + 协议 payload 扩展 + runner 补发（ADR-dispatch-durable-queue §6 D 项） |
| 17 | **权限对账脚本化**（`ACCOUNT-PERMISSION-MODEL` §10 门禁） | 工具项 | 对账表当前已全 ✅；脚本化为持续门禁 |

## 3. 刻意不做 / 裁定保留

| 项 | 裁定 |
| --- | --- |
| DAG 自由画布编辑器（C-08） | `CONSOLE-UI-DESIGN` §4.2：DependsOn 需求明确后评估 vue-flow |
| 产物自动删除策略 | 对账刻意只报告（防误删进行中的上传）；`expires_at` GC 已覆盖清理 |
| 拖拽式流水线编排 | 列表式编排已落地；拖拽待 DependsOn 拍板 |
| V1 `roles` / `approvals` 表删除 | 有活引用 + DROP 不可逆；真删需用户显式确认 |
| hub 用户表 / 邀请用户 / 新用户引导 | hub 无用户表（D3）；身份与组织归属由 Keycloak realm/组承担 |

---

> 状态变更纪律：新增/收口任何待办，**先改本清单**，再在对应域文档补行为规格；各文档不再自持状态标记，防止再次出现「正文过时 ⬜」。
