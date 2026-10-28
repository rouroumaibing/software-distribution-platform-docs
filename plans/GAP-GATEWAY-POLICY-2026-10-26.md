# 网关流量策略余量 Gap 跟踪（WS 长连超时 + ELB 健康检查探针）

> **来源**：`shared/NETWORKING-GATEWAY.md` §6/§7.2 落地时登记的两项遗留观察项，按指针协议升格为活跃 Gap 跟踪（STATUS §2 O-42）。
> **权威关系**：网关架构与运维手册权威在 `shared/NETWORKING-GATEWAY.md`；本文档只跟踪「缺口清单 + 方案候选 + 验证 gate」，行为规格以权威文档为准。

## 1. 缺口清单

| # | 缺口 | 现状 | 影响 |
| --- | --- | --- | --- |
| G1 | hub HTTPRoute `/gateway`（runner 回流 WS 长连）无显式超时 Policy → **已落**：hub chart `httproute.yaml` 以 BackendTrafficPolicy `timeout.http.streamIdleTimeout`（默认 `3600s`，values `gatewayRoute.streamIdleTimeout` 可覆盖）按 rule name `gateway` 精确挂 `/gateway` 规则（sectionName 规则级，`/api` 不受影响）；EG v1.6 字段面已核对（官方 concepts + API spec 双源确认） | kind 长 idle WS 实测待环境（见 §4）；EG 默认（未升级 chart 前）= listener 继承 5m |
| G2 | 云上 CCE EG 插件自动建 ELB 的健康检查探针参数未盘点归因 | 2026-10-19 云上端到端 4×200 属**结果性通过**，探针协议/路径/端口/Host 是「配置正确」还是「未启用主动探活」未归因（`plans/FIDELITY-KIND-VS-CLOUD-2026-10-09.md` §6 #4） | 探针若以业务路径 + 无匹配 HTTPRoute 的 Host 探活，Envoy 返回 404，健康后端被误判不健康 → 整入口摘流放大为平台不可用 |

## 2. 方案候选（G1）

| 方案 | 内容 | 权衡 |
| --- | --- | --- |
| A. BackendTrafficPolicy | route 级 Policy 挂 HTTPRoute `hub` 的 `/gateway` 规则（或独立 Policy targetRef 该 route），显式声明超时/重试 | Gateway API 正解、随 chart 分发三仓自持；**前置**：须核对 EG v1.6 的 BackendTrafficPolicy 是否暴露所需的 idle/stream timeout 字段（Policy 体系字段面以 v1.6 文档为准，不臆测） |
| B. EnvoyProxy CRD 调优 | env 仓 `gateway-sdp.yaml` 的 EnvoyProxy 段加 envoy 配置扩展 | 与 Gateway 级资源同处运行方持有、全局生效；缺点 = 粒度粗（全数据面），且跨本地/云上两套 EnvoyProxy 配置需同步 |
| C. 应用层心跳兜底 | runner WS 加 keepalive ping（短于网关 idle 阈值） | 不动网关、对 EG 版本升级免疫；缺点 = 掩盖而非消除缺口，且 runner 已有重连对账，边际收益需实测评估 |

**倾向**：A 优先（策略与路由解耦、随三仓 chart 自持），A 字段面不足时退 B；C 作为实施时的对账兜底可并行评估，不单独立项。

## 3. 方案候选（G2）

| 方案 | 内容 | 权衡 |
| --- | --- | --- |
| A. 盘点现状并固化 | 云上重建时读 ELB 探针配置（控制台/Gateway status），确认探活协议与路径；结论写回 `NETWORKING-GATEWAY.md` §7.2 | 零改动、先归因后动手；云上环境当前为归零态，须随下次重建执行 |
| B. 显式就绪端点探活 | 探针指向 Envoy 数据面就绪端点（EG 数据面 Pod 自带 readiness），不依赖任何业务路由 | 消除「业务路径 404 误判」类风险；改动面在云侧探针参数，属运维项 |

**倾向**：A 先行（归因），若确认探针依赖业务路径则转 B。

## 4. 验证 gate

- **G1**：~~静态 gate~~ `helm lint`/`helm template` 已绿（Policy 渲染正确、sectionName 挂 rule `gateway`）；**kind 实测待环境**——本地 kind 起 `/gateway` WS 长连接，idle 超过 listener 5m（< 3600s 阈值）后连接仍存活；网关→hub 全链（BackendTLSPolicy 不受影响）`response_flags` 为 `-`；runner 断连重连对账回归绿。
- **G2**：云上重建后 Gateway `Programmed` + ELB 后端健康态 100%；（若实施 B）手工停掉 hub 后端验证探针只摘对应后端、不放大到整入口。
- 静态 gate：`helm template` 三仓全绿；新增 Policy 落 hub chart 时 hub `go build/vet/test` 全绿（chart 改动不触 Go 代码则只跑 template）。

## 5. 变更历史

| 日期 | 变更 |
| --- | --- |
| 2026-10-26 | 首次成文：自 `shared/NETWORKING-GATEWAY.md` 落地时登记的两项遗留观察项升格；STATUS §2 登记 O-42。 |
| 2026-10-26 | G1 按方案 A 落地：hub chart 加 BackendTrafficPolicy（`streamIdleTimeout` 默认 1h，sectionName 挂 `/gateway` rule）；EG v1.6 字段面核对完成；helm lint/template 绿；kind 长 idle 实测与 runner 回归随下次本地部署执行。G2 维持云上重建随行（归因先行）。 |
