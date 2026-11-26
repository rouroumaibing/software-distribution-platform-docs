# 项目认知成本与可理解性审计

> 审计范围：`/Users/rouroumaibing/work/devops` 下 hub / runner / console / docs / env 五个仓；只读审计，未修改任何源文件。
> 下文文件路径均相对该根目录，格式为 `仓/路径:行号`。

## 0. 结论摘要

对一个能力强但完全不了解项目的工程师，**主要认知成本不来自代码量，而来自三类隐性依赖**：

1. **外部编号依赖**：代码注释里大量出现 `§2.8`、`B-11`、`C-09`、`N-26`、`RUNNER-REFLUX-SPEC`，正文在另一个仓库，甚至部分编号的定义指向已删档文档。仅 `software-distribution-platform-hub/cmd/hub/main.go` 就有 90 行带这类编号注释。
2. **装配层承载业务策略**：hub 的启动装配、runner 的注解状态机、console 的巨型管理视图里混着真正的业务规则；读单个 service 文件无法知道它在生产环境是否生效、以什么模式生效。
3. **跨仓术语漂移**：`Environment` 至少四义，`Service / 组件 / component`、`target / agent / runner` 在多处混用；同名类型在前端甚至存在两份定义。

**粗估认知成本**（强工程师、纯阅读+本地验证、不含修 bug）：

| 阶段 | 能达到的能力 | 主要成本 | 粗估 |
| --- | --- | --- | --- |
| 入门 | 能跑通本地 kind 环境、说清三仓职责 | 两套拓扑、入口文档状态矛盾、术语表缺失 | 2–3 人日 |
| 主干贯通 | 能跟完一次 pipeline run：hub 触发 → runner 执行 → 回流 → console 展示 | 外部编号、setter 注入链、WS 多身份语义 | 3–5 人日 |
| 独立改动 | 能安全修改一条核心链路并跑 gate | 装配层策略、手写同步常量、测试 fixture 与 nil 语义 | 3–5 人日 |
| 全面掌握 | 权限 / 灰度 / 协调 / 多环境差异都能接 | 状态机分散、未挂接代码、历史决策 | 再加 1–2 周 |

> 数字仅供排期参考；真实成本高度依赖接手者是否先拿到本文第 5 节的阅读路径。

---

## 1. 规模基线

| 仓 | 文件 / 代码规模 | 认知热点 |
| --- | --- | --- |
| hub | 约 454 文件、313 个 Go 文件、约 *44.5k* 行 Go（含生成码） | `cmd/hub/main.go` 1096 行；`internal/run/service/pipeline_run.go` 1329 行 |
| runner | 92 文件、44 个 Go 文件、约 *7.8k* 行 Go | `internal/controller/rollout_controller.go` 742 行；CRD 生成物 977 行 |
| console | `src/` 94 文件（49 Vue / 44 TS）、约 *16.2k* 行 | `PlatformAdminView.vue` 1917 行；`ServiceTreeView.vue` 1023 行；`utils/pipeline.ts` 663 行 |
| docs | 92 文件 | 单一设计真源，但入口索引与状态快照已出现漂移 |
| env | 134 文件 | local kind 与云上两套拓扑、分散的部署/验证脚本 |

代码总量约 *68k* 行，绝对规模不算巨大；真正放大认知成本的是**一份行为要同时看代码、装配层、外部设计文档和部署脚本**。

---

## 2. 高成本问题清单

### A. 命名与术语

**A1. `Environment` 至少四个含义 — 严重度：高**
证据：`software-distribution-platform-docs/shared/DATA-MODEL.md:518`（领域对象，dev/staging/prod 明确不是领域对象）、`:428-430`（平台级策略标记）、`docs/hub/STORY-BACKLOG.md:92`（runner 侧 `EnvironmentType` 枚举）、`env/local-kind-dev/README.md:1`（部署环境）。
机制：审批、灰度、kubeconfig 解析、部署脚本里都写「环境」，读者无法仅凭词判断是资源、策略标记还是部署目标。
简化：术语表强制写全限定名 `pipeline environment` / `production target flag` / `deployment env`；代码注释与文档禁止裸用「生产环境」。

**A2. `target / agent / runner` 三位一体 — 严重度：中高**
证据：`docs/shared/DATA-MODEL.md:520-525`、`runner/README.md:2,12`、`hub/README.md:44`。
机制：`target` 既是 DB 注册行又是被管机器；`agent` 既是 runner 进程身份，又是接入通道，又是 `agent_ops` 的操作主体（另见 `runner/api/v1alpha1/protocol.go:26,43`）。
简化：定一条硬映射并写进共享术语表——`target=注册行 / agent=runner 进程 / access=通道`，代码中只保留 `runner` 与 `RunnerOp` 两个新标识符。

**A3. `Service` 与分层 service 撞名，产生 `ServiceService` — 严重度：中**
证据：`hub/internal/catalog/models/service.go:10`、`hub/internal/catalog/service/service.go:65`。
机制：领域「服务树服务」和架构层 `service` 同词，出现 `NewServiceService`；前端需求文档又写「Service 级变量组」（`docs/console/features/ui-09-backend-deps-api-contract.md:115`），后端无同名资源。
简化：领域对象改名 `ServiceNode` / `CatalogEntry`，文档统一写 `components（组件）`。

**A4. 同一个概念四个词：`Release` / `Deploy` / `Rollout` / `Canary` — 严重度：中高**
证据：`runner/internal/controller/taskrun_controller.go:232-239`（`reconcileDeploy` + `"deploy task has no rolloutSpec"`），类型枚举却是 `Release`，字段是 `RolloutSpec/Canary`。
简化：统一 `Release` + `Canary`，函数改名 `reconcileRollout`，错误文案与注释同步。

**A5. 前端同名 `credentialApi` 与两份 `KubeParseResult` — 严重度：高**
证据：`console/src/api/environment.ts:84,122-132` 与 `console/src/api/credential.ts:15-52`。
机制：两个文件导出同名对象，各自带一套类型；`KubeParseResult.authMethod` 一处是枚举、一处是 `string`；两处 `list/create` 实现不同。消费方从哪个文件 import 全靠历史习惯。
简化：删除 `environment.ts` 中的副本，改为从 `credential.ts` 再导出。

**A6. Run 相关四个视图 + `?view=` 查询参数 — 严重度：中高**
证据：`console/src/router/index.ts:48,61,71-72`、`console/src/constants/runCenter.ts:13`。
机制：`RunCenterView / RunListView / RunMonitorView / RunsTab` 职责各异，运行中心又用 query 承载 runs/releases/approvals 三视图；release 没有独立 phase，Paused 被刻意不渲染。
简化：按职责重命名为 `*Tab` / `*Panel` 并把 `view` 收敛成字符串联合类型 + 单一映射表。

### B. 抽象、装配与职责

**B1. `main.go` 是真正的策略层 — 严重度：高**
证据：`hub/cmd/hub/main.go:118-1006`：40+ repo/service/handler 手工装配、32 处 `Set*/Attach*`、11 参构造函数；变更窗口闸门、agent-op 对账、retention GC 策略都在此。
机制：读 service 不知道某策略是否被注入、nil 时走什么分支；改一处业务规则要在装配层找接线。
简化：抽 `wire.go` 专门做装配；业务策略提到独立 runtime policy 对象，装配层只做传参。

**B2. `PipelineRunService` 的 setter 注入形成四种 nil 语义 — 严重度：高**
证据：`hub/internal/run/service/pipeline_run.go:166-279`，十余个 `Set*` 分散在多个 service 文件；注释直说「不改构造签名、不动既有测试 fixture」（`:185,189`）。nil 分别表示：禁用功能、回退旧行为、回退任意审批人、静默丢事件（`:171,190,199-203,212-219`）。
机制：漏接一个 setter 不报错，只静默降级；这是"能跑但行为不对"的温床。
简化：一次性 `Options` 注入 + 显式默认值 + 启动日志打印生效策略；严禁 nil 承担多种语义。

**B3. `PlatformAdminView.vue` 1917 行、7 路 `v-if` 分发 — 严重度：高**
证据：`console/src/views/PlatformAdminView.vue:154,878,904-1359`。
机制：7 个管理域塞进一个文件，8 条路由靠 `props.section` 复用；标题用三元链切换。任何一处改动都要理解全部域。
简化：拆成 7 个视图 + 一个薄壳路由，共享表头/权限守卫抽组件。

**B4. 分片协调框架生产未挂接 — 严重度：中**
证据：`hub/cmd/hub/main.go:134` 注明「§2.6 待裁定」；`hub/internal/coordination/shard_queue.go:22-91`、`coordinator.go:335-345` 的 `ShardSource / AttachWorkload` 只有测试调用。
机制：读者会花大量时间理解一套不生效的框架，并误以为生产依赖它。
简化：移入 docs 或文件头标 `Deprecated/unwired`，从主路径的阅读清单中移除。

**B5. `createCrud` 没有 `list` — 严重度：中高**
证据：`console/src/api/crud.ts:7-20`。
机制：工厂只给 create/get/update/remove，各模块自补列表，形成 `listGlobal / listByComponent / listByService / listByServiceTree / list / listByOrg` 六种叫法，无法预期。
简化：工厂补 `list` 原语并统一命名，特殊过滤参数走 options。

### C. 隐式契约与状态机

**C1. 注解 + Status 共同编码 Rollout 状态 — 严重度：高**
证据：`runner/internal/controller/rollout_controller.go:54-63,85-142,572-669`、`runner/pkg/canary/engine.go:220`。
机制：`action / paused / aborted / pause-start` 四个注解与 `Status.Phase` 共同编码状态，靠 patch 触发再次 reconcile；一次 promote 要连改对象两三次。读单个 reconcile 分支看不出全局状态机。
简化：控制意图收敛为 Spec 单一字段（如 `desiredAction`），Status 只做结果；注解只作兼容层。

**C2. 命令写入方式三种并存 — 严重度：中高**
证据：`runner/internal/controller/pipelinerun_controller.go:80`（宣称 reconciler 是 status 唯一写者）、`internal/dispatch/approve_handler.go:77`、`rerun_handler.go:85,107`（直接 `Status().Update`，甚至改 PipelineRun）、`cancel_handler.go:69-80`（只盖注解）。
机制：同类命令三条路径，竞态与终态行为分叉；新人按注释推断会得出错误结论。
简化：全部走 intent → reconciler 落盘，或明确写清例外与理由。

**C3. 手写同步的 annotation key — 严重度：中高**
证据：`runner/internal/controller/rollout_controller.go:58-63` 与 `runner/internal/dispatch/rollout_control_handler.go:14-19`，注释自承 `kept in sync by hand`。
机制：漏改一处命令静默失效，编译器无感。
简化：常量与判定函数下沉到 `api/v1alpha1`，两包共同引用。

**C4. `SnapshotSpec` 声称「对每字段敏感」，实际只哈希 7 个字段 — 严重度：高**
证据：`runner/internal/dispatch/snapshot.go:13-51`；`api/v1alpha1/pipelinerun_types.go:157-179` 中 `ScriptArgs / Command / Args / Repo / Produces / Consumes` 均被忽略。
机制：注释承诺「精确回溯 DAG」（C-03），但改脚本参数不会改变快照；这是**注释与行为直接矛盾**，比缺注释更危险。
简化：对排序后的完整 `Spec.Tasks` 做确定性 JSON + SHA256；若必须投影，注释改成准确列举。

**C5. `TaskTypeTest` 是幽灵类型 — 严重度：高**
证据：`runner/api/v1alpha1/pipelinerun_types.go:22-26` 定义了 `TaskTypeTest`，但 `:133` 的 kubebuilder 枚举仍是 `Build;Release;Approval`，CRD 同步落在 `config/crd/bases/pipeline.sdp.io_pipelineruns.yaml:590`。
机制：Go 类型存在、API 拒绝、controller 无分支——新人无法判断 Test 是否已实现。
简化：补 enum 并重新生成 CRD + 补 controller 分支；或删除该常量。

**C6. 一个开关改变整条行为链 — 严重度：高**
证据：`hub/internal/config/config.go:310`（`AuthDisabled()` 等价于 `KeycloakIssuer == ""`），`hub/cmd/hub/main.go:245,620` 等处据此切换中间件、路由裸挂与 dev/prod 行为。
机制：不是显式 `AuthMode`，而是「某个 URL 为空」这一件事派生出整套鉴权策略；配置名不携带语义。
简化：引入 `AuthMode = oidc | dev` 显式枚举，启动时打印生效模式，禁止用空字符串做模式开关。

**C7. 密钥复用与 typed-nil 陷阱 — 严重度：中**
证据：`hub/cmd/hub/main.go:326-332`（本地制品签名密钥缺省回退到 `GatewayToken`）、`:371-377`（`storage.Client(nil)` 转接口后非 nil，GC 会 panic，必须手工避免赋值）。
机制：一个密钥两种信任用途；一个编译器查不出的 nil 陷阱需要靠注释防呆。
简化：签名密钥独立必填；`NewLocal` 返回具体指针或提供 `IsConfigured()`。

**C8. WS Bearer 头三种身份语义 — 严重度：中**
证据：`hub/internal/gateway/gateway.go:129-180`。
机制：共享 token / 一次性 enroll / per-target 凭据共用同一头，靠 `ConsumeEnrollToken → GetByCredential` 的尝试顺序隐式判别。
简化：显式 auth mode 字段或拆三个入口。

**C9. `runApi.trigger` 丢弃多环境 fan-out 结果 — 严重度：中高**
证据：`console/src/api/run.ts:79-90`（返回类型写成 `PipelineRun[] | PipelineRun`，实际恒为列表却取 `d[0]`；依据只在"e2e-smoke gotcha 实测"注释里）。
机制：触发多 target 后前端只看到第一个 run，其他人需要读注释才知道契约。
简化：返回数组，由调用方决定展示哪一个；后端契约在 API 文档中固化。

**C10. `OpID[:8]` 无长度校验 — 严重度：中高**
证据：`runner/internal/agentops/handler.go:382-395`。
机制：短 OpID 直接 panic；「幂等」依赖截断后的 Job 名。
简化：改用 `sha256(OpID)[:8]` 并校验 OpID 非空。

### D. 文档与知识入口

**D1. 入口 README 与状态权威冲突 — 严重度：高**
证据：`docs/README.md:96,141` 写「云上验收 gate 未跑，#10 依赖」；`docs/plans/STATUS.md:76` 记录 `e2e-canary.sh PASS=9 FAIL=0，#10 关闭`（另见 `:140` 云上环境后续清理，当前不可直接复现）。
机制：新人从入口读到的是过期状态，可能误判功能未完成或重复验证。
简化：入口 README 删除所有状态句，统一写「状态见 STATUS.md」。

**D2. 编号定义指向已删档文档 — 严重度：高**
证据：`docs/hub/STORY-BACKLOG.md:26` 的 B-11 结尾引用 `plans/UNIMPLEMENTED-MODULES-PLAN.md`；该文件在 `docs/README.md:113` 明确列为已删档。
机制：顺着代码里的 `B-11` 追到定义，再从定义追到不存在的章节，链路断裂。
简化：docs/README 建一张「编号 → 权威文件」总表；删档引用就地补「结论见 STATUS §x」。

**D3. 入口住户数自相矛盾 — 严重度：中**
证据：`docs/README.md:138`（16）、`:174`（15）、`docs/shared/README.md:16`（实际 17 行）。
机制：数字快照未同步，入口可信度下降。
简化：只写「以 shared/README 为准」，不写数字。

**D4. 构建工具链表逐字复制四份 — 严重度：中**
证据：`hub/README.md:24-36`、`runner/README.md:24-36`、`env/local-kind-dev/README.md:119-129`、`env/prod-deplyment/README.md:55-65`；权威在 `docs/shared/BUILD-TOOLCHAIN.md`。
机制：nerdctl >= 2.x / buildkitd >= v0.34 的约束改一处即漂移。
简化：各仓只留一句「版本要求见 BUILD-TOOLCHAIN.md」。

**D5. local kind 与云上是两套拓扑，无决策入口 — 严重度：中高**
证据：`env/local-kind-dev/README.md:3,29,33,46`（harbor、CoreDNS rewrite、8443、社区 EG chart）对比 `env/prod-deplyment/README.md:12,41-43`（无 harbor、CCE 官方 EG 插件、ELB + 内网 DNS）；差异清单在 `docs/plans/FIDELITY-KIND-VS-CLOUD-2026-10-09.md:4,69`。
机制：镜像链路、网关、证书分发全不同，新人必须同时维护两套心智模型。
简化：`env/README.md` 顶部加一页 local vs cloud 对照 + 决策树。

---

## 3. 简化方案

### P0：低成本、高收益（建议先做，不动行为）

| 动作 | 验收标准 | 风险 |
| --- | --- | --- |
| 建 `docs/TERMINOLOGY.md`：钉死 Environment 四义、target/agent/runner 映射、Service/组件、Release/Deploy/Rollout/Canary | 代码评审中可直接引用条目 | 低 |
| 建「编号 → 权威文件」总表；修正 docs README 的状态句与住户数 | 从任一 `B-/C-/N-` 编号能一次跳到定义 | 低 |
| 删除 console 重复 `credentialApi` / `KubeParseResult`，补 `Envelope.data` 必填化或统一解包 helper | `pnpm build` + test 绿；不再有 `data as T` 散落 | 低 |
| 补 runner CRD 的 `Test` 枚举或删除幽灵常量 | `make manifests` 生成物与 Go 类型一致 | 低 |
| 修正 `SnapshotSpec` 注释与实现不一致 | 单测覆盖「改 ScriptArgs 必变 hash」 | 低（可能使历史快照失配，需评估） |
| annotation key 常量下沉到 `api/v1alpha1` | 两处引用同一符号，无字面量重复 | 低 |

### P1：结构性简化（一个改动一个闭环）

1. **装配层收敛**：`hub/cmd/hub/main.go` 拆 `wire.go`；`PipelineRunService` 改 `Options` 注入，启动日志打印生效策略。**验收**：nil 只代表一种语义，漏接配置启动即失败；现有 e2e 冒烟数量不变。
2. **管理视图拆分**：`PlatformAdminView.vue` 拆 7 视图 + 壳。**验收**：单文件 < 300 行；路由行为不变。
3. **Rollout 状态机单一化**：Spec 表达意图，Status 表达结果，注解仅兼容。**验收**：promote/pause/cancel 各只有一条写路径；canary E2E 全绿。
4. **命令写入统一**：Approve/Rerun/Cancel 全走 intent → reconciler。**验收**：注释中的「status 唯一写者」重新成立。
5. **配置收敛**：hub 所有 `os.Getenv` / `getenvInt` 收进 `Config` 并校验；`AuthMode` 显式枚举；制品签名密钥独立。**验收**：README/部署清单能列全所有配置项。

### P2：清理认知噪音（排期允许时）

- 未挂接的协调框架移出主代码树或明确标 `Deprecated`。
- `ServiceService` / `reconcileDeploy` / `RunCenterView` 等命名迁移，配合 IDE 重命名一次性完成。
- `ServeWS` 三种身份拆入口；`AgentOp` 自升级契约注释更新为现状。
- env 目录提供 local/cloud 一页对照与决策树；四份工具链表改指针。

> 纪律：P1/P2 每项改动单独成环，跑真 gate（hub/runner `go build | vet | test | gofmt -l`，console `pnpm build + test`）；不要与功能开发混在同一个提交里。

---

## 4. 值得保留的设计

审计不是一边倒的批评，以下几点显著降低了理解成本，改动时不要顺手破坏：

- hub `config.Load()` 把 60+ 配置项集中管理，并逐项说明 `0 = 关闭` 语义。
- hub `runnerproto` 消息类型集中定义，`gateway.readLoop` 单一 switch 分流；`unregister` 用 `owned` 比对防滚动重启误删连接。
- runner 核心逻辑（`findRunnableTasks`、`SnapshotSpec`、`canary.Evaluate`、`BuildJobSpec`）是纯函数且有单测；wire 协议集中在 `api/v1alpha1`。
- console `utils/*.ts` 坚持零 import 纯逻辑，node 可直接冒烟；`constants/runCenter.ts` 与 `styles/tokens.css` 是有效单一真源。
- docs `plans/STATUS.md` 的「完成 / 未完成 / 刻意不做」三段式，以及 hub `REVIEW.md` 的「触发器×检查×依据」清单，都是可直接执行的判卷工具。

---

## 5. 新人第一周建议阅读路径

1. `docs/README.md` 的 §6 形态论 + §4 索引（**跳过状态描述**）→ 建立「docs = 设计真源，STATUS = 状态权威」的边界感。
2. `docs/plans/STATUS.md` §1 → §2 → §3 → 先知道什么已完成，不被 STORY 里的旧勾选框误导。
3. `docs/shared/CROSS-COMPONENT-ALIGNMENT.md` + `DATA-MODEL.md` 的 §9.0 术语段 → 先钉死术语。
4. 三仓 README 的模块地图（hub `:38-52`、runner `:38-43`、console 顶部），按 STATUS 的证据落点跳代码。
5. 主干链路按序读：`hub/internal/run/service/pipeline_run.go` → `hub/internal/gateway/gateway.go` → `runner/api/v1alpha1` → `runner/internal/controller/pipelinerun_controller.go` → `console/src/api/run.ts` + 运行中心视图。
6. `env/README.md` → `env/local-kind-dev/README.md`（先本地跑通）→ `env/prod-deplyment/README.md` + 保真度差异清单。
7. 遇到编号查「编号总表」（P0 建成后）；建成前查 `docs/hub/STORY-BACKLOG.md` 与 `docs/console/features/ui-09-backend-deps-api-contract.md`。

---

## 6. 审计方法与局限

- 初始审计由四个只读审计流覆盖 hub、runner、console、docs/env 跨仓一致性；对高风险结论（巨型文件行数、重复类型、CRD 枚举冲突、状态文档矛盾、手写常量、密钥回退、`as never`）做了二次定点核对。
- 少数计数来自自动统计（代码行数、文件数），含生成代码；用于比较量级，不作为精确度量。
- 第 2–5 节保留为发现时的基线。后续已按第 3 节方案完成代码与文档修复，修复结果与验证见第 7 节。

---

## 7. 第一性原理根因与修复结果

### 7.1 根因归并

| 第一性原理根因 | 具体表现（原审计编号） | 修复原则 |
| --- | --- | --- |
| 知识没有住在代码能被解析的地方 | 外部编号、入口状态漂移、术语漂移、工具链表四份拷贝（D1–D5、A1–A2） | 一个事实只有一个权威位置；其余位置只放指针；编号与术语建本地索引 |
| 装配层退化成隐式配置系统 | env 直读、空字符串当模式、nil 多义、setter 接线、策略散落（B1–B2、C6–C8） | 配置显式化、模式枚举化、依赖一次性注入、启动即校验并打印生效策略 |
| 控制意图与观测结果没有分离 | 注解 + Status 共同编码状态、命令三条写路径、注解常助手抄（C1–C3） | Spec 表达意图、Status 只表达观测、常量单一真源、旧注解只作兼容读路径 |
| 契约在类型层被弱化 | `data?`、同名类型两份、联合类型掩盖真实返回、`as never`（A5、B5、C9） | 强类型 + 完整工厂原语 + 返回值与真实行为一致 |
| 命名承载了过多隐性上下文 | `ServiceService`、`reconcileDeploy`、四个 Run 视图、未挂接框架（A3–A4、A6、B4） | 术语表 + 类型别名/重命名 + 未挂接代码明确标注 |

### 7.2 逐条修复状态

| 原编号 | 修复落点 | 状态 |
| --- | --- | --- |
| A1–A2 | `docs/TERMINOLOGY.md` 建立 Environment 四义与 target/agent/runner 硬映射 | 已修 |
| A3 | hub `ServiceNode` 别名 + 领域注释；术语表统一 components | 已修 |
| A4 | runner `reconcileRollout` + Release/Rollout 文案统一 | 已修 |
| A5 | console 删除 `environment.ts` 中的重复类型/API，统一到 `credential.ts` | 已修 |
| A6 | 四个 Run 视图按角色重命名，`?view=` 收敛为联合类型 + 单表 | 已修 |
| B1 | hub `cmd/hub/wire.go` 承接装配与业务策略，`main.go` 瘦身 | 已修 |
| B2 | `PipelineRunOptions` + `NewPipelineRunServiceWithOptions`，旧构造器保留给测试；启动打印策略摘要 | 已修 |
| B3 | `PlatformAdminView.vue` 1917 行 → 30 行薄壳 + 7 个域视图，最大 273 行 | 已修 |
| B4 | coordination/ShardQueue 标注为主路径未挂接 | 已修 |
| B5 | `createCrud` 补 `list`，六种列表叫法归一 | 已修 |
| C1 | runner `Spec.DesiredAction` 单点表达意图，Status 只记录观测 | 已修 |
| C2 | Approve/Rerun/Cancel 统一为意图 → reconciler 落盘 | 已修 |
| C3 | annotation 常量与判定 helper 下沉 `api/v1alpha1` | 已修 |
| C4 | `SnapshotSpec` 改为完整 Spec 确定性哈希，补字段敏感单测 | 已修 |
| C5 | CRD enum 补 `Test`，codegen 重生成；Test 走通用脚本 Job 路径 | 已修 |
| C6 | hub `AuthMode(oidc|dev)` 显式化，启动打印 | 已修 |
| C7 | 制品签名密钥与网关令牌解耦；typed-nil 用具体指针 helper 消除 | 已修 |
| C8 | gateway `WSIdentityMode` 四模式，自动探测保留但日志标记身份类别 | 已修 |
| C9 | `runApi.trigger` 恒返回 `PipelineRun[]`，调用方自行取用 | 已修 |
| C10 | `OpID` 用 `sha256` 截断命名，短 ID 不再 panic | 已修 |
| D1–D3 | docs README 状态改指针、编号总表 `ID-INDEX.md`、住户数移除 | 已修 |
| D4 | hub/runner/env 两处共四份工具链表全部改为单一指针 | 已修 |
| D5 | `env/README.md` 新增 local/cloud 对照与决策树 | 已修 |

### 7.3 Gate 验证

| 仓 | 命令 | 结果 |
| --- | --- | --- |
| hub | `go build ./...` / `go vet ./...` / `go test ./...` / `gofmt -l .` | 全绿，独立复核 exit 0 |
| runner | `go build ./...` / `go vet ./...` / `go test ./...` / `gofmt -l .` | 全绿，独立复核 exit 0 |
| console | `vue-tsc --noEmit` / `vite build` / `pnpm test` | 全绿，独立复核 exit 0；测试 22/22、26/26、71/71、22/22、6/6 + property 12018 checks |
| docs/env | README 指针与术语一致性核对 | 四份工具链表均指向权威文档，术语表已同步修复后现状 |

> 独立复核 console 时，Vite 清空 `output/dist/assets` 触发沙箱批量删除守卫（88 个文件 > 阈值 50）。改用 `vite build --emptyOutDir false` 后 `vue-tsc + vite + test` 全绿；这是环境守卫，不是代码缺陷。

### 7.4 遗留风险处置

| 原遗留项 | 第一性原理根因 | 处置 | 状态 |
| --- | --- | --- | --- |
| `SnapshotSpec` 历史哈希失配 | 快照字符串不自描述算法，比较语义未定义 | 返回 `v2:<sha256>`；新增 `ParseSnapshot` / `SameSnapshot`，裸 64 位 hex 识别为 v1，跨算法比较显式报错 | 已修 |
| 自定义 values 必须设置签名密钥 | 密钥以明文配置默认值表达，配置与 Secret 契约混同 | chart 统一 `valueFrom.secretKeyRef`；无外部 Secret 时用 `artifact.signSecret` 生成开发 Secret；README 写明生产契约 | 已修 |
| `pause-start` 注解计时 | 时间状态存 metadata，观测数据与 Status 语义分离 | 计时移入 `RolloutStatus.PauseStartTime/PauseStepIndex`，旧注解只做一次性迁移读取；CRD/deepcopy 由 codegen 重新生成 | 已修 |
| `parseTestReport` 无消费方 | API → UI 链路未闭合，解析函数没有落点 | `EnvAccessPanel.vue` 用 `parseTestReport(env.lastTestResult)` 作为历史报告回退，空态由 `ConnectionTest` 兜底 | 已修 |
| 云上验收 gate 只活在文档里 | 验收结论不可复现、无证据留存 | 新增 `gate-cloud.sh` 串联四个 E2E 脚本，解析 `RESULT` 的 FAIL 数判定，落 `gate-evidence/<UTC>/` 与 `summary.txt` | 脚本已固化，待云上实跑 |
| chart CRD 副本漂移（处置中发现） | 同一份 schema 存在两个文件且无同步机制 | 同步三份 chart CRD；新增 `make sync-crds` / `make check-crds` 并在 README 说明 | 已修 |

---

## 8. 遗留处置后的残余风险

- 云上 gate 脚本已完成语法、参数解析与 RESULT 判定检查，但云上环境已清理，四步编排链路尚未实跑；恢复环境后需先跑一次 `gate-cloud.sh --only=smoke` 验证前置条件。
- v1 裸 hex 快照仍留在历史 CR 注解中，解析器只提供只读识别，不回填、不重算；若要做跨算法精确回溯，应走 hub 的 `pipeline_runs.PipelineVersion` → `pipeline_versions.snapshot` 完整 JSON 链路。
- 更换 `artifact.signSecret` 会使未过期的签名 URL 失效（默认 900s）；建议在滚动发布窗口执行密钥轮换。
- `make check-crds` 已接入 runner `ci.yml`，作为 CRD 与 types 一致性门禁；若后续新增 API 类型，变更前仍需执行 `make sync-crds` 同步三份 chart CRD。
