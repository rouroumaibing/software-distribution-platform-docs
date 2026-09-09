# [SDP-RUNNER-001] [Tech Story] Runner 执行平面（K8s Operator）实现

> 配套文档：`STORY-hub-implementation.md`（控制面接线层）。本 Story 覆盖 M1 全链路的 **Runner 侧**：接收 Hub 下发 → 落地 CRD → DAG 调度 → 任务执行（Job/Deploy/Approval）→ 状态/审批回写 Hub。
>
> **项目目标（对齐 console / hub）**：runner 是 SDP 的执行平面，把 hub 下发的流水线 DAG 在目标集群真正执行——构建（Build Job）、施加发布（Release chart/manifest + 金丝雀）、人工卡点（Approval）——从而让"界面触发一次发布"端到端跑通到多套环境。它支撑 console 定义的 4 类标准流水线（日常 / 版本归档 / 转测 / 生产，见 console `CONSOLE-UI设计文档.md` §1.1）。落地顺序：先贯通基本功能（R1–R3 生产化收尾），**权限管控紧接着由 hub 侧 G7 统一落实**。

## 1. 元信息与业务价值 (Context & Value)
- **类型**: [x] Tech Story (架构/重构/技术债)   [ ] Biz Story (业务)
- **责任人**: PO: @rouroumaibing | Dev: @rouroumaibing | QA: @rouroumaibing
- **故事点/复杂度**: [ L (8分) ] —— 核心执行链路，跨 dispatch / 3 个 controller / canary 引擎 / 长连接回写。
- **业务/技术目标**:
  - As a **Hub（控制平面）/ 流水线触发方**,
  - I want to **把一条已解析的流水线 DAG 安全地下发到目标集群的 Runner，由它落地为 K8s CRD 并真正执行（脚本 Job、审批门禁、金丝雀发布），再把每个节点的实时状态回写给我**,
  - So that **"点击触发"能端到端跑通，而不只是落一条 Pending 历史记录**。
- **关键指标/埋点**: 无（M1 以链路打通为验证目标；监控见 §3 工程护栏）。

### 1.1 本次文件清单（均为新增/接线，未重写既有业务逻辑）
- `cmd/runner/main.go` —— 入口装配：manager + 长连接 + 注册两个下发 handler + 注册 3 个 reconciler（原 `MessageApplyPipelineRun` handler TODO 已消除）。
- `internal/dispatch/apply_handler.go` —— 解析 `ApplyPipelineRunPayload`，幂等创建 `PipelineRun` CR（先 ensure namespace）。
- `internal/dispatch/approve_handler.go` —— 解析 `ApproveTaskPayload`，按 `sdp.io/pipeline-run`+`sdp.io/task` 标签定位 Approval TaskRun，写入 `ApprovedBy`/`RejectedBy`，达到 `RequiredCount` 置 Succeeded。
- `internal/controller/pipelinerun_controller.go` —— DAG 调度（纯函数 `findRunnableTasks`/`dependenciesSatisfied` 等）+ 每次状态变更后异步经 `conn.Send(MessageStatusUpdate, …)` 上报 Hub。
- `internal/controller/taskrun_controller.go` —— Build→Job（内联命令或脚本）、Release→chart/manifest 施加（带 `RolloutSpec` 时走 `reconcileDeploy` 创建/持有 `Rollout` 并映射 Phase 回 TaskRun）、Approval 初始化 `Status.Approval`。
- `internal/controller/rollout_controller.go` —— 管理 stable + canary 两个 Deployment 与 `-sdp` Service，按 canary 引擎决策做副本切分。
- `pkg/canary/engine.go` —— 纯逻辑金丝雀引擎（与 K8s 解耦，便于单测）：按步缩放权重、等 canary Pod Ready 再进阶、Pause 步等待、ReplicaFailure 自动回滚。

### 1.2 关键契约修正（含一处必要 Hub 改动）
原 Hub `gateway.Dispatch` 只下发 `PipelineRunSpec`，Runner 不知道该用什么 CR 名（而 Hub `ApplyStatus` 靠 `CRName` 回写）。本次把线协议升级为 `ApplyPipelineRunPayload{Name, Namespace, Spec}`，并同步改了 Hub 的 `gateway.Dispatch` / `Dispatcher` 接口 / `Trigger` 下发 `{Name: run.CRName, Namespace: run.CRNamespace, Spec}`，使两端名字对齐、状态可正确闭环。

---

## 2. 验收标准 (Acceptance Criteria - AC)
> QA 依据以下内容编写测试用例。已实现项标 ✅，待 Hub 侧补齐路径的标 🚧。

- [x] **AC-01 (正常路径 - 下发落地)**: Given Hub 通过长连接发来 `apply_pipeline_run` 帧（含 Name/Namespace/Spec），When Runner 的 `ApplyHandler` 收到，Then 在目标 namespace 幂等创建一条 `PipelineRun` CR（重连重发不重复调度），并打 `sdp.io/cluster` 标签/注解。
- [x] **AC-02 (DAG 调度)**: Given `PipelineRun` CR 已存在，When `PipelineRunReconciler`  reconcile，Then 仅对"依赖全部 Succeeded"的节点创建 `TaskRun`（名称 `{pipelineRunName}-{taskName}`），其余保持 Pending；终态后不再调度。
- [x] **AC-03 (Build 任务执行)**: Given 一个 Build 类型 TaskRun 变为 runnable，When `TaskRunReconciler` 处理，Then 构建 Job（init 容器 git checkout + 主容器 `sh {ScriptPath} {ScriptArgs…}` 或内联 `command`/`args`）并 `ownerReference` 挂载；Job Succeeded→TaskRun Succeeded，Failed 按 `RetryPolicy` 退避重试，`RetryCount` 耗尽→Failed。成功/失败只看 Job 退出码，不解析输出内容。
- [x] **AC-04 (审批门禁闭环)**: Given Approval 类型 TaskRun 初始化出 `Status.Approval`，When Hub 经 `approve_task` 帧回写决策，Then `ApproverHandler` 幂等累加 `ApprovedBy`，达到 `RequiredCount` 置 Succeeded（DAG 继续）；任一 `Rejected`→TaskRun Failed（PipelineRun 跟随 Failed）。
- [x] **AC-05 (Release / 金丝雀)**: Given Release 类型 TaskRun 且带 `RolloutSpec`，When `reconcileDeploy` 创建 `Rollout` 并 watch，Then `RolloutReconciler` 按 `RolloutSpec.Steps` 推进：缩放 canary 副本至步权重、等 canary Pod Ready 再进阶、Pause 步等待；canary Deployment `ReplicaFailure`→自动回滚置 `Degraded`；`RolloutHealthy`→TaskRun Succeeded。不带 `RolloutSpec` 的 Release 走 Job 直接施加 chart/manifest。
- [x] **AC-06 (状态回写)**: Given 任意 `PipelineRun` 状态变更，When `PipelineRunReconciler.updateStatus` 调用，Then 经长连接异步发 `MessageStatusUpdate`，其 `PipelineRunName` == CRName（Hub 据此命中 run 行）；不阻塞 reconcile 主循环。
- [x] **AC-07 (无 Runner 降级)**: Given Hub 触发时目标集群无在线连接，When `gateway.Dispatch` 找不到 conn，Then 返回 `ErrNoRunner`，Hub 侧 `Trigger` 将 run 标记 Failed 并返回 503（已在 hub story AC 覆盖）。
- [x] **AC-08 (非法输入)**: Given `ApplyPipelineRunPayload.Name` 为空 或 `ApproveTaskPayload` 缺 `pipelineRunName`/`taskName`，When handler 解析，Then 返回明确错误（`errMissingName` / `approve payload needs ...`），不创建脏对象。

---

## 3. 稳定性与工程护栏 (Engineering & Stability Guardrails)
> L 级 Story 全量填写。

- **[x] 资损与网络安全 (Security)**
  - 敏感数据脱敏: 不涉及（Runner 不持有用户手机号/身份证）。
  - **集群凭证安全**: `CLUSTER_AUTH_TOKEN`、`HUB_GATEWAY_URL`、`CLUSTER_NAME` 仅来自环境变量，不落盘、不进 CRD、`keycloak_id` 类比 Hub 不序列化。git 凭据通过 `RepoSource.SecretRef` 引用目标 namespace 内既有 Secret，**Hub 不在线上明文下发凭证**（见 `RepoSource.SecretRef` 注释）。
  - 幂等创建：重复下发不重复调度，防重提交即"下发多次=创建一次"。
- **[x] 高并发与限流降级 (High Availability)**
  - 核心链路 Peak QPS: 默认普通（事件驱动 reconcile，非高 QPS 服务）。
  - 降级/兜底: 长连接不可用时，CRD 已落地的运行仍可本地继续推进（reconcile 不依赖连接）；状态上报 `go func()` best-effort，连接断开时仅记日志不阻塞主链路。
  - **多副本 HA**: `cmd/runner/main.go` 支持 `LEADER_ELECTION=true`，基于 K8s Lease 自动选主，无需 etcd/Redis 额外组件。
  - 动态开关: 不涉及（M1）。
- **[x] 可服务性与监控 (Serviceability)**
  - 核心日志: 全链路带 `cluster`/`pipelineRunName`/`taskName` 上下文（如 `dispatch: created PipelineRun ... on cluster %s`、`rollout: scale %s failed`），可经 TraceID 关联。
  - 监控告警: M1 尚未接入 Prometheus；可观测性依赖 `kubectl get pipelinerun/taskrun/rollout`（status 已含 phase/weight/step 摘要）。⚠️ 指标埋点为后续待办。

---

## 4. 技术契约与接口设计 (Technical Contract)

### 4.1 Hub ↔ Runner 线协议（共享 `api/v1alpha1`）
帧结构: `Message{ Type MessageType, Payload json.RawMessage }`。

| 方向 | Type | Payload 类型 | 说明 |
|------|------|-------------|------|
| Hub→Runner | `apply_pipeline_run` | `ApplyPipelineRunPayload` | 下发流水线；Name/Namespace 必须 == Hub `pipeline_runs` 的 `CRName`/`CRNamespace` |
| Hub→Runner | `approve_task` | `ApproveTaskPayload` | 回写审批决策（批准/拒绝） |
| Runner→Hub | `status_update` | `StatusUpdatePayload` | 每次状态变更上报；`PipelineRunName`==CRName |
| Runner→Hub | `log_chunk` | `LogChunkPayload` | 实时日志分片（M1 已定义类型，发送侧见后续待办） |
| Runner→Hub | `heartbeat` | （空） | 保活，Hub 标记集群在线 |

**ApplyPipelineRunPayload**: `{ name, namespace, spec: PipelineRunSpec }`
**ApproveTaskPayload**: `{ pipelineRunName, taskName, approver, rejected? }`
**StatusUpdatePayload**: `{ clusterID, pipelineRunName, pipelineRunNamespace, phase, message?, startTime?, completionTime?, tasks: TaskRunStatusSummary[] }`

### 4.2 数据库/缓存变动 —— Runner 的"表"即 K8s CRD（etcd 持久化）
> ⚠️ **重要说明**: Runner 是 K8s Operator，**不连接任何关系型数据库**。其全部持久化状态由 3 个自定义资源（CRD）承担，物理存于 K8s 集群的 etcd。这与 Hub 的 Postgres 20 张表是**两套独立的存储**：Hub 存"历史/审计/权限"（SQL），Runner 存"实时执行状态"（CRD/etcd）。二者通过 `CRName`/`CRNamespace` 关联。

以下为 3 个 CRD 的"建表"（schema）设计，字段类型/枚举均对照 `api/v1alpha1/*_types.go` 核实。

#### 表 1: `PipelineRun`（根执行对象，对应一条流水线运行）
| 字段 | 类型 | 约束/索引 | 说明 |
|------|------|----------|------|
| `metadata.name` | string | 唯一（namespace 内） | == Hub `pipeline_runs.CRName`；格式由 Hub 生成 |
| `metadata.namespace` | string | — | == Hub `pipeline_runs.CRNamespace`；约定 `{tenant}-{project}-{env}` 或 `sdp-run` |
| `metadata.labels[sdp.io/cluster]` | string | 索引 | 标记归属集群 |
| **Spec** | | | |
| `spec.pipelineRef` | string | 可选 | 可复用流水线定义名（仅展示/审计，Runner 不拉取） |
| `spec.tasks[]` | PipelineTaskSpec | MinItems=1 | 已完全解析的 DAG 定义（含跨阶段 + 阶段内 Serial 的 `DependsOn`，由 hub `buildSpec` 推导；见 §4.3 / [hub 数据模型 §6.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)） |
| `spec.repo` | *RepoSource | 可选 | 默认 checkout 源（任务可覆盖） |
| `spec.params[]` | Param{name,value} | — | 参数，下发前已由 Hub 注入命令/env |
| `spec.tenantID/projectID/environmentID` | string | — | 多租户上下文，避免回 Hub 往返 |
| `spec.targetNamespace` | string | — | Job/TaskRun 创建所在 namespace |
| `spec.serviceAccountName` | string | 可选 | 任务 Pod 使用的 SA |
| `spec.timeoutSeconds` | int64 | 默认 0=不限 | 整条流水线超时 |
| `spec.triggeredBy` | string | 可选 | 触发人（审计） |
| **Status** | | | |
| `status.phase` | enum | Pending/Running/WaitingApproval/Succeeded/Failed/Cancelled | 整体阶段 |
| `status.startTime/completionTime` | *Time | — | 起止时间 |
| `status.tasks[]` | TaskRunStatusSummary | — | 每个 DAG 节点进度摘要（按 Name 对齐 Spec） |
| `status.currentApproval` | *ApprovalStatus | — | WaitingApproval 期间非空 |
| `status.observedGeneration` | int64 | — | 标识 Status 是否反映最新 Spec |
| `status.message` | string | — | Failed/Cancelled 人类可读原因 |
| `status.conditions[]` | metav1.Condition | — | 标准条件 |

#### 表 2: `TaskRun`（DAG 单节点执行对象，PipelineRun 的 owned 子资源）
| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `metadata.name` | string | `{pipelineRunName}-{taskName}` | 唯一 |
| `metadata.labels[sdp.io/pipeline-run]` | string | 索引 | 归属 PipelineRun（审批 handler 据此定位） |
| `metadata.labels[sdp.io/task]` | string | 索引 | 任务名（审批 handler 据此定位） |
| **Spec** | | | |
| `spec.pipelineRunRef` | string | — | 父 PipelineRun 名（同时设 ownerReference） |
| `spec.taskName` | string | — | DAG 节点名 |
| `spec.type` | enum | Build/Release/Approval | 分支类型 |
| `spec.image/scriptPath/scriptArgs` | string/string/[]string | — | Build 脚本型任务执行环境（escape hatch） |
| `spec.command/args` | []string | — | Build 内联命令型任务（如 pytest/go build） |
| `spec.releaseSpec` | *ReleaseSpec | Type==Release 必填 | chart/manifest 源 + 从参数管理注入的 values |
| `spec.rolloutSpec` | *RolloutSpec | Type==Release 可选 | 金丝雀渐进发布 |
| `spec.repo` | *RepoSource | — | 任务级 checkout 覆盖 |
| `spec.produces/consumes` | []string | — | 构件产出/消费 key |
| `spec.namespace` | string | — | 实际执行 namespace（targetNamespace） |
| `spec.serviceAccountName` | string | 可选 | — |
| `spec.retryPolicy` | *RetryPolicy | — | 失败重试 |
| `spec.timeoutSeconds` | int64 | — | 单任务超时 |
| `spec.approvalConfig` | *ApprovalConfig | Type==Approval 必填 | 审批人/最少批准数/超时 |
| `spec.rolloutSpec` | *RolloutSpec | Type==Deploy 必填 | 金丝雀模板 |
| **Status** | | | |
| `status.phase` | enum | Pending/Running/Succeeded/Failed/Skipped | 阶段（Skipped=上游失败不调度） |
| `status.jobRef` | string | Normal 任务 | 创建的 Job 名 |
| `status.rolloutRef` | string | Deploy 任务 | 创建的 Rollout 名 |
| `status.podName` | string | — | 运行 Pod 名 |
| `status.startTime/completionTime` | *Time | — | 起止 |
| `status.retryCount` | int32 | — | 已重试次数 |
| `status.exitCode` | *int32 | — | 退出码 |
| `status.message` | string | — | 原因 |
| `status.logsRef` | string | — | 完整日志归档位置（M1 未启用） |
| `status.approval` | *ApprovalStatus | Approval | 该任务审批状态镜像 |

#### 表 3: `Rollout`（Deploy 任务的金丝雀发布对象，TaskRun 的 owned 子资源）
| 字段 | 类型 | 约束 | 说明 |
|------|------|------|------|
| `metadata.name` | string | == TaskRun 名 | 唯一 |
| `metadata.labels[sdp.io/pipeline-run]` / `[sdp.io/task-run]` | string | 索引 | 归属链路 |
| **Spec** | | | |
| `spec.workloadRef` | string | — | 被渐进更新的 Deployment 名 |
| `spec.stableImage/canaryImage` | string | — | 稳定/金丝雀镜像 |
| `spec.steps[]` | CanaryStep{setWeight?,pause?} | MinItems=1 | 渐进计划（按序） |
| `spec.healthCheck` | HealthCheckSpec | — | PodReady/HTTPProbe/PrometheusQuery |
| `spec.trafficRouting` | TrafficRoutingSpec | enum DeploymentWeight/IngressCanary | 流量切分方式 |
| `spec.autoRollback` | bool | 默认 true | 连续健康检查失败自动回滚 |
| **Status** | | | |
| `status.phase` | enum | Progressing/Paused/Healthy/Degraded/RollingBack | 阶段 |
| `status.currentStepIndex` | int32 | — | 当前步 |
| `status.currentWeight` | int32 | 0-100 | 当前 canary 权重 |
| `status.stableReplicas/canaryReplicas` | int32 | — | 当前两侧副本数 |
| `status.consecutiveFailures` | int32 | — | 连续失败计数 |
| `status.lastHealthCheckTime` | *Time | — | 最近健康检查时间 |
| `status.startTime/completionTime` | *Time | — | 起止 |
| `status.message` | string | — | 原因 |
| `status.conditions[]` | metav1.Condition | — | 标准条件 |

#### 4.2.1 派生原生对象（非 CRD，由 RolloutReconciler 托管）
Runner 在发布过程中还会创建/持有以下 K8s 原生对象（受 Rollout `ownerReference` 垃圾回收）：
- **stable Deployment** (`spec.workloadRef`)：稳定版本，M1 默认副本数 2（Runner 不读线上 Deployment 副本数）。
- **canary Deployment** (`{workloadRef}-canary`)：金丝雀版本，副本数 = `weightReplicas(weight, total)` = `weight*total/100`。
- **`-sdp` ClusterIP Service**：`selector: {app: workloadRef}` 同时选 stable+canary Pod，靠副本比做 **DeploymentWeight** 流量切分。

#### 4.2.2 CRD 生成与关键枚举取值
- CRD YAML 由 `controller-gen v0.21.0` 生成于 `config/crd/bases/*.yaml`（安装步骤见 §4.2.3）。
- 枚举常量（直接引用 `api/v1alpha1`）：
  - `PipelineTaskType`: `Normal` / `Approval` / `Deploy`
  - `PipelineRunPhase`: `Pending` / `Running` / `WaitingApproval` / `Succeeded` / `Failed` / `Cancelled`
  - `TaskRunPhase`: `Pending` / `Running` / `Succeeded` / `Failed` / `Skipped`
  - `RolloutPhase`: `Progressing` / `Paused` / `Healthy` / `Degraded` / `RollingBack`
  - `TrafficRoutingType`: `DeploymentWeight` / `IngressCanary`
  - `HealthCheckType`: `PodReady` / `HTTPProbe` / `PrometheusQuery`

#### 4.2.3 kubebuilder / controller-gen 安装（开发环境准备）

CRD YAML 由 `controller-gen v0.21.0` 生成于 `config/crd/bases/*.yaml`。`controller-gen` 随 kubebuilder 分发，安装步骤：

```bash
# 下载并安装 kubebuilder（自带 controller-gen）
curl -L -o kubebuilder "https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)"
chmod +x kubebuilder && sudo mv kubebuilder /usr/local/bin/
```

> 安装后 `controller-gen` 位于 kubebuilder 的 `bin/` 目录（或 `$GOPATH/bin`），由 `make manifests` 调用于生成/更新 CRD。

### 4.3 任务处理与 DAG 推进逻辑（Runner 侧；推送模型，已确认）

> Runner **不轮询 hub DB**、**不直连 Postgres**（已确认保留推送模型，见 [hub 数据模型 §6.2](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)）。Runner 只消费 hub 经 WS 推送下来的 `ApplyPipelineRunPayload{Name, Namespace, Spec}`，在集群内把 spec 落地为 CRD 并推进。

**1. 接收与落地**
- `ApplyHandler` 收到 payload → 创建/更新 `PipelineRun` CR（`metadata.name==payload.Name`，`namespace==payload.Namespace`）；若已存在则更新 Spec（**幂等重投安全**，离线集群重连补投不重复建）。

**2. 阶段间串行 + 阶段内串行/并行（统一用 `DependsOn` 表达）**
- `PipelineRunReconciler` 纯函数 `findRunnableTasks` / `dependenciesSatisfied`：仅当某 task 的全部 `DependsOn` 前驱 `Succeeded`，才创建其 `TaskRun`。
- **阶段间串行**：hub `buildSpec` 已为每个阶段首任务加"依赖上一阶段末任务"的 `DependsOn` → 自然形成阶段顺序屏障。
- **阶段内并行（默认）**：同阶段任务间无 `DependsOn` → 同时可运行。
- **阶段内串行（Stage `executionMode=Serial`，已确认 Stage 级）**：hub `buildSpec` 按 `DisplayOrder` 在同阶段任务间补 `DependsOn` 链（t1→t2→t3）→ 严格先后。
- 终态（`Succeeded`/`Failed`/`Skipped`/`Cancelled`）后不再调度新 `TaskRun`。

**3. 单节点执行（TaskRun → 实际命令）**
- `TaskRunReconciler` 按 `spec.type` 建原生对象：
  - `Normal`(Build) → K8s Job（init 容器 git checkout + 构件 fetch，主容器跑 `command`/`sh {scriptPath}`）；
  - `Deploy`(Release) → `Rollout` CR 渐进发布（`rolloutSpec`）；
  - `Approval` → **不建 Job**，挂起等 Hub 经 `approve_task` 帧回写决策（见 §4.1）。
- 失败按 `retryPolicy` 退避重试；超时按 `timeoutSeconds` 置 `Failed(Timeout)`。

**4. 状态回流（进展记在哪）**
- 每次 TaskRun/Stage/PipelineRun 状态变更，`conn.Send(MessageStatusUpdate, StatusUpdatePayload{PipelineRunName, tasks[]})` 经 WS 上报 Hub。
- Hub `ApplyStatus` 据 `CRName` 写回 `task_runs` / `pipeline_runs`（**这是进展的系统记录**）。**阶段进展由 hub 侧 `task_runs` 派生聚合**（确认不建 `stage_runs`，用户决策，见 [hub 数据模型 §6.3](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)），Runner 不维护阶段级中间表。

**5. 异常与跳过**
- 某 task `Failed` 且不可重试 → DAG 中依赖它的下游 task 标 `Skipped`（不调度）；整条 `PipelineRun` 跟随 `Failed`。
- 上游 `Skipped` 同样阻断下游，保证"阶段完成 = 全部子任务终态"的不变式。

### 4.4 授权边界（Runner 侧；不持有授权逻辑）

> 完整授权模型见 [hub 数据模型 §7](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)，前端交互见 [console 设计文档 §7.9](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/console/CONSOLE-UI设计文档.md)。本小节只界定 Runner 在授权链路中的边界。

- **Runner 只消费 hub 已鉴权下发的 spec**：`ApplyPipelineRunPayload` 由 hub 在通过 §7.5 Enforcement 后下发，Runner 不解析用户身份、不判断"谁有权触发/修改"。
- **审批决策不在 Runner**：Approval 子任务的通过/拒绝由 Hub 经 `approve_task` 帧（§4.1）下发；Runner 仅据此解除挂起或终止，不判断"谁有权审批"（防自审等规则在 [hub 数据模型 §7.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md) 落实）。
- **集群侧权限由 k8s RBAC 约束（已用）**：Hub 为每个"组件 × 环境"签发 `RoleBinding`，Runner 所用 SA 只可触碰该组件命名空间；这是 runner↔集群的部署边界闸，与"用户对组件"的业务授权（[hub 数据模型 §7.2/§7.3](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)）解耦。
- **结论**：Runner 信任 hub 下发的 spec，自身无授权逻辑、不连接 Keycloak/业务 RBAC 表；业务鉴权与审批审计全部落在 hub + console。

---

## 5. Story 级 Definition of Done (DoD Checklist)
- [x] 3-Corner 澄清通过（Hub/Runner 契约已对齐，关键决策已落 `ApplyPipelineRunPayload`）。
- [x] 静态代码扫描无 P0/P1 级安全漏洞：`go vet ./...` ✅（runner 与 hub 双模块）。
- [x] 编译通过：`go build ./...` ✅（runner 与 hub 双模块，含 `gofmt -w` 格式化）。
- [ ] 单元测试覆盖率达到团队基线：canary 引擎为纯函数已具备单测条件（M1 未补用例，待办）。
- [ ] 自动化测试用例通过 / QA 手动验收通过：M1 以"链路编译+合约闭合"为验收；端到端跑通需 Hub 触发 + 真实集群（见 §6）。
- [ ] 监控告警与降级开关在预发/灰度环境验证正常：⚠️ 监控埋点未接入（§3 已标注）。

---

## 6. 后续待办（非本 Story 范围 / 已注明 TODO）
- ✅ **Hub 审批下发路径**：Hub 侧已实现 `POST /pipelines/:pipelineId/runs/:runId/tasks/:taskName/decision`（经 `gateway.Approve` → `MessageApproveTask` 下发），与 Runner 的 `ApproveTask` handler 形成完整审批闭环（见 SDP-HUB-001 本轮补充）。
- ⬜ **实时日志**：`MessageLogChunk` / `LogChunkPayload` 类型已定义，Runner 侧 Pod 日志抓取与发送未实现。
- ⬜ **IngressCanary 路由**：`TrafficRoutingIngressCanary` 已记录但 M1 降级为副本切分；专用 canary Ingress 资源为后续项。
- ⬜ **HTTPProbe / PrometheusQuery 健康检查**：M1 实际只校验 `PodReady`；`HTTPProbe`/`PrometheusQuery` 引擎分支已留但未接真实探测。
- ⬜ **Rollout 副本数读取真实 Deployment**：M1 默认 `total=2`，未读线上 Deployment 的 `spec.replicas`。
- ⬜ **端到端验证**：需 Hub 触发 + 一个真实（或 kind）集群跑通整条 M1 链路；目前仅保证两模块编译/vet 通过。
- 关联：`STORY-hub-implementation.md`（控制面）。Console 页面与多环境为更上层 Story。
