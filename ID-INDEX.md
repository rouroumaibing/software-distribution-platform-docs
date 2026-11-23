# 编号索引（ID-INDEX）

> 代码注释与设计文档里的外部编号，一律在本表查权威落点。本表只做「编号 → 权威文件」映射，不维护状态；状态以 `plans/STATUS.md` 为准。
> 路径相对本仓根目录（docs/）。每个编号族只列权威定义处；其余文档中的同号引用均为消费方。

## 1. 编号族总表

| 编号族 | 含义 | 权威落点 |
| --- | --- | --- |
| `B-01` ~ `B-21` | hub 实现 Backlog 待办/完成项 | `hub/STORY-BACKLOG.md` §1 |
| `C-01` ~ `C-13` | 从 FEATURE-GAP-BACKLOG 合并的补充缺口 | `hub/STORY-BACKLOG.md` §4 |
| `N-1` ~ `N-15` | console 附 A 后端依赖与待确认 | `console/features/ui-09-backend-deps-api-contract.md` 附 A |
| `N-16` ~ `N-35` | console 补全计划新增/澄清的后端依赖 | `console/features/ui-09-backend-deps-api-contract.md` 附 A 补充 |
| `G-1` ~ `G-14` | 三流水线整体 E2E 发现的代码缺口 | `shared/E2E-THREE-PIPELINES-2026-09-26.md` §6（登记）/ §9.1（修复）/ §9.3（回归）；摘要 `hub/STORY-BACKLOG.md` §5 |
| `O-17` ~ `O-42` | 平台未完成/运维/安全缺口登记 | `plans/STATUS.md` §2（状态权威）；设计草案在 `plans/` 对应文档（见 §4 本表） |
| `#1` ~ `#22` | 平台特性编号（STATUS 内部追踪号） | `plans/STATUS.md` §1.4 / §2 |
| `§N.x`（console） | CONSOLE-UI-DESIGN 章节号，拆文件后全局唯一且不变 | `console/CONSOLE-UI-DESIGN.md` §0.4 章节→文件映射；正文在 `console/features/ui-01` ~ `ui-12` |
| `§9.x`（数据模型） | 接入拓扑/术语/裁定章节 | `shared/DATA-MODEL.md` §9.0 ~ §9.11 |
| `§x.y`（已删档文档） | 指向已删档的历史计划文档章节 | 结论落点见 `plans/STATUS.md` 与各域权威文档；按根 `README.md`「已删档的历史计划文档」段处理 |

## 2. 高频单号落点

| 编号 | 定义 / 权威落点 | 说明 |
| --- | --- | --- |
| **B-11** | `hub/STORY-BACKLOG.md` §1 B-11 行 | 主规格细化项（审批超时 / 生产强审批 / 产物签名下载 / 版本对比 / 自定义角色）。该行末尾引用的 `plans/UNIMPLEMENTED-MODULES-PLAN.md §11.1` 属已删档文档；**结论落点**：`plans/STATUS.md` §1.1「审批」行（审批超时 `run/service/approval_timeout.go`、生产强审批 `production_guard.go`）与「账号权限」行（组件级角色端点），版本对比见下方 C-09，产物签名下载契约见 `shared/API-REFERENCE.md`。`plans/STATUS.md` 文首声明：旧引用中的 §x.y 均指删档文档章节，当前状态一律以 STATUS 为准。 |
| **C-09** | `hub/STORY-BACKLOG.md` §4 C-09 行 | 流水线版本历史 / 对比 / 回滚：hub `PipelineVersionService` + `GET /pipelines/:id/versions` 等端点、console `PipelineVersionPanel.vue`；状态见 `plans/STATUS.md` §1.1/§1.3。 |
| **C-03** | `hub/STORY-BACKLOG.md` §4 C-03 行 | Pipeline 触发时 stages/tasks 快照序列化固化：`PipelineVersionService.Publish` / `models.BuildSnapshot`，runner 侧快照固化见 `plans/STATUS.md` §1.2「协议」。 |
| **C-06** | `hub/STORY-BACKLOG.md` §4 C-06 行 | `ExecutionMode=Serial` 阶段内串行：hub `buildSpec` 派生紧邻前驱 `DependsOn`、runner `serialBlocked()`；状态见 `plans/STATUS.md` §1.1「流水线」/§1.2「DAG 调度」。 |
| **C-13** | `hub/STORY-BACKLOG.md` §4 C-13 行 | runner Test 类型 / `EnvironmentType`（dev/test/staging/prod/canary/bluegreen）；落地在 runner `api/v1alpha1/pipelinerun_types.go`。 |
| **N-26** | `console/features/ui-09-backend-deps-api-contract.md` 附 A 补充 N-26 行 | 普通变量 / 共享变量组实体（首批 Service 级，Org 级延后）+ 运行时参数声明 + 日志脱敏规则；底层密钥能力见同文件 N-1~N-15 表与 `shared/DATA-MODEL.md`。 |

## 3. G-1 ~ G-14 落点

定义与修复证据权威在 `shared/E2E-THREE-PIPELINES-2026-09-26.md` §6 / §9.1 / §9.3；逐项摘要在 `hub/STORY-BACKLOG.md` §5 表；验收状态在 `plans/STATUS.md` §1.4。

| 编号 | 缺口本质（现状标签） | 权威段落 |
| --- | --- | --- |
| G-1 | 执行 Job 无 ServiceAccount → Release 无部署权限 | E2E §6 G-1、§9.1 G-1 |
| G-2 | 制品登记断链 → 前端制品 Tab 恒空 | E2E §6 G-2、§9.1 G-2 |
| G-3 | 无软件包版本选择 / 制品→发布无联动（follow-up B-20） | E2E §6 G-3、§9.2 版本号行 |
| G-4 | 无构建环境选择（follow-up B-21） | E2E §6 G-4、§9.1 G-4（最小版） |
| G-5 | 参数注入断裂（hub 文本替换 + runner env 双通道） | E2E §6 G-5、§9.1 G-5 |
| G-6 | 制品下载（consume）为占位 → `POST /artifacts/storage-url` | E2E §6 G-6、§9.1 G-6 |
| G-7 | runner job 镜像硬编码裸名 → `SDP_JOB_IMAGE_*` 可配 | E2E §6 G-7、§9.1 G-7 |
| G-8 | 签名存储路由从未挂载（`localArtifactStore` 漏赋值） | E2E §6 G-8、§9.1 G-8 |
| G-9 | Release 任务丢 `ReleaseSpec` | E2E §6 G-9、§9.1 G-9 |
| G-10 | `GetOrgID` Scan 类型错 → 审批通知/审计/超时全断 | E2E §6 G-10、§9.1 G-10 |
| G-11 | console config.js 混入 YAML 注释 → 卡登录页 | E2E §6 G-11、§9.1 G-11 |
| G-12 | console↔hub ReleaseConfig 契约断裂（`repoURL`/`manifest.content`） | E2E §9.1 G-12 |
| G-13 | runner ClusterRole 权限不足 → 特权提升防护拒绝授予 | E2E §9.1 G-13 |
| G-14 | `RegisterProduced` 非幂等 → 同 key 重复 | E2E §9.1 G-14 |

## 4. O- 编号的设计文档落点

状态与结论在 `plans/STATUS.md` §2；下列文档是该编号的行为规格/设计草案，不自持状态。

| 编号 | 设计文档 |
| --- | --- |
| O-17 / O-18 / O-22 | `plans/STATUS.md` §2 行（G-3 / G-4 follow-up；HARBOR 余量见 `plans/HARBOR-REGISTRY-INTEGRATION-2026-09-28.md`、`plans/HARBOR-DEPENDENCY-GAP-2026-10-20.md`） |
| O-24 ~ O-30 | `plans/STATUS.md` §2 行；云上重置/清理见 `env/log/2026-10-20-cleanup.md` |
| O-31 / O-32 / O-33 | `plans/runner-hardening.md` |
| O-34 / O-35 | `plans/observability-security.md` |
| O-36 | `plans/notification-webhook.md` |
| O-37 | `plans/data-lifecycle.md` |
| O-38 / O-39 | `plans/release-governance.md` |
| O-40 / O-41 | `plans/target-runtime.md` |
| O-42 | `plans/GAP-GATEWAY-POLICY-2026-10-26.md` |

## 5. 使用约定

- 代码注释里出现 `B-/C-/N-/G-/O-/§` 编号时，在本表查到权威文件后直接跳该文件；不要顺着消费方的转述继续追。
- 编号定义文件与 STATUS 冲突时，以 `plans/STATUS.md` 为准；术语见 `docs/TERMINOLOGY.md`。
- 新增编号族或改动权威落点时，只在本表改一行，其余文档保留编号引用即可。
