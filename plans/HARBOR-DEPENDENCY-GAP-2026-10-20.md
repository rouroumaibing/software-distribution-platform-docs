# 镜像仓库可替换 — Gap 跟踪

> 关联文档：[HARBOR-REGISTRY-INTEGRATION-2026-09-28.md](./HARBOR-REGISTRY-INTEGRATION-2026-09-28.md)（harbor 默认对接现状）、[FIDELITY-KIND-VS-CLOUD-2026-10-09.md](./FIDELITY-KIND-VS-CLOUD-2026-10-09.md)（云上切换目标）。
> 适用范围：docs / env / hub / runner / console 五仓。example / old 与镜像仓库无关，已排除。
>
> **状态**：设计层已经裁定——**镜像仓库为可替换后端，Harbor 仅为默认实现、非强制依赖**。相关设计文档（DATA-MODEL §9.10、runner-reflux-spec §4、install-upgrade-executor-design §6、HARBOR-REGISTRY-INTEGRATION）的"唯一/必须"措辞已修正为"默认 harbor、registry 可配置"（见 §E 落点）。本文现只跟踪**实现层**仍把 harbor 钉死为必装/必用的改点（A/B/C/D），设计层 gap 已关闭。

## 1. Gap 定义

设计意图与现状曾不一致：架构本就指向"镜像仓库可替换"（云保真文档列"云 registry / 公网 harbor"为目标、`image.imageAddr` 参数化、env 预留 `HARBOR_*` / `SDP_JOB_IMAGE_*` 入口），但文档裁定、部署脚本、一个测试断言、三 chart 默认值四处曾把 harbor 钉死，落地成"必须用 harbor"。

文档裁定层已对齐设计（registry 可配置、harbor 默认），设计层 gap 关闭。**残留 gap 在实现层**——部署脚本无条件安装 harbor 本体、runner 自升级测试断言锁 harbor 前缀、三 chart `imageAddr` 默认值写死 harbor、agentops busybox 默认镜像缺 env 覆盖。这四处不改，平台切到非 harbor registry（云厂商镜像仓库、公网 harbor、纯 docker registry）仍会"换源即炸"。

## 2. 结论（一句话）

**设计层：已裁定 registry 可替换、harbor 非强制依赖。实现层：仍四处钉死 harbor**（部署脚本必装、测试断言、chart 默认值、busybox env 缺失），须按 A–D 落实后才能真切换。

## 3. 依赖分层盘点（带行号 + 置信度）

| 层次 | 位置 | 现状 | 是否可换 | 置信度 |
|---|---|---|---|---|
| 设计裁定（已修正） | `docs/shared/DATA-MODEL.md:699` | 原"平台唯一镜像事实源" → 现"平台默认镜像事实源 + registry 可配置" | 是（设计已裁定） | 确认 |
| 设计裁定（已修正） | `docs/shared/runner-reflux-spec.md:113` | 原"必须 是 harbor 引用" → 现"默认 harbor、registry 可配置" | 是（设计已裁定） | 确认 |
| 设计裁定（已修正） | `docs/shared/install-upgrade-executor-design.md:137` | 原"必须预先存在于 harbor" → 现"必须预先存在于目标镜像仓库（默认 harbor）" | 是（设计已裁定） | 确认 |
| 设计裁定（已修正） | `docs/plans/HARBOR-REGISTRY-INTEGRATION-2026-09-28.md:7,20` | 原"唯一镜像仓库" → 现"默认镜像仓库（registry 可配置、harbor 非强制）" | 是（设计已裁定） | 确认 |
| 部署脚本 | `env/local-kind-dev/deploy-local.sh:471` `stage_harbor()`、`:836` 固定调用 | **无条件 helm 安装 harbor 本体**（bitnamicharts/harbor 27.0.3） | 否（harbor 产品必装） | 确认 |
| 部署脚本 | `deploy-local.sh:256-277` `ensure_harbor_project`、`:549` `sdp_login` | 推送/建项目逻辑钉死 harbor 私有 `v2.0/projects` API（非通用 registry） | 否（harbor 专属 API） | 确认 |
| 部署脚本 | `deploy-local.sh:50/:52` `HARBOR_REGISTRY`/`HARBOR_PROJECT` 默认值、`deploy-local.sh:289` 内部推送目标 | 注册表*域名*可经 env 改（默认 `harbor.<base>`）；节点内推目标 `harbor.harbor.svc.cluster.local` 写死 | 域名可配，但内部目标写死 | 确认 |
| 部署脚本 | `deploy-local.sh:695/:788/:802` `--set image.imageAddr` | 实际部署镜像地址由 `${HARBOR_REGISTRY}/${HARBOR_PROJECT}/...` 拼，覆盖 chart 默认 | 部署时经 env 可换 | 确认 |
| 三组件 chart | `hub`/`runner`/`console` `build/*/charts/.../values.yaml:imageAddr` | 硬编码 `harbor.sdpworkflow.com/sdp/*` | 部署时被 `--set` 覆盖，但 chart 默认写死 | 确认 |
| Runner 默认 job 镜像 | `runner/pkg/executor/job_builder.go:44-50`（常量）+ `cmd/runner/main.go:123-126` | 常量写死 harbor，但 **G-7 已落地** `SDP_JOB_IMAGE_*` env 覆盖（`envOr` 已接） | 是（runtime 可换私有 mirror） | 确认 |
| Runner 自升级镜像 | `runner/internal/agentops/handler.go:52` `DefaultRunnerImageName` + `cmd/runner/main.go:114` | 默认 `harbor.sdpworkflow.com/sdp/...runner`，经 `SDP_RUNNER_IMAGE` 覆盖 | runtime 可换，但… | 确认 |
| Runner 自升级断言 | `runner/internal/agentops/upgrade_job_test.go:62-63` | `DefaultRunnerImageName` **前缀必须等于 `harbor.sdpworkflow.com/sdp/`** 否则测试挂 | 否（代码级硬约束） | 确认 |
| Runner busybox 默认 | `runner/internal/agentops/handler.go:46` `DefaultImage="harbor.sdpworkflow.com/sdp/busybox:1.36"` | 写死 harbor | 未找到对应 env 接线 | 未验证-动态 |
| Console CI | `console/.github/workflows/release.yml:6` | "镜像暂不 push 远程 registry，registry 地址确定后定值，届时在此补 push 段" | 明确未决 | 确认 |

## 4. 为什么仍是 gap（设计已定，实现未对齐）

设计侧（已裁定）：registry 可替换、harbor 默认——见 §3 前四行"设计裁定（已修正）"。

实现侧（把 harbor 钉死的点，见 §3 其余行）：

1. `deploy-local.sh` 把 harbor 当成**基础设施必装项**（先于三组件），且推送/建项目逻辑依赖 harbor 私有 API，不是通用 registry 客户端。
2. runner 的 `upgrade_job_test.go` 用测试断言把默认镜像锁在 harbor sdp 项目。
3. 三 chart 默认 `imageAddr` 写死 harbor（部署时被 `--set` 覆盖，但默认值仍误导）。
4. agentops busybox 默认镜像的 env 覆盖出口缺失（未验证）。

即：设计已说"可换"，但**部署链路 + 一个测试断言 + chart 默认值 + busybox 默认**仍把它落地成"必须用 harbor"。

## 5. 解耦改点清单（按组件，含影响面 + 验证 gate）

> 以下改点均为**实现层**落实项，未经实施。每个改点落地后须走对应 gate。设计层口径修正（原 E 项）已完成。

### A. 部署脚本：harbor 从"必装"改为"可选注册表"（env 仓，最高优先）
- **位置**：`env/local-kind-dev/deploy-local.sh` 的 `stage_harbor()`（`:471`）、`ensure_harbor_project`（`:256-277`）、`sdp_login`（`:549`）、`node_push_to_harbor`（`:290`）内部推送目标（`:295` 写死 `harbor.harbor.svc.cluster.local`）。
- **改法**：引入 `REGISTRY_BACKEND`（harbor | generic）开关；harbor 后端保留现状，generic 后端跳过 `stage_harbor` 安装、改用通用 `docker login` + 直接 push 到 `${HARBOR_REGISTRY}`；内部推送目标改为从 `${HARBOR_REGISTRY}` 派生，不再写死 harbor 集群内 DNS。
- **影响面**：`deploy-local.sh` 全链路（infra→harbor→images→platform→components 顺序）、`stop-dev.sh` 的 harbor port-forward 清理（`:81-91` 须条件化）、`env/README.md` 安装顺序描述。
- **验证 gate**：`bash -n deploy-local.sh` 语法；`--stage harbor` 在 `REGISTRY_BACKEND=generic` 下被跳过且不报 FATAL；dry-run 输出 `--set image.imageAddr` 指向目标 registry；本地 kind 一条龙部署到非 harbor 后端后三 pod Running。

### B. Runner 自升级断言放开（runner 仓）
- **位置**：`runner/internal/agentops/upgrade_job_test.go:62-63`。
- **改法**：断言从"前缀必须等于 `harbor.sdpworkflow.com/sdp/`"改为"默认命名须落在已配置 registry 的 project 下"——即断言读取 `DefaultRunnerImageName` 由可配置 registry 前缀构成，而非硬编码 harbor 域名。
- **影响面**：`handler.go:52` 常量仍是 harbor 默认（保留），但契约改为"默认=harbor，可换"；`main.go:114` 的 `SDP_RUNNER_IMAGE` 覆盖已就位，无需改。
- **验证 gate**：`go test ./internal/agentops/...` 通过；把 `DefaultRunnerImageName` 临时改成其他 registry 前缀，测试仍绿（证明断言不再锁 harbor）。

### C. 三 chart 默认值去硬编码（hub/runner/console 三仓）
- **位置**：`build/*/charts/.../values.yaml:imageAddr`（三处）。
- **改法**：默认值改为占位/由 `--set` 注入；或在 chart 注释明确"此值由 `deploy-local.sh` 经 `--set` 覆盖，本地 helm 渲染需自行提供"。避免"chart 默认 harbor、部署实际覆盖"的双源误导。
- **影响面**：`build/*/build.sh` 的 `imageAddr` 解析逻辑（`:75/:118` 等 sed 提取仓库地址）须仍能正确解析外部 registry 地址（含带端口/路径的 registry，如 `ccr.ccs.tencentyun.com/ns`）。
- **验证 gate**：`helm template` 本地渲染不报缺值；`build.sh` 对外部 registry 地址的 `imageAddr` 解析单测/手动验证通过。

### D. agentops busybox 默认镜像补 env 覆盖（runner 仓，未验证项先确认）
- **位置**：`runner/internal/agentops/handler.go:46` `DefaultImage`。
- **改法**：先确认 busybox 是否在 `main.go` 有 `SDP_JOB_IMAGE_BUSYBOX` 类接线（**当前未找到，标未验证**）；若无，补 `envOr("SDP_JOB_IMAGE_BUSYBOX", executor.DefaultBusyboxImage)` 并导出常量，与 G-7 四镜像同构。
- **影响面**：agentops handler 引用 busybox 的处（init 容器/sidecar）；runner chart 的 `values.yaml:34` G-7 覆盖说明需补充 busybox 一行。
- **验证 gate**：`go build ./...` 通过；设 `SDP_JOB_IMAGE_BUSYBOX` 后生成的 agentops Job 使用该镜像（单测或 `kubectl get job` 校验）。

### E. 文档口径从"必须 harbor"改为"默认 harbor、可换"（docs 仓）— **已完成**
- **落点**：`DATA-MODEL.md:699`、`runner-reflux-spec.md:113`、`install-upgrade-executor-design.md:137`、`HARBOR-REGISTRY-INTEGRATION-2026-09-28.md:7,20`，并各补"变更历史"记录本裁定。
- **结论**：设计层"唯一/必须"措辞已全部修正为"默认 harbor、registry 可配置"，设计层 gap 关闭。详见各文档"变更历史"与 [HARBOR-REGISTRY-INTEGRATION-2026-09-28.md](./HARBOR-REGISTRY-INTEGRATION-2026-09-28.md)。

## 6. 分阶段建议

- **P0（拆钉死点）**：A（部署脚本可选化）+ B（断言放开）。这两处是"换源即炸"的硬约束，优先解。
- **P1（去双源误导）**：C（chart 默认值）。属于一致性收口。
- **P2（补缺口）**：D（busybox 覆盖）+ 第 4 类 Build→Harbor 的 registry 抽象入口（STATUS #22②）。属于"完整可替换"闭环的最后一块。

## 7. 验证 gate 总表

| 改点 | 必须通过的 gate |
|---|---|
| A 部署脚本 | `bash -n`；`REGISTRY_BACKEND=generic` 跳过 harbor 段不 FATAL；dry-run `--set` 指向目标 registry；本地 kind 非 harbor 后端三 pod Running |
| B 断言 | `go test ./internal/agentops/...`；改默认前缀后测试仍绿 |
| C chart | `helm template` 不缺值；`build.sh` 解析外部 registry 地址通过 |
| D busybox | `go build ./...`；`SDP_JOB_IMAGE_BUSYBOX` 生效校验 |
| E 文档 | **已完成** |

## 8. 仍未确认项（未验证-动态）

- **D 项 busybox 的 env 覆盖出口**：当前在 `main.go` 未检出 `SDP_JOB_IMAGE_BUSYBOX` 接线，需读 `agentops/handler.go` 全量确认 busybox 是否在某处被覆盖，或确属缺口。
- **generic 后端下的节点镜像预推**：`node_push_to_harbor` 当前经节点 containerd 推 harbor 内部地址；切 generic 后端后，节点拉镜像的 pull secret / mirror 配置（CoreDNS rewrite 等）需重新设计，本文未展开。
- **Console CI push 段**：`release.yml:6` registry 地址未定，待与 A 项 registry 抽象一并拍板。

## 9. 变更历史

| 日期 | 变更内容 | 原因 |
|---|---|---|
| 2026-10-20 | 创建初稿（设计层 + 实现层 gap 全量盘点） | 发现设计文档与代码将 harbor 钉死为强制依赖 |
| 2026-10-20 | v2：状态重定性为"设计已定、实现待落实"；设计层四处"唯一/必须"措辞（DATA-MODEL/runner-reflux/install-upgrade/HARBOR-REGISTRY-INTEGRATION）已修正，E 项标记完成；§3 盘点拆为"设计裁定（已修正）"与"实现钉死"两类 | 用户裁定镜像仓库可替换、harbor 非强制；设计文档优先修正，实现层改点留守待落实 |
