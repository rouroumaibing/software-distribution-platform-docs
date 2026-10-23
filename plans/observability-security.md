> **性质**：计划（**未实现，草稿**）。状态以 [plans/STATUS.md O-34/O-35](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **来源**：原 `plans/GAP-FEASIBILITY-STEELMAN-2026-10-20.md`（A3、B2）与 `plans/PLAN-DRAFT-ACTIONABLE-2026-10-20.md`（A3、B2）已删档，其论据已并入本计划文档；状态以 STATUS 为准。
> **铁律**：本文件只追加；状态判断一律以 STATUS 为准，本文件维护计划规格。
> **文档命运裁定（2026-10-23 分析）**：O-34/O-35 **FILL/KEEP** —— 设计已实质；建议补强首步验收项（多副本限流演进路径、runner 日志调用点盘点清单）。

---

## O-34 API 限流 / CORS / 安全响应头（A3）

**目标**：在 hub 中间件链补防御纵深标准件——安全响应头（零成本）+ 认证接口限流（防暴破）；CORS 默认同源放行、仅确有跨域时加白名单。

**现状 / 证据**：`hub/internal/middleware/` 仅 `auth/rbac/audit/ownership/user_context`；中间件链在 `cmd/hub/main.go:546-559`，**无限流 / CORS / 安全头**。

**代码改动点**：
1. 新建 `internal/middleware/security_headers.go`：`X-Content-Type-Options: nosniff` / `X-Frame-Options: DENY` / `Strict-Transport-Security` / 基础 `Content-Security-Policy`；挂 `main.go:546` 之后。
2. 新建 `internal/middleware/ratelimit.go`：单副本 in-memory 滑动窗口（IP + route 维度）；多副本时降级 best-effort（与 O-32 联动——不开 LE 则计数不跨副本，明确注释）。登录/token 接口更严格配额。
3. CORS：当前 console↔hub 同源，默认同源放行不加严格 CORS；仅确有跨域需求时加白名单配置项。

**验收 gate**：`go build/vet/test` 全绿；集成测试断言安全头存在；登录接口连续超额触发 `429`。

**钢人结论**：中-高可落地。安全头 + 单副本限流易；CORS 配错会阻断前端需谨慎；限流在多副本下需共享计数（先单副本起步，多副本再引 redis）。

## O-35 结构化日志与集中采集（B2）

**目标**：统一各组件 JSON 日志 schema，多副本/多组件下可聚合排障与审计取证；采集后端不强制。

**现状 / 证据**：hub 用 `applog` 封装；runner 侧日志风格未统一盘点；无统一 JSON schema。

**代码改动点**：
1. 约定统一字段：`level` / `time` / `msg` / `component` / `scope` / `trace_id`（预留，接追踪时填）。
2. hub `applog` 补齐字段；runner 侧盘点日志输出点后对齐同 schema。
3. 采集端点约定 `stdout + 可选 Loki/ES`，不强制后端（与 B1/B4 后端立项解耦）。

**验收 gate**：两仓日志可被 JSON 解析、字段一致；不强制接后端即可验收。

**钢人结论**：高可落地（增量、可逆、无协议变更）；runner 侧需先盘点调用点防格式回归。
