# 术语规范（TERMINOLOGY）

> 本文是平台术语的规范用词表，只记录现状。每个词的权威定义仍在其所属文档，本文给全限定名与落点指针。
> 引用术语时写全限定名，不裸用「环境」「组件」「目标」等单字词。

## 1. Environment 的四个含义

「环境」在平台内有四个互不等价的含义，必须按语境写全限定名。

| 规范用词 | 现状定义 | 权威落点 |
| --- | --- | --- |
| **pipeline environment**（流水线环境） | 领域对象 `environments`：挂在组件下的一行，绑定 `target_id` + `namespace`，是流水线运行级参数 `targetEnvironment` 的指向对象。dev / test / prod 在这里是用途区分，不是平台运行环境。 | `shared/DATA-MODEL.md` §9.0 术语消歧表「环境」含义 A、§9.2（`environments.target_id` NOT NULL） |
| **production target flag**（生产目标标记） | 平台级策略标记：按「目标是否关联了 production 类型环境」判定，命中则生产强审批 fail-closed，返回 `409 + reasons`（`ERR.08409005`）。不是一条环境记录，也不是部署目标本身。 | hub `run/service/production_guard.go`、`environment/repository.ProductionTargets`；编号 B-11 见 `hub/STORY-BACKLOG.md` §1；E2E 反向用例见 `shared/E2E-THREE-PIPELINES-2026-09-26.md` §3.5-4 |
| **runner EnvironmentType**（runner 环境类型枚举） | runner API 的枚举 `EnvironmentType`（`dev/test/staging/prod/canary/bluegreen`）与 `IsValidEnvironment`，用于 CR / spec 层标注任务运行环境；与 `environments` 表行不是同一层概念。 | runner `api/v1alpha1/pipelinerun_types.go`；编号 C-13 见 `hub/STORY-BACKLOG.md` §4 |
| **deployment env**（部署环境） | 运维概念：local kind 与云上托管 K8s 两套部署拓扑，含各自的镜像仓库、网关、DNS、证书链路。不是领域对象。 | `env/README.md`（local vs cloud 一页对照）；差异清单 `docs/plans/FIDELITY-KIND-VS-CLOUD-2026-10-09.md` |

写法约定：裸「环境」→ 写 `pipeline environment`；裸「生产环境」→ 按语境写 `production target flag`（策略判定）或 `production pipeline environment`（领域对象）；讲本地/云上部署时写 `deployment env`。

## 2. target / agent / runner 硬映射

| 词 | 规范所指 | 权威落点 |
| --- | --- | --- |
| **target（目标）** | `targets` 表的一行注册记录，即一个被管对象；`targetKind` = `k8s` 或 `host`，console 菜单名为「接入管理」。指被纳管对象时一律写「目标（Target）」，不写「集群」；K8s 技术词（`ClusterRole` / `ClusterIP` 等）保留「集群」。 | `shared/DATA-MODEL.md` §9.0 术语消歧表「目标」「集群」、§9.1 |
| **agent（代理进程）** | runner 进程的身份：出站回连 hub 的运行中进程，承载 `agent_version` 与心跳；hub 全局共享 `GATEWAY_TOKEN` 认证，目标身份由自报的 `name` 决定。 | `shared/DATA-MODEL.md` §9.1；`shared/ADR-0001-runner-first-connect-enrollment.md` |
| **runner（执行器）** | 执行器仓库与进程名，也是代码标识符的唯一保留名；`RunnerOp` 是 agent_ops 的操作主体。文档与代码注释统一用 `runner` / `RunnerOp` 指代执行器进程与操作，不用 `agent` 指代仓库或组件。 | `runner/README.md`；`shared/install-upgrade-executor-design.md` |
| **access（接入通道）** | 平台怎么够到目标：`access=` `agent` / `kubeconfig` / `ssh`。写通道时必须同时注明凭据归属：`agent` → 目标侧；直连 → hub 侧。 | `shared/DATA-MODEL.md` §9.0 术语消歧表「通道」、§9.5 / §9.7 |

硬映射一句话：**target = 注册行 / agent = runner 进程 / access = 通道**。agent 同时是接入通道取值与操作主体，遇歧义写全限定名。

## 3. Service / component / 组件

| 词 | 规范所指 | 权威落点 |
| --- | --- | --- |
| **components（组件）** | 领域对象 `components`：服务树叶子，绑定一个 git 仓库；文档统一写 `components（组件）`。 | `shared/DATA-MODEL.md` §9.0 术语消歧表「组件」、§1 |
| **service（服务）** | 服务树中的服务节点（`services`）。代码里 `service` 同时是架构层包名（如 `hub/internal/catalog/service`），与领域「服务树服务」同形从而出现 `ServiceService`；引用时写「服务（service，服务树节点）」或「service 包（架构层）」。 | `shared/DATA-MODEL.md` §1；`shared/ACCOUNT-PERMISSION-MODEL.md` |
| **平台组件** | hub / console 这类平台自身构件，不进服务树模型；runner 是接入侧代理组件，**不属平台自身**。 | `shared/DATA-MODEL.md` §9.0 术语消歧表「组件」、§9.3 / §9.4 |
| **Service 级变量组** | 前端需求用词：共享变量组首批落在 Service 级（Org 级强管控延后）；后端无同名资源，底层实体是 `credentials` 加待建的变量组。 | `console/features/ui-09-backend-deps-api-contract.md` 附 A 补充 N-26 |

## 4. Release / Deploy / Rollout / Canary

| 规范用词 | 所指与出现位置 | 权威落点 |
| --- | --- | --- |
| **Release** | 任务类型枚举 `Release`（声明式施加软件单元）及发布记录资源；CR 任务类型枚举为 `Build / Release / Approval / Test`（C-13）。Test 与 Build 共用脚本 Job 执行路径，按退出码判定。 | `runner/api/v1alpha1/pipelinerun_types.go`；`console/features/ui-09-backend-deps-api-contract.md` 附 D.3；`hub/STORY-BACKLOG.md` §4 C-13 |
| **deploy（部署动作）** | 文档中不作为任务类型使用。runner 施加 Release 资源的函数为 `reconcileRollout`，错误与注释统一写 Release / Rollout；描述类型与资源写 `Release`，描述灰度施加过程写 `rollout`。 | `runner/internal/controller/taskrun_controller.go` |
| **Rollout** | Rollout CR 与其状态机：`rollout_controller.go` 管理 stable / canary Deployment，字段 `RolloutSpec` / `RolloutPhase`，支持 pause / promote / rollback 与健康检查连败回滚。操作意图由 `Spec.DesiredAction` 单点表达，Status 只记录观测结果。 | `runner/internal/controller/rollout_controller.go`；`pkg/canary/engine.go`；`shared/DATA-MODEL.md` |
| **Canary** | 金丝雀策略/引擎 `pkg/canary`：按权重步进（如 10/50/100、25/50/100）+ 暂停窗口 + HTTP/Prometheus 健康检查 + Ingress/DeploymentWeight 流量切分。规范用词 `Release` + `Canary`，不用 deploy 指代类型或策略。 | `runner/pkg/canary/engine.go`；`shared/E2E-THREE-PIPELINES-2026-09-26.md` §9；`plans/STATUS.md` §1.4 |

## 5. pipeline run / task / job

| 规范用词 | 所指与生命周期 | 权威落点 |
| --- | --- | --- |
| **pipeline run（运行）** | `PipelineRun` CR / `pipeline_runs` 一行：一次触发的执行实例，相位含 Pending / Running / WaitingApproval / Succeeded / Failed / Cancelled；可由参数决定运行级 target 与 namespace。 | `shared/DATA-MODEL.md` §6；`runner/api/v1alpha1/pipelinerun_types.go` |
| **task（任务运行）** | `TaskRun` CR / `task_runs` 一行：PipelineRun 内单个任务的执行实例，类型 Build / Release / Approval / Test；阶段运行由 `task_runs` 读时聚合（`stage-progress`），无独立 stage run 表。 | `runner/api/v1alpha1/pipelinerun_types.go`；`shared/CROSS-COMPONENT-ALIGNMENT.md` §4 |
| **job（执行 Job）** | k8s `Job`：runner 为每个 TaskRun 实际创建的工作负载，由 `BuildJobSpec` 构造；不是平台资源，不写进 `PipelineRun` / `TaskRun` 的同义词表。 | `runner/pkg/executor/job_builder.go`；`shared/ADR-dispatch-durable-queue.md` §10 |

写法约定：「运行」= PipelineRun，「任务」= TaskRun，「执行 Job」= k8s Job；不把 Job 叫任务，不把 TaskRun 叫 job。定义态的 `PipelineStage` / `PipelineTaskTemplate` 写「阶段定义 / 任务模板」，与运行态分开。

## 6. 兼容读取与编号

- 暂停计时由 `RolloutStatus.PauseStartTime` / `PauseStepIndex` 承载，reconciler 单一写入；`sdp.io/pause-start` 注解仅用于旧 CR 的一次性迁移读取，写入后即删除，不进入 `Spec.DesiredAction` 枚举。
- 已删档文档中的 `§x.y` 编号：只指向当时章节；当前状态一律以 `plans/STATUS.md` 为准，编号落点见 `docs/ID-INDEX.md`。
