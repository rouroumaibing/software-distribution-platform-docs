> **性质**：计划（**未实现，草稿**）。状态以 [plans/STATUS.md O-36](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **来源**：原 `plans/GAP-FEASIBILITY-STEELMAN-2026-10-20.md`（A4）与 `plans/PLAN-DRAFT-ACTIONABLE-2026-10-20.md`（A4）已删档，其论据已并入本计划文档；状态以 STATUS 为准。
> **铁律**：本文件只追加；状态判断一律以 STATUS 为准，本文件维护计划规格。
> **文档命运裁定（2026-10-23 分析）**：O-36 **FILL/KEEP** —— 设计已实质；首步须补「反向追踪 Dispatch 调用方 + 失败吞错契约单测」（生产调用方未通过字面量检索定位，标记未验证-动态）。

---

## O-36 通知渠道 Webhook 适配器（A4，升格·范围锁 Webhook）

**目标**：在现有邮件通知外，新增 Webhook POST 适配器，使 O-5 告警规则能出企业 IM / Webhook，闭合运维告警回路；IM 留后续。

**现状 / 证据**：`internal/notification/service.go:97-110` `Dispatch` 对未配置渠道 best-effort swallow（仅邮件）；`subscription.go:13` 注释「企业 IM/Webhook 渠道留作后续适配器插件」；O-5 告警已落地但出不去 Webhook，运维闭环不完整（#7 铃铛仅站内消费）。

**代码改动点**：
1. 定义 `Channel` 接口 `Send(evt, subject, title, body string) error`；先实现 **Webhook POST 适配器**（基础重试 + 超时 + 失败格式）。
2. `Subscription`（`subscription.go:14`）扩展 `WebhookURL` 字段 + `Wants` 逻辑纳入 webhook 事件；`Dispatch` 从 best-effort swallow 改为按渠道分发。
3. `Dispatch` 失败不可令调用方（run 状态写 / 审批 seeding）失败。

**验收 gate**：单测覆盖 Webhook 适配器 POST + 重试；`Dispatch` 按订阅分发、邮件路径不回归；频道失败不影响主流程。

**钢人结论**：中可落地。技术可行，属产品节奏决策；R3 已当周期决策邮件-only，加 Webhook 需考虑重试/超时/凭据存储，范围先锁 Webhook、IM 留后续。
