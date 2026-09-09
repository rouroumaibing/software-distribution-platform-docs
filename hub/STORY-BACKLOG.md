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
| B-03 | **审批下发闭环** | Hub 侧补齐 approve_task 决策发送：新增 `POST /pipelines/:pipelineId/runs/:runId/tasks/:taskName/decision`，经 `gateway.Approve` → `MessageApproveTask` 下发，接上 Runner 已就绪的 `ApproveTask` handler | ✅ 已完成 | hub gateway/run svc+handler + main | Epic 7 |
| B-04 | **IngressCanary 路由** | `TrafficRoutingIngressCanary` 已记录，M1 降级为副本切分；专用 canary Ingress 资源为后续项 | ⬜ 未做 | runner §6:194 | Epic 6 |
| B-05 | **HTTP/Prometheus 健康检查** | M1 实际只校验 `PodReady`；`HTTPProbe`/`PrometheusQuery` 引擎分支已留但未接真实探测 | ⬜ 未做 | runner §6:195 | Epic 6 |
| B-06 | **Rollout 副本数读取真实 Deployment** | M1 默认 `total=2`，未读线上 Deployment 的 `spec.replicas` | ⬜ 未做 | runner §6:196 | — |
| B-07 | **端到端验证** | 需 Hub 触发 + 一个真实（或 kind）集群跑通整条 M1 链路；目前仅保证两模块编译/`vet` 通过 | ⬜ 未做 | runner §6:197 | M1 验收 |
| B-08 | **单元测试** | 核心逻辑（`buildSpec`/`selectCluster`/`ApplyStatus`/canary 引擎）具备单测条件，M1 未补用例，当前以 `go build`+`go vet` 作门禁 | ⬜ 待补 | hub §5:371, runner §5:185 | 质量基线 |
| B-09 | **监控告警与降级开关验证** | 依赖后续 Epic 5 离线告警与 console 灰度监控；Prometheus 指标埋点未接入 | ⬜ 未做 | hub §5:374, runner §5:187, hub §3:66 | Epic 5 |
| B-10 | **QA 负责人待补** | Story 责任人 QA 字段、（3-Corner 澄清）QA 待补 | ⬜ 待补 | hub §1:13, hub §5:370 | 协作流程 |
| B-11 | **主规格细化项** | 审批超时 / 生产强审批 / 产物签名下载 / 版本对比 / 自定义角色等主规格 ⬜ 项 | ⬜ 未做 | hub §6:384 | 多 Epic |

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

- **真实未做项**：11 项（B-01 ~ B-11），其中 🚧 半做 1 项（B-03 审批下发）、⬜ 未做 10 项。
- **过时期待办**：2 项（已在 Runner 实现中消化，待回填 Hub 文档）。
- **优先级提示**（按 M1 验收阻塞程度）：
  - 阻塞 M1 端到端验收：B-07（端到端验证）、B-03（审批下发，若用审批任务）。
  - 影响可观测/质量基线：B-08（单测）、B-09（监控告警）。
  - 功能完整性：B-01/B-02/B-04/B-05/B-06/B-11。
  - 协作流程：B-10（QA 待补）。
