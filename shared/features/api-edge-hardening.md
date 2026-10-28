> **来源**：[plans/observability-security.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/observability-security.md)（O-34/O-35 设计草案）与 [plans/data-lifecycle.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/data-lifecycle.md)（O-37 设计草案）；保留 GC 骨架范本 `hub/internal/artifact/service/gc.go`（`ArtifactGC`）。
> **拆分说明**：plans 文档是**设计起草记录**，本文件是**行为规格**（API 边界防护三件套 + 数据保留 GC 如何工作）。O-35（结构化日志）尚未实施，见 §5 登记项。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 1. 问题与目标

API 边界此前无安全响应头、无限流、无 CORS 白名单；审计日志 / 运行日志 / 历史制品版本无保留期，PG 与对象存储无限增长。目标：防御纵深标准件 + 分级保留 GC（均默认关闭或零成本，部署显式开启）。

## 2. 安全响应头（O-34a）

- `middleware.SecurityHeaders()` 挂 root engine（全路由，含 /api 与 /gateway）：`X-Content-Type-Options: nosniff`、`X-Frame-Options: DENY`、`Content-Security-Policy`（default-src 'none' 族）、`X-XSS-Protection`、`Referrer-Policy`。
- 零配置、恒开启；不影响 API JSON 响应与 WS 升级。

## 3. API 限流与 CORS（O-34b/c）

- **限流**：`middleware.RateLimit`（in-memory token bucket），`HUB_RATE_LIMIT_RPS` > 0 启用，burst = rps（过载请求 429）。按客户端 IP（`X-Forwarded-For` 末跳优先）。**单副本实现**：计数不跨副本，多副本部署需共享存储（与 O-32 LeaderElection 同款"先单副本防呆"边界）。闲置 bucket 由 sweeper 回收。
- **CORS**：`HUB_CORS_ORIGINS`（逗号分隔白名单）设置时生效——非白名单 origin 拒发 `Access-Control-Allow-Origin`，OPTIONS 预检内联处理；未配置 = 同源 no-op（当前 console 与 hub 同源，默认零影响）。

## 4. 数据保留 GC（O-37）

- **骨架**：`internal/retention.RetentionGC` 复用 `ArtifactGC` 范本（默认关闭、批量、失败记日志吞掉），ticker `HUB_RETENTION_GC_INTERVAL`（默认 0=关闭），批大小 `HUB_RETENTION_GC_BATCH`（默认 1000）。
- **三档保留**（全部默认 0=关闭）：

| 配置 | 清理对象 | 判定 |
| --- | --- | --- |
| `HUB_AUDIT_LOG_RETENTION_DAYS` | `audit_logs` | `created_at` 超龄即删（审计日志无终态概念） |
| `HUB_RUN_LOG_RETENTION_DAYS` | `pipeline_runs` + `task_runs`（级联） | **终态 + 超龄双保险**：仅 `Succeeded/Failed/Error/Cancelled/Canceled` 且超龄的 run；运行中永不删 |
| `HUB_ARTIFACT_VERSION_RETENTION` | `artifacts` | 每组件保留最新 N 版（ROW_NUMBER 窗口），更旧版本删除（对象存储删除为 best-effort，失败记日志不重试阻塞） |

- **与 O-26 备份协同**：GC 删的是"过保留期的历史数据"，备份策略独立评估；两者都默认关闭，运维显式开启。

## 5. 登记项（未实施）

- **O-35 结构化日志**：统一 JSON schema（level/time/msg/component/scope/trace_id）→ hub `applog` 补字段 → runner 对齐；采集端点约定 stdout，后端（Loki/ES）留待 B1 立项。

## 6. 变更历史

| 日期 | 变更 |
| --- | --- |
| 2026-10-26 | 首次成文：O-34 安全头/限流/CORS + O-37 三档保留 GC 行为规格，随代码落地（hub 31 包 gate 绿）；O-35 维持登记。 |
