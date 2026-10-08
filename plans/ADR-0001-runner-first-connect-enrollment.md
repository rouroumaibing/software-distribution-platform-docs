# ADR-0001：Runner 首连自注册（bootstrap-on-first-connect）

- 状态：已采纳（2026-10-07）
- 关联：`DATA-MODEL.md` §9.9（enroll-token 引导，**消费端留守 queued**，§16.5 裁定）、`API-REFERENCE.md`「网关鉴权偏弱」⚠️ 标注、`deploy-local.sh` §9 target 注册
- 落码：hub `internal/gateway/gateway.go` ServeWS + `internal/target/service/target.go` Enroll；runner `pkg/connector/client.go` WithEnrollInfo + `cmd/runner/main.go` TARGET_VENDOR/TARGET_REGION

## 1. 背景与问题

`GATEWAY_TOKEN` 是全局共享 bearer（hub chart 默认 `sdp-dev-token-2026`，与 runner chart 成对）。runner 拨号 `/gateway/ws` 时 hub 校验 token → 按 `X-Target-Name` 查库，**target 不存在即 404**，runner 以 ≤30s 退避无限重试。而 target 注册（`POST /api/v1/targets`）走用户 RBAC，auth ON 时部署脚本无法代做（401 跳过）——部署闭环缺最后一公里：装完 runner 必须人工登录 console 补建 target。

§9.9 已有的 enroll-token 只是**半成品**：铸发端落地（`GenerateEnrollToken` + `POST /targets/:id/enroll-token`），消费端经 §16.5 钢人裁定留守 queued，**没有任何代码路径消费该 token**。dev 环境靠双端写死的共享静态 token 把缺口盖住（token 层能过、只在查库层失败），于是呈现为 404 空转。

## 2. 备选方案与双向钢人

### 方案 A：首连自注册（已采纳）

`ServeWS` 在 token 合法 + target 不存在时，若请求携带 `X-Target-Vendor`/`X-Target-Region` 则自动建行（get-or-create，审计日志），否则维持 404。

| 钢人（支持） | 反钢人（反对） |
| --- | --- |
| 协议已有机器凭据通道（共享 gateway token），自动注册是补全既有意图（deploy-local.sh §9 本就尝试过 POST /targets） | target 是运维宣告的"接入意图"，自注册把宣告权下放给持共享 token 的主体，生产里两者可能不是同一人 |
| GitLab Runner registration token 同款范式；runner chart 注释本就写明"需先注册同名目标，token 与其一致"，配置耦合早已存在 | 语义副作用在连接路径里：target 拼写错误的 runner 会静默建垃圾行 |
| 404 空转不是防御：token 那关已挡住未授权者，手工注册没有额外安全增益，只产生无效重试噪音 | 生命周期尾巴：runner 卸载后 target 残留，需人工 GC |
| 改动最小：hub 一个分支 + service 一个 get-or-create 方法，零新端点 | dev 下 GATEWAY_TOKEN 非空（chart 默认值），门真实存在；但**置空即开放注册**，依赖运维纪律 |

**缓解**：vendor/region 头**同时非空**才触发建行——未配置对接信息的 runner（拼写错误、忘配）仍走严格 404，垃圾行需要"显式配置了 vendor/region"才会产生，即部署者主观意图；建行打审计日志。

### 方案 B：独立 enroll 端点（未采纳）

新增 `POST /gateway/enroll`（鉴权 = gateway token），runner 启动先 HTTP 注册再连 WS。

| 钢人（支持） | 反钢人（反对） |
| --- | --- |
| 语义显式：注册是注册、连接是连接，审计/测试/幂等都更好做 | 新端点 + 新路由 + runner 侧 HTTP client 逻辑，两个仓的 diff 都更大 |
| 可返回丰富结果（created vs existed、target id），便于部署工具判断 | runner 当前除 job 下载外无 hub HTTP 依赖，为注册引入新依赖面 |
| 为 §9.9 per-target token 的消费端预留了自然挂载点 | hub/runner 协议层是 e2e 证明的最脆层（canary 回流缺口所在），扩面违背最小改动原则 |
| | 注册成功与首连之间有时间窗，状态同步反而多一种中间态 |

**裁定**：方案 A。方案 B 的可测性优势不足以抵消双仓 diff 扩大；且 B 的挂载点优势对 §9.9 并不排他——A 落地后 per-target token 仍可在 WS 鉴权链上叠加演进。

### 与 §9.9 的关系

互补不冲突：§9.9 = 运维**先**建 target、再铸一次性 token 引导 runner（target 预先存在，生产级 per-target 凭据方向）；ADR-0001 = target **不存在**时由持共享 token 的 runner 安装自建（GitLab 式安装即注册）。演进路径：A 落地解决冷启动 → §9.9 消费端补齐后做 per-target token 轮换 → 共享 token 收敛为纯引导凭据。

## 3. 安全边界

- 门 = hub `GATEWAY_TOKEN`：持钥者即被授权注册（GitLab registration token 语义）。**生产必须设置**；置空（dev 全收模式）等于开放注册，已在 hub chart values 注释标明。
- 不绕 Keycloak、不触 ResourceTarget RBAC：注册走机器凭据通道，与既有 ServeWS 鉴权同层；target 行的后续管理（改/删/配环境）仍走用户 RBAC。
- 唯一性：`targets.name` 有 uniqueIndex，并发创建输家重读赢家，无重复行。

## 4. 验证记录（2026-10-07，kind 集群实跑）

- **go gates**：hub / runner 两仓 `go build` + `go vet` + `go test` 全绿，`gofmt -l` 零输出。
- **部署**：hub/runner 镜像经 build.sh 重建（enrollment 改动）→ node_push 入 harbor → helm upgrade（REVISION hub=3 / runner=2）。⚠️ 同 tag + `IfNotPresent` 命中节点旧镜像缓存，须 `ctr images remove` 节点缓存 ref 后 `rollout restart` 强制重拉（复刻 2026-09-26 已知坑）。
- **E2E 实证**：
  - hub 日志：`gateway: target local-dev auto-enrolled (vendor=kind region=local)` → `gateway: target local-dev connected`；
  - DB：`targets` 表 `local-dev | kind | local | online`（自注册落库，心跳在线）；
  - runner 侧 `websocket: bad handshake` 退避重试消失。
- **负路径**（代码内保证，未单独立 E2E）：vendor/region 缺一即维持 404-on-unknown，拼写错误不会建垃圾行。

## 5. 遗留

- runner 卸载后 target 不自动 GC（保留：target 是运维可见资源，删被环境引用的目标本就有 FK 限制）。
- API-REFERENCE「网关鉴权偏弱」⚠️ 仍成立：per-target 身份未实现，本次只解决"注册自动化"，目标身份仍是自报 `X-Target-Name` + 共享 token。
