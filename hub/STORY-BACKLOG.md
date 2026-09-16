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
| B-07 | **端到端验证** | 需 Hub 触发 + 一个真实（或 kind）集群跑通整条 M1 链路；目前仅保证两模块编译/`vet` 通过 | ⬜ 未做 | runner §6:197 | M1 验收 |
| B-08 | **单元测试** | 核心逻辑（`buildSpec`/`selectCluster`/`ApplyStatus`/canary 引擎）具备单测条件，M1 未补用例，当前以 `go build`+`go vet` 作门禁 | ⬜ 待补 | hub §5:371, runner §5:185 | 质量基线 |
| B-09 | **监控告警与降级开关验证** | 依赖后续 Epic 5 离线告警与 console 灰度监控；Prometheus 指标埋点未接入 | ⬜ 未做 | hub §5:374, runner §5:187, hub §3:66 | Epic 5 |
| B-10 | **QA 负责人待补** | Story 责任人 QA 字段、（3-Corner 澄清）QA 待补 | ⬜ 待补 | hub §1:13, hub §5:370 | 协作流程 |
| B-11 | **主规格细化项** | 审批超时 / 生产强审批 / 产物签名下载 / 版本对比 / 自定义角色等主规格 ⬜ 项 | ⬜ 未做 | hub §6:384 | 多 Epic |
| B-12 | **后端 DELETE 级联校验** | `services`/`components` 的 Delete handler 无级联校验（`catalog/service/service.go:31`、`component/service/component.go:98` 均 TODO 直删）；`pipelines` 已校验但与 N-5 契约语义不符（应仅拦 running/waiting）；`APIError` 无 `reasons[]` 字段 → 契约 `409 + {reasons}` 无法表达。计划见 `hub/DELETE-CONTRACT.md` §4 | ⬜ 未做 | DELETE-CONTRACT §4 | N-15 / N-5 |
| B-13 | **环境分组落库** | console 环境页/配置页左侧的"分组（类生产/生产）"只存在于原型内存（`ENV[comp].groups`），hub 无落库位置。已拍板"需要落库"：新表 `environment_groups` + `environments.group_id`（可空）。DDL + 删除语义 + gate 见 `hub/DATA-MODEL.md` §8 | ⬜ 未做 | DATA-MODEL §8 | 环境/配置 |
| B-14 | **`component_config_history` 去 FK + 快照列** | `environment_id` 现为 `NO ACTION` FK（`0002_component_management.sql:93`）→ 删环境若历史表有该环境行则 **FK 500**；而 `component_configs.environment_id` 是 `ON DELETE CASCADE` → 同一操作两种结果。且审计表无环境快照 → 溯源不健全。方案：去 FK + 加 `environment_key` 快照列（详 `DELETE-CONTRACT.md` §6.6-2） | ⬜ 未做 | DELETE-CONTRACT §6.6-2 | 配置审计 |
| B-15 | **stages/templates 软删标记 + 父存在性校验 + `pipelines` 唯一约束** | (a) `pipeline_stages`/`pipeline_task_templates` 无 `deleted_at`，pipeline 软删后其行物理留下（且 cascade 不触发）→ 孤儿可见固定通道；(b) `StageHandler.Create`/`List` **不校验父存在**，可在已软删 pipeline 下新建阶段；(c) `pipelines` 的 `unique(component_id,name)` 不含 `deleted_at` → 软删后建不回同名（500） | 🟡 **(a)(b)(c) 已落地（2026-09-16）**；`deleted_at` 待拍板 | DELETE-CONTRACT §6.6-3 | 流水线定义 |
| B-16 | **Artifact 治理（源头 + 对账）** | (a) `_ = s.store.Delete()` 吞错无重试；(b) hub **无任何 GC**，`expires_at` 全仓无读取点（DDL 注释承诺的后台清理任务不存在）；(c) `artifacts.component_id` 是 cascade 但 components 软删 → 每次删组件批量留孤儿（行 + 对象）。顺序：先堵源头（级联 + 清理标记 + `expires_at` 生效），后做对账且**仅报告不自动删** | ⬜ 未做 | DELETE-CONTRACT §6.6-4 | 产物管理 |

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

- **真实未做项**：16 项（B-01 ~ B-16）。其中 ✅ 已完成 2 项（B-03 审批下发；B-15 的 (a)(b)(c) 三项修复，2026-09-16）、🟡 部分完成 1 项（B-15 仍余 `deleted_at` 待拍板）、⬜ 未做/待补 14 项。
  - **本轮（2026-09-16）新增 4 项**：B-13 ~ B-16，来源为删除检查项梳理 + 三项双向钢人论证（`hub/DELETE-CONTRACT.md` §6.5~§6.7、`hub/DATA-MODEL.md` §8.8）。
  - **本轮（2026-09-16）落地 1 项**：B-15 的 (a) 父存在性校验 + (b) `pipelines` 改 partial unique index + (c) 模型时间列映射，见 `hub/DELETE-CONTRACT.md` §6.6-3「落地记录」。
- **过时期待办**：2 项（已在 Runner 实现中消化，待回填 Hub 文档）。
- **优先级提示**（按 M1 验收阻塞程度）：
  - 阻塞 M1 端到端验收：B-07（端到端验证）、B-03（审批下发，若用审批任务）。
  - 影响可观测/质量基线：B-08（单测）、B-09（监控告警）。
  - **数据模型/一致性（本轮新增，建议紧随 B-13）**：B-14（config_history 快照列，消除"删环境随机 500"）、B-15（**仅剩** stages/templates 补 `deleted_at`，待"是否支持恢复已删流水线结构"拍板）、B-16（artifacts 源头治理）。
  - 功能完整性：B-01/B-02/B-04/B-05/B-06/B-11/B-12/B-13。
  - 协作流程：B-10（QA 待补）。
