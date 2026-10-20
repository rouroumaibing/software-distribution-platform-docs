# ALERTING-RULES-DESIGN：平台离线告警规则设计

- **状态**：Design（设计定稿，本轮落实）
- **住户依据**：横跨 hub（指标源 + 通知流）+ runner（指标源）+ env 仓（规则文件部署）三端，按「范围优先」判据入住 `shared/`
- **覆盖缺口**：STATUS §2 **#5**（集群离线告警规则 + 降级开关预发/灰度验证）

## 1. 设计目的

当前系统（三仓 main）双端指标埋点已就绪——hub `internal/metrics`（自研 0.0.4 文本导出器：`sdp_hub_http_requests_total` / `sdp_hub_http_request_duration_seconds_total` / `sdp_hub_in_flight_requests` / `sdp_hub_uptime_seconds` / `sdp_hub_build_info`）、runner `pkg/metrics`（`sdp_runner_taskrun_phase_transitions_total` / `sdp_runner_rollout_current_canary_weight` / `sdp_runner_connector_reconnects_total` / `sdp_runner_alert_failures_total`）——但**没有任何告警规则**消费它们：runner 与 hub 的 WS 断连、hub 5xx 激增、流水线连环失败都只能靠人盯 Grafana。本设计目的是补齐「指标 → 告警规则 → 通知流」的最后一环，使离线/异常**主动可发现**。

## 2. 设计逻辑

### 2.1 指标缺口（先补数，再配规则）

「target 离线」告警需要 **hub 侧 gateway 在线 target 数 gauge**，当前 hub 指标集没有。补一个最小指标（随本设计一并实现）：

```
sdp_hub_gateway_connected_targets{target=...} gauge   # 当前 WS 在线 runner 数
```

落点：`internal/gateway` 连接建立/断开处调用 `metrics.SetGatewayConnectedTargets(n)`（hub 导出器为无依赖文本实现，沿用 `RecordRequest` 同款注册模式）。runner 断连已可由该 gauge 掉 0 观测，无需 runner 侧新指标。

### 2.2 规则集（Prometheus rule 文件，置 env 仓）

| 规则 | 表达式（要点） | 级别 | 通知流挂点 |
|---|---|---|---|
| RunnerOffline | `sdp_hub_gateway_connected_targets == 0 for 2m`（按 target 维度） | critical | `internal/notification` 同一通知流（#7 通知中心已备好消费端） |
| RunnerFlapping | `increase(sdp_runner_connector_reconnects_total[15m]) > 3` | warning | 同上 |
| HubErrorSpike | `rate(sdp_hub_http_requests_total{status_class="5xx"}[5m]) / rate(sdp_hub_http_requests_total[5m]) > 0.05` | critical | Alertmanager → webhook → hub 通知注入 |
| PipelineFailBurst | `increase(sdp_runner_alert_failures_total{kind="pipelinerun"}[10m]) > 3` | warning | 同上 |
| TargetDown（无告警数据） | `up{job="sdp-runner"} == 0 for 3m` | critical | Prometheus 抓取失败的兜底（RunnerOffline 的双保险） |

**降级开关分级验证（钢人裁定）**：规则文件按 `groups:` 分 critical/warning 两组，env 仓部署时可用 `--only-groups` 语义分级启用；预发环境先启用 warning 组验证通知流，灰度再放开 critical 组——避免新规则误报直接打扰生产值班。

### 2.3 验证方式（不臆想、真验证）

1. **promtool 静态校验**：`promtool check rules <rules.yaml>` + `promtool test rules`（自带测试用例文件，喂入序列样本断言告警触发/恢复）；
2. **kind 实测（可选增强）**：env 仓部署 kube-prometheus-stack → port-forward → 手动摘掉 runner pod → 断言 RunnerOffline 在 2m 内 fire → 恢复后 resolve。

## 3. 核心数据结构 / 接口定义

- **hub 侧**：`metrics.SetGatewayConnectedTargets(n int)`（新增，文本导出器同款）；通知流注入函数复用 `internal/notification` 既有写入路径，签名不变。
- **env 仓**：`local-kind-dev/alerting/sdp-alerts.yaml`（rules）+ `sdp-alert-test.yaml`（promtool 用例）；kube-prometheus-stack 的 values 覆盖文件（可选部署形态）。
- **Alertmanager webhook → hub**：`POST /api/v1/alerts/webhook`（新增端点，挂鉴权组 + webhook token），body 为 Alertmanager v2 JSON，映射为通知流条目——**本轮实现最小闭环（Rule→通知流），Alertmanager webhook 端点列入部署前提**。

## 4. 一致性校验

| 维度 | 结论 |
|---|---|
| 概念一致性 | 「指标缺口 / 规则集 / 分级启用 / 通知流挂点」统一命名；规则名与指标名零冲突 |
| 状态完备性 | 告警生命周期 firing→resolved 均有落点（for 子句 + 测试用例覆盖恢复路径）；Prometheus 自身不可达由 TargetDown 兜底 |
| 接口完备性 | gauge 写点（gateway 连接/断开）、webhook 端点、通知流注入均有落点 |
| 层次一致性 | 规则评估在 Prometheus（env 仓），hub 只做指标暴露与通知注入，不内嵌告警引擎 |
| 安全性 | webhook 端点带 token 鉴权；规则文件不含凭据 |
| 可靠性 | 分级启用防误报风暴；resolve 通知确保状态收敛可见 |
| 可测试性 | promtool test rules 用例随文件入库，CI 可跑 |
| 可调试性 | 告警名即文档；每条规则带 runbook 注释（annotation） |

## 5. 变更历史

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-10-08 | v1 初稿 | STATUS #5 由「运维环境项」转「落实」：补 gateway gauge 指标缺口 + 规则文件 + promtool 验证路径 |
