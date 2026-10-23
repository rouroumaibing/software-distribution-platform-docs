> **性质**：计划（**未实现，草稿**）。状态以 [plans/STATUS.md O-38/O-39](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **来源**：原 `plans/GAP-FEASIBILITY-STEELMAN-2026-10-20.md`（F2.2、F4.3）与 `plans/PLAN-DRAFT-ACTIONABLE-2026-10-20.md`（F2.2、F4.3）已删档，其论据已并入本计划文档；状态以 STATUS 为准。
> **铁律**：本文件只追加；状态判断一律以 STATUS 为准，本文件维护计划规格。
> **文档命运裁定（2026-10-23 分析）**：O-38/O-39 **NOT-NEEDED-NOW** —— 保留为占位；数据源（O-38）/ 终止语义（O-39）未拍板前不补实质内容。

---

## O-38 组件可部署版本端点（F2.2，canary 回滚闭环）

**目标**：实现 `GET /components/:id/versions` 端点，为灰度「回滚到指定版本」提供目标来源，闭合 canary 回滚最后一环；配套 console picker。

**现状 / 证据**：`API-REFERENCE.md:105` 的端点登记待建；`cmd/hub/main.go` 路由清单无该端点；canary 回滚缺目标版本来源（关联 O-17 版本/发布联动）。

**代码改动点**：确认版本数据源（制品库 vs 部署版本快照）；实现端点 + console picker。

**验收 gate**：端点返回组件可部署版本列表；console picker 可选版本触发回滚。

**钢人结论**：中可落地（产品）。数据源需先拍板；与 O-17 版本/发布联动同批。

## O-39 运行级超时 / 截止（F4.3，运行治理）

**目标**：为整个 PipelineRun 增加运行级超时/截止字段 + reconciler 终止逻辑，避免长尾/卡死 run 无自动终止、占用 target 与配额。

**现状 / 证据**：任务级 `timeoutSeconds` 存在（`API-REFERENCE.md:152`），但 PipelineRun 级运行超时/SLA 截止无字段；长尾 run 无自动终止。

**代码改动点**：定义运行级超时字段 + 终止语义（cancel / failed，参照任务级 `timeoutSeconds` 实现）；UI 呈现。

**验收 gate**：超时的 run 被自动终止；语义（cancel vs failed）明确且 UI 呈现。

**钢人结论**：中可落地，难点在终止语义拍板（cancel 还是 failed）+ UI 呈现；与 O-38 同属运行治理议题。
