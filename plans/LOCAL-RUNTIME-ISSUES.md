# 本地运行时问题排查与根因修复报告

> 触发：本地 kind 环境重建并启动服务后，做一次全方面问题收集。
> 方法：先跑真实环境观测行为，再回到代码从第一性原理找最本质原因，记录后逐一修复。
> 问题来源三路：① 本地运行时实测；② 三工具质量门报告遗留；③ 认知成本审计报告残余风险。

---

## 0. 执行摘要

本地实例启动后，**hub 陷入 CrashLoopBackOff**，业务服务无法就绪。第一性原理定位为一个被反复复制的模式：**启动期对外部依赖的瞬态失败用「永久失败」语义处理（Fatal / 无重试）**。这一根因同时解释了运行时故障与多处遗留风险——它们本质都是"把随时间变化的依赖/状态当成静态快照"。

本轮收集到 9 个问题，按根因归并为 4 类：

| 根因类 | 问题 | 严重度 | 处置 |
| --- | --- | --- | --- |
| R1 启动瞬态失败无重试/降级 | P0-1 hub OIDC discovery 503 直接 Fatal | 阻塞 | 修复 |
| R2 意图/观测混写、缺单一权威 | P1-1 rollout 状态机、P1-2 命令三写路径（历史已修，验证回归） | 中 | 复核/回归 |
| R3 类型/契约弱化 | P2-1 dispatch 测试盲区、P2-2 tree.ts 边界、P2-3 console API 零覆盖 | 中 | 补测试 |
| R4 约束未机械化 | P3-1 check-crds 未入 CI、P3-2 云上 gate 未实跑、P3-3 v1 快照不回填 | 低-中 | 固化/说明 |

---

## 1. 本地环境实测状态

kind 集群（`sdp-dev`，2026-11-23 12:33 重建）观测时间线：

| 时刻 | 观测 |
| --- | --- |
| 12:32 | 仅 `harbor` + `envoy-gateway-system` 基础设施就绪；`sdp-workflow` namespace 为空 |
| 12:36 | `postgres` Running；`hub-keycloak-0` 0/1 Running（startup probe 持续 503/connection refused）；`hub` 0/1 Error，日志 `hub: failed to init authenticator: 503 Service Unavailable ... Connection refused` |
| 12:37 | `hub` CrashLoopBackOff，RESTARTS=3；8443 网关 `/api/v1/targets` 返回 503 |
| 12:41 | keycloak 冷启动完成（约 4 分钟，startup probe failureThreshold=60）转 Ready；hub 随 kubelet 重启后 Running；console / runner 均 Running；8443 `/api/v1/targets` 返回 401（鉴权生效，链路通） |

**结论**：不是部署脚本没跑，而是 hub 在 keycloak 冷启动窗口（startup probe 尚未转 Ready）抢跑，把 OIDC discovery 的一次 503 当成不可恢复错误直接退出。keycloak 自身冷启动是正常现象，但 hub 无重试导致只能靠 kubelet 反复拉起硬等约 4 分钟——期间业务不可用，这正是 P0-1 要消除的窗口。

---

## 2. 问题清单与第一性原理根因

### P0-1 hub 启动时 OIDC discovery 瞬态 503 直接 Fatal（阻塞）

**现象**：`cmd/hub/main.go:505` `Fatalf("hub: failed to init authenticator: %v", err)`，`internal/middleware/auth.go:105 NewAuthenticator` 单次 `oidc.NewProvider` 拉取 discovery 文档，失败即返回。keycloak 冷启动返回 503 → hub 退出 → CrashLoop。

**第一性原理**：
- 分布式系统里，**依赖服务的就绪是随时间收敛的过程，不是布尔瞬时量**。任何"启动瞬间必须一次成功"的外部探测，都把时序问题误判成配置问题。
- 同一份 `main.go` 里，`EnsureDefaultOrgWithAdmin`（`:238`，同样调 keycloak）明确设计为 best-effort + Warn 继续，唯独 `NewAuthenticator` 用 Fatal——**处理策略不一致本身就是缺陷信号**：说明这里没有统一的"启动期外部依赖"策略，而是各处凭直觉写。
- OIDC discovery 的错误分两类：① 网络/503/连接拒绝（transient，应重试或稍后重建）；② realm 不存在/issuer 配置错误（permanent，应快速失败）。当前实现把两类都当 permanent。

**修复方向**：给 discovery 加**有界重试 + 固定间隔**（预算覆盖依赖就绪上限），区分 transient/permanent 错误；仅在重试耗尽后 Fatal。重试预算取 150 次 × 2s = 300s，与 keycloak startupProbe 上限（failureThreshold 60 × period 5s）对齐——重试预算必须 ≥ 依赖收敛上限，否则 hub 仍会在依赖就绪前放弃（这是把默认值从 40s 提到 300s 的第一性原理依据）。同时把"认证未就绪"降级为可观测状态而非进程崩溃是更彻底的方案，但会引入"未验证 token 的中间件语义"复杂度——本轮采用有界重试（最小且正确），并在报告记录更彻底方案的取舍。

**验收**：keycloak 冷启动期间启动 hub，能自动等到 discovery 成功并进入 Running；永久错误（伪造 issuer）仍在有界时间内失败，不无限挂起。

---

### P1 组：意图/观测分离（历史已修，回归复核）

- **P1-1 rollout 状态机**：`Spec.DesiredAction` 已作为意图单一权威，Status 只记录观测，annotation 仅兼容读路径。本轮复核 `applyDesiredAction`（`rollout_controller.go:590-731`）：pause 保 Spec、promote/rollback 消费后清空、rolledback 保护均在位。
- **P1-2 命令写路径**：Approve/Rerun/Cancel 已统一为意图 → reconciler 落盘。`approve_handler.go` / `rerun_handler.go` 确认只 Patch annotation、不写 Status。

**根因回顾**：注解 + Status 共同编码状态、命令三条写路径——控制意图与观测未分离。已在认知审计报告第 7 节修复，本轮确认无回归。

---

### P2 组：测试盲区（质量门报告遗留）

- **P2-1 dispatch 层真盲区**：`approve_handler.go:28` / `rerun_handler.go:32` 的 `||` 短路只测了两字段全空；`:54` 幂等 `==`、`:71`/`:81` 错误分支、`snapshot.go:92` 非法 hex 未测。根因：**契约边界（字段级、错误级）没有对应的测试切片**。
- **P2-2 `rollout_controller.go` 48.2%（67 killed / 72 survived / 59 uncovered）**：全项目 CC 最高（38）的函数恰是测试最薄的。存活集中在防御性/错误分支（SetControllerReference 失败、Create 非 AlreadyExists、scaleDeployment replicas nil、promote 的 aborted 保护、CompletionTime 幂等）。根因：**状态机复杂度增长快于测试覆盖**，且错误分支需 mock client 报错才能触发。
- **P2-3 console `tree.ts` 63.8%**：`computeWindow` 的 `?? -> ||`、`start>=end` 吸附分支边界测试不足。根因：窗口计算的关键保护分支缺边界用例（`rowHeight:0`、`total<=0`、滚过头吸附）。
- **P2-4 console API/views 零覆盖**：c8 只触达 16 文件（9 scripts + 7 src/utils）。根因：**测试布局结构性偏科**，非工具误报。

---

### P3 组：约束未机械化（认知审计残余）

- **P3-1 `make check-crds` 未入 CI**：CRD schema 存在 `config/crd/bases` 与 chart 两份副本，靠手动同步。根因：**一致性约束未绑定到自动执行的 gate**。
- **P3-2 云上 gate 未实跑**：`gate-cloud.sh` 已固化但云上环境已清理。根因：**验收证据与环境生命周期脱节**（环境清理后无法复现）。
- **P3-3 v1 裸 hex 快照不回填**：历史 CR 注解里的 v1 快照只读识别、不重算。根因：**数据格式演进缺迁移策略**。当前设计（跨算法比较显式报错、回溯走 hub `pipeline_versions.snapshot`）是可接受的取舍，不强行回填。

---

## 3. 修复记录

（下方在修复过程中逐条更新）

| 编号 | 修复落点 | gate | 状态 |
| --- | --- | --- | --- |
| P0-1 | `hub/internal/middleware/auth.go` 新增 `discoverProvider` 有界重试（IssuerMismatch 快速失败，瞬态错误默认重试 150 次 × 2s=300s，覆盖 keycloak startupProbe 上限）；`AuthConfig` 暴露尝试次数/间隔；新增 `auth_discovery_test.go` 4 用例（瞬态重试/永久失败/预算耗尽/ctx 取消） | `go build ./...` + `go vet ./...` + `go test ./internal/middleware/` 全绿 | 已修（代码层）|
| P1-1/P1-2 | 无新增改动，复核 `applyDesiredAction` / approve / rerun 的意图-观测分离无回归 | 随全仓 gate | 复核通过 |
| P2-1 | `runner/internal/dispatch/handler_edges_test.go` 新增 5 用例：单字段缺失（approve/rerun）、Delete 非 NotFound 上抛、NotFound 忽略、Patch 失败上抛、非法 hex 拒绝；`approve_handler_test.go` 补审批人身份断言（杀幂等 `==->!=`） | `go test ./internal/dispatch/` 全绿；变异复核见第 4 节 | 已修 |
| P2-2 | 未改（rollout 控制器 48.2%）——属"补测试"范畴、非行为缺陷，且需 mock client 错误分支；列为后续专项 | — | 保留（已知风险）|
| P2-3 | `console/scripts/service-tree-smoke.mjs` 补 3 用例：rowHeight=0/负、total<=0、overscan=0 滚过头吸附 | `node service-tree-smoke.mjs` 25/25 通过 | 已修 |
| P2-4 | 未改（console API/views 零覆盖）——结构性测试布局，非本次范围 | — | 保留（已知风险）|
| P3-1 | `runner/.github/workflows/ci.yml` 增加 `make check-crds` 步骤，头部命令说明同步 | `make check-crds` 通过；ci.yml YAML 语法校验通过 | 已修 |
| P3-2 | 不强行修：`gate-cloud.sh` 已完整固化（变量入口/RESULT 判定/证据留存），云上环境已清理无法实跑；恢复环境后按 `--only=smoke` 起 | bash -n 已验（历史） | 保留（环境限制）|
| P3-3 | 不强行修：v1 裸快照只读识别、跨算法比较显式报错，精确回溯走 hub `pipeline_versions.snapshot` 完整 JSON —— 是可接受取舍，回填反而引入状态重写风险 | 随全仓 gate | 保留（设计取舍）|

> **P0-1 运行时验证说明**：本地部署已升级到含修复的 `v0.0.2` 镜像。代码层由单测证明行为正确（503→重试→成功），运行层由新旧镜像对照实验确认：旧版在 issuer 不可达时 CrashLoop，新版 0 重启 + 有界 retry，依赖恢复后自动收敛。完整过程与证据见第 10 节。

> **P2-1 变异复核**：对 approve/rerun/snapshot 三文件重跑 mutator（复用覆盖率快照、串行、关闭删除 shim），结果与结论记于下方第 4 节。

---

## 4. P2-1 变异复核（补测试前后对比）

对 `internal/dispatch` 的 approve/rerun/snapshot 三文件重跑真实变异（复用覆盖率快照、串行、`CODEBUDDY_SAFE_DELETE_ENABLED=0`）。对比三工具质量门报告的补测试前数据：

| 文件 / 函数 | 补测试前 | 补测试后 | 说明 |
| --- | --- | --- | --- |
| `ApproverHandler.Handle` | 11 killed / 3 survived = 78.6% | **14 killed / 0 survived = 100%** | 单字段缺失、Patch 失败、审批人身份断言全杀 |
| `RerunHandler.Handle` | 19 killed / 4 survived = 82.6% | **18 killed / 0 survived = 100%** | Delete 非 NotFound 上抛、NotFound 忽略生效 |
| `isSHA256Hex` / `ParseSnapshot` | — | **11/11、4/4 = 100%** | 非法 hex 用例生效 |
| 合计（三文件） | 78–83% | **58 killed / 3 survived / 4 uncovered = 95.1%** | — |

**3 个幸存变异体复核**：
- `approve_handler.go:54 == -> !=`：首轮仍存活——原测试只断言 decisions 长度（变异下 alice 重复 2 条恰好也是 2），补上"审批人身份集合必须含 alice 和 bob"断言后被杀（单文件复核 14/14 = 100%）。这是本轮新发现并修复的真盲区。
- `snapshot.go:31 < -> <=`：对唯一 Name 数组排序等价，等价变异体，无需补测试。
- `snapshot.go:82 false -> true`：错误信息文案变化，测试只关心是否返回错误，等价变异体。

报告所列 5 个真盲区已全部消除；剩余 2 个为已确认的等价变异体。

---

## 5. 全量 gate 验证

| 仓 | 命令 | 结果 |
| --- | --- | --- |
| hub | `go build ./...` + `go vet ./...` + `go test ./...` + `gofmt -l .` | 全绿，exit 0，gofmt 无输出 |
| runner | `go build ./...` + `go vet ./...` + `go test ./...` + `gofmt -l .` | 全绿，exit 0，gofmt 无输出 |
| console | `pnpm test`（9 组脚本 + property） | 全绿：22/22 + 26/26 + 71/71 + 25/25（service-tree，含本轮新增 3 例）+ 6/6 + property，exit 0 |
| runner | `make check-crds` + ci.yml YAML 语法 | 通过 |

> 本轮所有代码改动：hub 2 文件（auth.go 改、auth_discovery_test.go 新增）、runner 4 文件（handler_edges_test.go / approve_handler_test.go 新增改动、ci.yml 改）、console 1 文件（service-tree-smoke.mjs）。均为测试与容错逻辑，未改业务行为语义。变更产物（覆盖率快照、mutation-workers）已清理。

---

## 6. 两个薄弱点补测（rollout_controller / tree.ts）

针对三工具质量门报告点名的两个质量洼地补单测。**第一性原理根因**：二者的决策逻辑与 I/O/框架职责揉在同一函数里——想验证一个状态判定就得搭 fake client + 全套对象，导致测试供给跟不上状态机复杂度增长（`rollout_controller.go` 是全项目 CC 最高的函数，CC=38）。最高杠杆的补法不是堆 mock 报错测试，而是**把可纯判定的逻辑用表驱动钉死 + 用构造对象触发决策分支**。

### 6.1 runner `rollout_controller.go`（变异 48.2% → 62.5%）

**补测**（新增 2 文件）：
- `rollout_helpers_test.go`：纯函数表驱动测试——`currentStep`（越界/负数）、`weightReplicas`（含 total≤0）、`canaryReplicaState`、`canaryDeploymentHasReplicaFailure`（含多条件扫描）、`rolloutSvcTargetPortEnv`（unset/空/合法/非法/负值）、`canaryIngressSpec`、`canaryHealthy` 的三类前置门。
- `rollout_decisions_test.go`：用 fake client + 构造对象触发的决策分支——terminal hold 不复活、aborted 注解兼容保持 + CompletionTime 幂等、Spec/legacy paused 保持、promote 在回滚后被拒、promote 越界到 Healthy、operator 文案、promote 清 legacy paused、rollback CompletionTime 幂等、pause 在终态被忽略、未知意图被清。

**补测暴露并修复 3 个真实缺陷**（这是补测的直接价值，非仅为提分）：
1. **`currentStep` 负索引 panic**：`CurrentStepIndex` 是 `int32` status，无 minimum 约束；负数时 `Steps[-1]` 直接 panic → controller CrashLoop。加 `idx >= 0` 守卫。
2. **`applyDesiredAction` pause-ignored 分支 status 消息丢失**：原顺序「先设 `Status.Message` → 后 `clearDesiredAction`(Patch Spec) → `Status().Update`」。Patch 的 API 响应会把服务端当前 Status 解码回 `ro`，覆盖尚未落盘的消息。改为先 Patch 再写消息，与 promote/rollback 分支一致。
3. **unknown-intent 分支同类消息丢失**：同上，调整 Patch/写消息顺序。

**变异复核**（复用覆盖率快照、串行、`CODEBUDDY_SAFE_DELETE_ENABLED=0`）：

| 函数 | 补测前 | 补测后 |
| --- | --- | --- |
| 合计 | 67 killed / 72 survived / 59 uncovered = **48.2%** | 110 killed / 66 survived / 25 uncovered = **62.5%** |
| `applyDesiredAction` | 69.4% | **86.0%** |
| `currentStep` / `canaryReplicaState` / `canaryDeploymentHasReplicaFailure` / `canaryIngressSpec` | 0% / 0% / 0% / uncovered | **各 100%** |
| `rolloutSvcTargetPortEnv` | 0% | **71.4%** |
| `Reconcile` | 54.9% | 56.1%（提升有限：剩余多为需 mock client 报错的防御分支） |

> `scaleDeployment`/`applyDecision`/`ensureCanaryIngress` 等仍 0%：其存活点集中在 `SetControllerReference`/`Create`/`Patch` 失败路径，需 interceptor 注入 client 错误才能触发，本轮未做（收益低于复杂度）。剩余 66 存活中该部分为已知保留风险。

### 6.2 console `src/utils/tree.ts`（变异 63.8% → 73.9%）

`computeWindow` 的关键边界在上一轮已补（rowHeight=0/total≤0/overscan=0 吸附）；本轮补齐 `ensureVisible` 与剩余窗口边界：
- `ensureVisible`：行高默认值 `??` 边界、`top<scrollTop` 严格不等、贴底 `Math.max` 下界、显式 `rowHeight=0`。
- `computeWindow`：`overscan=0` 非吸附场景、小 total + 大视口吸附时 start 夹到 0。

`service-tree-smoke.mjs` 用例 25 → 30。变异复核：`ensureVisible` 50%→70%、`computeWindow` 59.3%→70.4%，合计 **63.8% → 73.9%**（killed 30→34）。剩余 12 个存活经逐行复核均为等价变异（`total=0` 时继续计算 end 仍为 0、`viewportHeight` 可选参数默认值、边界常量变体等），无新增真盲区。

### 6.3 本轮 gate

| 仓 | 命令 | 结果 |
| --- | --- | --- |
| runner | `go build` + `go vet` + `go test ./...` + `gofmt -l` | 全绿，exit 0，gofmt 无输出 |
| console | `pnpm test`（9 组脚本 + property） | 全绿：22/22 + 26/26 + 71/71 + **30/30**（service-tree）+ 6/6 + property，exit 0 |

> 本轮 runner 改动：`rollout_controller.go`（3 处 bug 修复 + 负索引守卫）、`rollout_helpers_test.go`（新增）、`rollout_decisions_test.go`（新增）；console：`service-tree-smoke.mjs`（+5 用例）。变异/覆盖率产物已清理，工作区仅留预期源码变更。

## 7. 本质修复：Status/Spec 写入机制隔离

第 6 节修的 3 个 bug（负索引 panic + 两处消息丢失）当时是逐点修复。从第一性原理复盘，两处消息丢失是**同一个本质根因**的两次显形，逐点修顺序只是治标。

### 7.1 最本质原因

`Rollout` 对象上，**意图（Spec/annotation）与观测（Status）共用同一个可变指针**，而 K8s client 的 `Patch`/`Update` 都会把服务端表示回写进这个指针。于是：

- 任何「先写 `ro.Status.*` → 再对同一个 `ro` 做 Spec/annotation Patch」的路径，Patch 的 API 响应都会用服务端当前 Status 反序列化覆盖 `ro`，未落盘的 Status 字段被静默吞掉。第 6 节的两处消息丢失正是如此。
- 逐点「调整赋值顺序」只是在具体分支上回避了冲突；只要有人在别处再写「先 Status 后 Patch」，bug 立刻复发。**根因是机制允许这种写法，而不是某个分支写错了顺序。**
- （负索引 panic 属另一条根因链：Status 字段是外部可写的 API 输入，却未在数据入口建立不变量，已在第 6 节加守卫。）

用 fake client 复现证实：旧式 `r.Patch(ctx, ro, MergeFrom(base))` 执行后，内存里预设的 `ro.Status.Message` 确实被清空——这不是推测。

### 7.2 机制修复（而非顺序修复）

在 `rollout_controller.go` 引入两个统一写出口，让「正确」成为唯一可能的写法：

| 出口 | 职责 | 为什么治本 |
| --- | --- | --- |
| `patchRollout(ctx, ro, mutate)` | 所有 Spec/annotation 写作用于 `ro.DeepCopy()`，Patch 打在副本上 | API 响应只回写副本，调用方 `ro.Status` 不受污染；`MergeFrom` 无乐观锁，连续 Patch 不冲突 |
| `commitStatus(ctx, ro)` | 所有 Status 写走 fresh `Get` + 最新 resourceVersion + `Status().Update` | 不受前序 Spec Patch 的 rv 变化影响，Status 独立落盘 |

改造覆盖：`clearDesiredAction`、legacy annotation 清理、legacy→Spec 迁移、删除 paused 标记、timed-pause 迁移，以及 Reconcile/applyDesiredAction 全部 6 处 `Status().Update`——对 `ro` 的直接 `Patch`/`Status().Update` 已清零（仅剩对 Deployment/Ingress 的 Patch，与 Rollout 状态无关）。

### 7.3 回归测试锁定不变量

新增 `rollout_status_write_test.go`，3 个用例直接锁定 helper 契约（不绑具体分支）：
- `patchRollout` 后调用方内存 Status 不被覆盖（旧实现必挂——已用临时探针验证 fake client 确实回写覆盖）。
- Spec Patch 之后 `commitStatus` 仍完整落盘 Spec + Status（验证 fresh Get 契约）。
- 真实 pause-ignored 分支：Spec intent 被清 + Status 消息同时保留。

### 7.4 验证与变异复核

| 项 | 结果 |
| --- | --- |
| runner 全量 gate | `go build` + `go vet` + `go test ./...` + `gofmt -l` 全绿，exit 0 |
| 回归测试 | 3 例全过；临时探针证实旧式 Patch 会清空内存 Status（回归非假绿），探针已删 |
| 变异复核 | 重构前 62.5% → 重构后 **62.7%**（111 killed / 66 survived / 25 uncovered）；新增 `commitStatus` 100% |

> 变异得分几乎不变是**预期结果**：本轮是机制重构而非补测，价值不在提分，而在消除「先写 Status 后 Patch」这类 bug 的滋生条件。66 个存活与重构前相同，均为已确认的 client 报错防御分支盲区（需 interceptor 注入错误），未在本次范围。对 `ro` 的直接写调用点已清零，从结构上杜绝该类 bug 复发。

> 本轮 runner 改动：`rollout_controller.go`（两出口 helper + 全调用点切换 + 清理过时注释）、`rollout_status_write_test.go`（新增 3 例）。hub/console 本轮未改。

## 8. 剩余测试盲区补强（P2）

上一轮标记"需 interceptor 注入、收益低于复杂度"的 client 报错分支，本轮补上。

### 8.1 runner `rollout_controller.go`：变异 62.7% → 68.5%

新增 `rollout_client_error_test.go`，9 个用例用 `interceptor.Funcs` 注入 Get/Create/Patch 错误，验证 best-effort 辅助函数出错时不 panic、按设计降级。

| 函数 | 重构后 | 本轮补测后 | 覆盖的分支 |
| --- | --- | --- | --- |
| 合计 | 62.7% | **68.5%**（122 killed / 56 survived） | killed +11，survived −10 |
| `getStable` | 0% | **100%** | Get 错误降级 nil |
| `applyDecision` | 0% | **100%** | nil 分支跳过 + 错误不 panic |
| `ensureCanary` | 12.5% | **62.5%** | Get 非 NotFound 错误、Create 错误 → nil |
| `ensureService` | 14.3% | **71.4%** | Get 非 NotFound 错误、Create 错误 → nil |

> `scaleDeployment`（0%）/`ensureWorkload`（25%）仍有存活：前者是 `replicas != nil` 等值变异与 Patch err（后者只 log、无可观测状态，属等价/低价值）；后者是 `SetControllerReference` 错误（需非法 owner）。这两处不再追——继续补需伪造 client 内部状态，收益低于复杂度。

### 8.2 console utils 纯逻辑：新增 19 项断言

新增 `utils-pure-smoke.mjs`（已接入 `pnpm test` 为 `test:utils-pure`），覆盖此前零覆盖的 4 个纯逻辑模块：
- `pipeline.ts`：任务类型派生优先级（Release > Approval > Build）、空白 trim 判空、阶段模式切换。
- `search.ts`：分档打分（全等>前缀>子串>路径>类型>别名）、四类路由、DTO 翻译、键盘导航不环绕。
- `theme.ts`：主题解析回退、切换、按钮文案（下一步动作）、灰阶只在 "1" 时开。
- `agentOp.ts`：SSE 事件解析（注释/多行 data/默认值）、事件解码、终态判定。

19 项断言全过。这些模块零 import、可无浏览器直测，是"正确渲染/导航/派发"的判定核心。

> `src/api/`（25 文件）仍零覆盖：它牵出 axios 与 pinia store，无法用 Node 类型剥离直测；若强行补需引入 jsdom + mock，属结构性取舍（详见第 9 节）。

### 8.3 本轮 gate

| 仓 | 命令 | 结果 |
| --- | --- | --- |
| runner | `go build` + `go vet` + `go test ./...` + `gofmt -l` | 全绿，exit 0 |
| console | `vue-tsc --noEmit` + `pnpm test` | 全绿：22/26/71/30/6 + property(12018 checks) + **utils-pure(19)** |

## 9. 统一遗留清单（交付状态总表）

散落于本报告与 `QUALITY-GATE-3TOOLS-REPORT.md` 的保留项统一收口于此，供交付与审计。状态分三类：**已闭环** / **保留（附理由与重启条件）** / **他域**。

### 9.1 已闭环

| 项 | 处置 | 证据 |
| --- | --- | --- |
| hub 启动 OIDC 瞬态失败 CrashLoop（P0-1） | 代码层修（有界重试 150×2s 对齐 keycloak startupProbe）+ 新镜像部署 | `auth_discovery_test.go` 4 例；新旧镜像对照端到端见第 10 节（旧版 CrashLoop / 新版 0 重启 + retry + 自动收敛） |
| dispatch 测试盲区（P2-1） | 补测 + 发现幂等真盲区并修 | 变异 78-83% → approve/rerun 100% |
| rollout 负索引 panic + 两处消息丢失 | 第 6 节点状修 + 第 7 节机制隔离根治 | `rollout_status_write_test.go` 3 例锁定不变量 |
| rollout / tree.ts 薄弱点（P2-2） | 补测 | 48.2→68.5%（累计）、63.8→73.9% |
| rollout client 报错分支 / console utils（P2） | 本轮补测 | 62.7→68.5%、utils-pure 19 checks |
| check-crds 未入 CI（P3-1） | 接入 runner `ci.yml` | `make check-crds` + YAML 语法通过 |

### 9.2 保留（附理由与重启条件）

| 项 | 状态 | 理由 | 重启条件 |
| --- | --- | --- | --- |
| `scaleDeployment`/`ensureWorkload` 剩余存活 | 已知风险（低） | 等值变异与 `SetControllerReference` 错误，需伪造 client 内部状态，收益低于复杂度 | 若这两函数后续变复杂，补 client interceptor 覆盖 |
| console `src/api/`（25 文件）零覆盖 | 结构性取舍 | 依赖 axios + pinia store，Node 类型剥离无法直测 | 若引入 jsdom + mock 基础设施再补 |
| console `views/` 零覆盖 | 结构性取舍 | Vue SFC 需组件测试环境 | 同上 |
| hub WS 层 / runner agentops/executor 未跑变异 | 测量盲区 | 覆盖率 0%，变异无意义 | 先补测试，再测变异 |
| hub 装配层重构未收口（`main` 全项目最复杂） | 已知风险（中） | 依赖注入已外移至 Options，但 `main` 仍承载过多装配 | 后续专项重构 |
| dryer 270 条结构重复（hub CRUD handler/repository） | 不列为缺陷 | `RegisterCRUD` 工厂 + 分层模板的意图性相似，可理解性中性 | 出现"一处改处处改"信号时再抽取泛型骨架 |
| v1 裸快照不回填（P3-3） | 设计取舍 | 只读识别 + 跨算法显式报错，精确回溯走 hub `pipeline_versions.snapshot`；回填引入状态重写风险 | 无（接受取舍） |

### 9.3 他域（需外部条件，非代码缺陷）

| 项 | 状态 | 前提 |
| --- | --- | --- |
| 云上 gate 实跑（P3-2） | 未做 | `gate-cloud.sh` 已固化，云上环境已清理；恢复环境后按 `--only=smoke` 起 |

> 当前三仓工作区仅含本报告记录的源码/测试/配置变更；覆盖率快照、mutation-workers、`.metrics/` 均已清理。

---

## 10. P0-1 端到端验证（新镜像冷启动竞态）

第 9.3 节原列的「hub 跑新镜像验证冷启动不再 CrashLoop」已执行并闭环。本节记录过程与证据，作为 R1 根因（启动瞬态失败无重试）在真实运行环境的最终确认。

### 10.1 镜像与部署基线

| 项 | 前 | 后 |
| --- | --- | --- |
| 运行镜像 | `harbor.sdpworkflow.com/sdp/software-distribution-platform-hub:v0.0.1` | `...:v0.0.2` |
| 镜像 digest | `sha256:0e69171d...`（无重试逻辑） | `sha256:5aa617c6...`（含 `discoverProvider` 有界重试） |
| 构建产物 | — | `build.sh v0.0.2` 交叉编译 + docker build；二进制含 `OIDC discovery attempt` 重试日志串（旧镜像无） |
| 推送链路 | — | 宿主 docker → kind-registry:5000 → 节点 containerd `ctr pull/tag/push` → harbor（harbor API 确认两 tag 并存，digest 各不相同） |

本地部署基线已从 `v0.0.1` 升到 `v0.0.2`；生产 hub pod 现 Running、0 重启。回滚只需 `kubectl set image deploy/hub container-1=...:v0.0.1`。

### 10.2 竞态复现方法的修正

最初尝试「缩容 keycloak → 0 再 set image」复现冷启动竞态，但新 pod 启动时 discovery 一次成功、未触发重试。原因是 issuer 经网关域名 `www.sdpworkflow.com:8443` 访问，Envoy 对已建立的 keycloak 后端 endpoint 摘除有延迟，缩容后短窗口内 discovery 仍命中缓存/未摘除后端。**结论：缩容 keycloak 不足以稳定制造 discovery 失败窗口**（网关层缓存时序不可控）。

改用确定性对照：临时 deployment 把 `KEYCLOAK_ISSUER` 指向 `https://127.0.0.1:1/realms/sdp`（必然 connection refused），分别用新旧镜像启动，隔离观测 discovery 失败行为；不触碰生产 hub。

### 10.3 对照实验结果

| 观测项 | 旧镜像 v0.0.1（对照组） | 新镜像 v0.0.2（实验组） |
| --- | --- | --- |
| 40s 内容器状态 | Running → Error → **CrashLoopBackOff** | **持续 Running** |
| 重启次数 | 2 次（40s 内） | **0 次** |
| 日志 | `F... hub: failed to init authenticator: ... connect: connection refused` | `W... OIDC discovery attempt 1..20/150 failed (... connection refused); retrying in 2s` |
| 结论 | 单次 discovery 失败即 Fatal → 崩溃（P0 根因复现） | 有界重试 + 存活，符合「依赖就绪是收敛过程」的修复目标 |

### 10.4 依赖恢复后的自动收敛

把实验组 issuer 改回可达地址后，新 pod discovery 一次成功（retry 计数归零）、打印 `listening on :8080`、产生 949 条 DB 活动（启动流程走完并开始服务）、0 重启。证明重试逻辑不仅「不崩溃」，还能在依赖恢复后自动收敛到正常服务状态。

### 10.5 清理与最终态

- 临时对照 deployment（`hub-probe-old` / `hub-probe-new`）已删除，namespace 无残留。
- keycloak 已从缩容状态恢复为 1 副本并 Ready。
- E2E 经网关实测：hub API `/api/v1/pipelines` 返回 401（服务存活、鉴权开启），OIDC discovery 端点返回 200。
- 生产四组件（console / hub / postgres / runner）全部 Ready，hub 为 `v0.0.2`。
