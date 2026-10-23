# 钢人分析：ADR-0002 落码后三项遗留项（2026-10-22）

> 本文是 ADR-0002（runner 安装引导 / join-bundle API）落码后，对 §6 遗留项的双向钢人论证全记录。
> 分析方法遵循用户既定协议：①最完整重述问题 → ②双向钢人 → ③分歧与关键变量 → ④只问一个最关键问题 → ⑤用户裁定后给出判断与下一步。
> 上游文档：`shared/ADR-0002-runner-install-bootstrap.md`、`shared/ADR-0001-runner-first-connect-enrollment.md`、`plans/GAP-BACKEND-TLS-2026-10-22.md`（§6 业界方案对比）、`shared/install-upgrade-design.md` §9.9。

## 1. 遗留项清单与出处

ADR-0002 落码（join-bundle API + console 安装命令弹窗 + cloud-init 模板）时显式声明不做的三件事（**#1 已实现**，行为规格见 [runner/features/per-target-auth.md](../runner/features/per-target-auth.md)；#2 / #3 维持记档，触发条件见 §8）：

| # | 遗留项 | 一句话描述 |
|---|--------|-----------|
| 1 | **enrollToken 消费端（per-target WS 鉴权链）** | join-bundle 签发的一次性 enroll token 目前没有消费者；runner 回连 WS 仍走共享静态 token |
| 2 | **云上网关公网证书（Web PKI 信任锚）** | 外部 runner 的 TLS 信任引导在云上可用公网证书整体消除，未做 |
| 3 | **runner 二进制平台托管分发** | join 模板的 `__RUNNER_BINARY_URL__` 由装机管线外部决定，平台不托管二进制 |

## 2. 事实打底（查实代码证据，非记忆臆断）

分析前核实了两组决定性事实：

1. **runner 侧（`cmd/runner/main.go:65`、`pkg/connector/client.go:89`）**
   - `mustEnv("TARGET_AUTH_TOKEN")` —— 共享静态 token **硬必填**，缺失即启动失败；
   - runner 全仓**没有任何代码**消费 `SDP_ENROLL_TOKEN`（join-bundle 渲染的 env 文件里有这个变量，runner 二进制不认识它）；
   - ADR-0001 的 auto-enroll（首连携带 `TARGET_VENDOR`/`TARGET_REGION` 注册属性）同样**依赖有效的共享 gateway token**，与 §9.9 一次性 enroll-token 无关。

2. **hub 侧（`internal/gateway/gateway.go:120-127`）**
   - WS 升级握手鉴权 = `Authorization: Bearer <GATEWAY_TOKEN>`（共享静态）+ `X-Target-Name`（**自报身份**）；
   - 一次性 enroll-token 只有铸发端（`GenerateEnrollToken` + `POST /targets/:id/enroll-token`，join-bundle 复用），**WS 握手不接受它**——铸发端有、消费端两侧（hub 接收 / runner 发送）皆无。

**核心结论（事实层面）**：遗留项 #1 不是"演进项"，而是**已交付 join 链路的功能断点**——信任语义（TLS + CA 指纹 + URL）已闭环，身份语义（谁在连）断裂。当前装机物料只有两个坏选项：塞共享 `TARGET_AUTH_TOKEN`（per-target 信任名存实亡），或 runner 起不来。

## 3. 问题重述（钢人协议第 1 步）

表面问题是"三个遗留项怎么排优先级"。真正的决策问题是：**ADR-0002 交付的 join 链路，是"设计上允许暂时不完整"，还是"已经欠了一笔必须马上还的功能债"？**

三个遗留项性质完全不同：#1 是已交付链路里"信任语义闭环、身份语义断裂"的缺口；#2 是部署层简化项（做了则信任引导整体消失）；#3 是升级闭环的依赖项（不做则升级编排空转）。钢人要回答的是：它们的真实优先级、依赖顺序，以及"现在做"和"记档等真实需求"的分界线。

## 4. 双向钢人（协议第 2 步）

### 4.1 遗留项 #1：enrollToken 消费端（per-target WS 鉴权链）

| 钢人 · 支持立即做（升 P0） | 钢人 · 反对（记档等待） |
|---|---|
| **join 链路当前实际不可用**：装机物料要么塞共享 `TARGET_AUTH_TOKEN`（per-target 信任名存实亡，ADR-0001 ⚠️ 被新链路放大——现在连"全平台共享的钥匙"都印在装机物料里了），要么 runner 起不来 | 当前部署现实：runner 都是运维手工装的，共享 token 从未泄漏；修的是"还没发生的问题"（YAGNI） |
| **契约热着**：join-bundle / §9.9 铸发端刚交付，此时接消费端心智最连续；hub 只差 WS 握手接受一次性 token，runner 只差发送侧，两端改动都小 | per-target token 牵动**整个 WS 鉴权协议**：token per-target 了但 `X-Target-Name` 还是自报的，等于半吊子——真正的修法要把"凭据绑定身份"一起设计（token 编码 target 或服务端从 token 反查），改动面比"接一个 token"大，值得一次设计好而非打补丁 |
| 一次性 token 使物料泄漏的爆炸半径从"全平台沦陷"降为"单目标一次性" | 真集群 E2E（GAP B–E 项）还没回归，先稳后动，避免两个未验证层叠在一起排障 |

**分歧**：是"修已交付链路的功能断点"（支持方定性）还是"为尚未发生的泄漏修防御"（反对方定性）。
**关键变量**：join 链路是否近期**真实投用**（有真实目标机走这条链路装机）——是，则支持方定性成立，P0。

### 4.2 遗留项 #2：云上网关公网证书（Web PKI）

| 钢人 · 支持（现在做） | 钢人 · 反对 |
|---|---|
| 唯一让"外部 runner 信任引导"**整体消失**的方案：OS 信任根直连，TLS 部分零分发（参见 GAP §6 派别 C，SaaS 平台同款） | `www.sdpworkflow.com` 是否真实注册解析、证书管理（续期/多环境）是**平台外事务**，不是代码能闭环的 |
| 云上 ELB 挂证书是标准运维动作，改动在部署不在代码 | dev/kind 永远自签——Web PKI 不消除双形态维护，只是云上少一步 |
| 与 #1 正交：token 逻辑在 TLS 内层，谁先做都不阻塞谁 | 若近期没有云上外部 runner 部署计划，这是"优化尚未存在的路径" |

**分歧**：归属层（部署运维 vs 代码）与时机（跟随云上部署节奏 vs 提前铺）。
**关键变量**：域名控制权确认 + 云上外部 runner 部署时间表。

### 4.3 遗留项 #3：runner 二进制平台托管分发

| 钢人 · 支持（平台托管） | 钢人 · 反对 |
|---|---|
| install/upgrade 编排（§9.9 ops）已存在，但平台不能发二进制，**升级编排是空转**——发了 op 运维还得自己找包，闭环断在分发 | runner 是控制面组件：让它从 hub 下载自己的新版本 = **升级通道自举问题**（通道被攻破 = 控制面沦陷）；业界惯例（包管理器 / systemd 路线）倾向宿主机包管理，不走自升级 |
| join 模板 `__RUNNER_BINARY_URL__` 由管线决定 = 安装物料仍有**平台外自由变量**，与"消灭物料漂移"的初衷矛盾 | 二进制托管引入版本生命周期（保留几版 / 回滚 / 完整性校验 / 签名），复杂度不小 |
| hub 已有 artifact 存储 + 签名 URL（`ARTIFACT_STORE_SIGN_SECRET`），**复用即可**，不是新架构 | runner 发布节奏慢、升级低频，人工 scp 尚可忍 |

**分歧**：升级分发的归属（平台自动化 vs 宿主机包管理/人工）与自举风险的对策。
**关键变量**：runner 升级是否要走平台自动化——若走，#3 是 #1 之后升级链路的硬依赖；若不走，纯 YAGNI。

## 5. 分歧主线、关键问题与用户裁定（协议第 3、4 步）

**三项的共同主线分歧**：它们是"未完成的产品闭环"还是"故意留下的设计边界"？优先级由什么驱动——安全驱动（#1）、部署驱动（#2）、功能驱动（#3）。

**只问了一个最关键的问题**（决定 #1 定性的胜负手）：

> 昨天交付的 join 链路（console 安装命令弹窗 + cloud-init 模板）近期是否要真实投用——即有没有真实目标机要走这条链路装机？这决定遗留项 #1 是 P0 功能缺口还是 backlog：runner 现在仍 mustEnv 共享 TARGET_AUTH_TOKEN，不走消费端改造，装机物料就必须塞共享 token 或 runner 起不来。

**用户裁定：近期真实投用。**

## 6. 判断与理由（协议第 5 步）

**#1 升 P0 立即做；#2、#3 维持记档、各挂明确触发条件。**

理由收敛为一句：查实代码后 #1 的性质变了——不是"将来再补的演进项"，而是已交付链路的功能断点；用户已裁定 join 链路近期真实投用，装机物料塞共享 token 或 runner 起不来，二选一不可接受。#2/#3 没有这种"已交付即断"的紧迫性来源，且与 #1 正交。

## 7. #1 实现方案（kubeadm TLS bootstrap 同构，待落码）

| 侧 | 改动 |
|---|---|
| **hub 握手三态鉴权**（`internal/gateway/gateway.go`） | ① `Bearer == GATEWAY_TOKEN` → 共享路径保留（dev/内网过渡）；② 命中未消费、未过期的一次性 enroll token → 标记 used、生成 per-target 凭据（`crypto/rand`）落库（targets 新增 `runner_credential` 列，AutoMigrate 只加不删）、**101 响应头 `X-SDP-Runner-Credential` 返回**、按 enroll token 绑定的 target id 解析身份；③ 命中某 target 的 `runner_credential` → **服务端反查 target**（身份源 = token），`X-Target-Name` 降级为一致性断言（自报身份问题一并了结，ADR-0001 ⚠️ 收口） |
| **runner 三态发送**（`cmd/runner/main.go` + `pkg/connector/client.go`） | 凭据文件存在（`SDP_RUNNER_CREDENTIAL_FILE`，缺省 `/etc/sdp-runner/credential`）→ 用 per-target 凭据拨号；否则有 `SDP_ENROLL_TOKEN` → 用它首拨、从 101 响应头收凭据落盘 0600（gorilla `Dialer.Dial` 返回 resp，读响应头零障碍）；都没有 → 回落 legacy 共享 token（dev 不破坏） |
| **物料（console / cloud-init）** | 零改动——join 命令 env 已含 `SDP_ENROLL_TOKEN`；共享 `TARGET_AUTH_TOKEN` 从装机物料中消失 |

**Gate**：hub / runner 各自 `go build` / `go vet` / `go test` 全绿（鉴权三态单测：共享 token、enroll token 首拨换凭据、per-target 凭据反查、过期/已用 token 拒绝）。

## 8. #2 / #3 记档条件

- **#2 Web PKI**：与 #1 正交，不阻塞。触发条件 = `www.sdpworkflow.com` 域名控制权确认 + 云上外部 runner 部署时间表。落地形态：云上 ELB / Gateway listener 挂公网证书（或 cert-manager HTTP-01），外部 runner 凭 OS 信任根直连，TLS 信任引导整体消失。
- **#3 二进制托管**：升级自动化立项时做。复用 hub artifact 签名 URL；**必须带完整性校验/签名**（升级通道自举沦陷风险是钢人反方留下的硬边界，不可省略）。若最终走宿主机包管理路线（rpm/deb 仓），本文 #3 支持方论点第 1 条（升级编排空转）需重新评估。

## 9. 变更历史

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-10-22 | 初稿：ADR-0002 落码后三项遗留项的完整双向钢人记录（事实打底代码证据 → 逐项双面论证 → 分歧与关键变量 → 单问题裁定 → 判断与 #1 三态鉴权设计方案） | 用户要求把钢人分析完整记录到项目（初版仅 GAP 变更历史一行简记，用户反馈过于简略） |
| 2026-10-22 | **§7 方案落码**：hub 侧 `models/target.go` 增 `RunnerCredential` 列（AutoMigrate 只加不删）、`repository/target.go` 增 `BurnEnrollToken`（事务内条件 UPDATE 原子消费：token 匹配 + 未过期 + 名字断言合一，RowsAffected==0 ⇒ 单次生效由数据库而非 check-then-write 保证）与 `GetByCredential`、`service/credential.go`（ConsumeEnrollToken/GetByCredential，哨兵 `ErrEnrollTokenInvalid` 统一映射）、`gateway/gateway.go` ServeWS 三态鉴权（鉴权段 + `serveTarget` 公共段，enroll 态经 101 响应头 `X-SDP-Runner-Credential` 返还凭据）；runner 侧 `connector/client.go`（`WithEnrollBootstrap` + `currentToken` 三级解析 + `persistCredential` 0600 落盘）与 `cmd/runner/main.go`（放掉 `mustEnv("TARGET_AUTH_TOKEN")`，三态 env 接线，全无凭据 fail-fast）。gate：hub/runner 各 build/vet/test/gofmt 全绿（新增 credential_test 两侧）。ADR-0001 ⚠️（共享 token + 自报身份）在 per-target 态收口 | 用户确认按 §7 方案执行 |
