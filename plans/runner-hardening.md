> **性质**：计划（**未实现，草稿**）。状态以 [plans/STATUS.md O-31/O-32/O-33](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **来源**：原 `plans/GAP-FEASIBILITY-STEELMAN-2026-10-20.md`（A2/F3.2、F3.1、F1.1）与 `plans/PLAN-DRAFT-ACTIONABLE-2026-10-20.md`（O-31/O-32/O-33）已删档，其论据已并入本计划文档；状态以 STATUS 为准。
> **拆分**：O-33 已落地的「per-target 三态鉴权」部分见 [runner/features/per-target-auth.md](../runner/features/per-target-auth.md)；本文件为 O-31/O-32 的完整设计与 O-33 的**未落地「缩窄版」**设计。
> **铁律**：本文件只追加；状态判断一律以 STATUS 为准，本文件维护计划规格。
> **文档命运裁定（2026-10-23 分析）**：O-31/O-32/O-33 **FILL/KEEP** —— 设计已实质、可落地；O-33 现状表述已就地修正（三态鉴权已落地，本文件为加法缩窄）。

---

## O-31 Runner 任务容器安全加固（A2 / F3.2）

**目标**：非特权任务容器获得平台默认安全上下文与资源上限，消除「默认以容器 root + 可写根文件系统 + 未 drop capability + 无 seccomp 运行、单任务可吃满节点」的逃逸面；**保留 privileged 构建路径（dind/cind）**。

**现状 / 证据**：
- `runner/pkg/executor/job_builder.go:284` 任务容器 `Resources` 全依赖任务 spec，平台层无默认 requests/limits。
- `job_builder.go:377-383` `applyPrivileged` **仅 `privileged=true` 时**设 `SecurityContext.Privileged`；非特权分支直接 return，不设任何安全上下文。
- runner 自身 pod 已有 requests/limits，但由 runner 创建的任务 Job/Pod 无默认加固。

**代码改动点**：
1. 新增 `applyDefaultSecurityContext(c)`：`RunAsNonRoot=true`、`AllowPrivilegeEscalation=false`、`Capabilities.Drop=["ALL"]`、`SeccompProfile=RuntimeDefault`、`ReadOnlyRootFilesystem=true`。
2. `mainContainer`/`releaseContainer` 末尾、`applyPrivileged` 之后加 `if !tr.Spec.Privileged { applyDefaultSecurityContext(&c) }` —— 加固只作用于非特权分支。
3. chart `values.yaml` 新增 `taskSecurity.defaultResources.{requests,limits}`；`tr.Spec.Resources` 为空时用平台默认值回填。
4. 需写 workspace 的任务挂 writable emptyDir 子路径（如 `/tmp`、构建缓存），避免只读根文件系统击穿。

**验收 gate**：`go build/vet/test` + `gofmt -l` 全绿；kind 跑非特权任务（断言 SecurityContext 已注入且成功）+ dind 构建任务（`privileged=true`，断言未被加固阻断）；单测覆盖 privileged 真假两种 spec。

**钢人结论**：高可落地，前提是非特权分支加固 + 保留 privileged 构建路径；强制 `ReadOnlyRootFilesystem` 会击穿 dind/cind，须挂可写卷——双路径验证不可省。

## O-32 Runner 多副本 LeaderElection 防呆（F3.1）

**目标**：消除「`replicaCount>1` 但忘了开 `LEADER_ELECTION` → 双 reconcile 重复建 Job/Pod」的运维陷阱；不改默认单副本行为。

**现状 / 证据**：`cmd/runner/main.go:144` `LeaderElection: os.Getenv("LEADER_ELECTION")=="true"` 仅 env 显式 true 才启用；`deployment-runner.yaml` 未设该 env；`rbac.yaml:65` 选主权限已备。

**代码改动点**（正确层 = chart，非 main.go）：
1. `deployment-runner.yaml` 在 `container-1` env 段加：
   ```yaml
   {{- if gt (int .Values.basic.replicaCount) 1 }}
   - name: LEADER_ELECTION
     value: "true"
   {{- end }}
   ```
2. `values.yaml`：`basic.replicaCount` 默认 `1` + 注释强提示「多副本必须依赖此联动自动开启选主，勿手动关」。

**验收 gate**：`helm template` `replicaCount=2` → 含 `LEADER_ELECTION=true`；`=1` → 不含；`helm lint` 通过。

**钢人结论**：高可落地廉价修复；无协议变更；与 B3 探针核验一并进 chart 修复。

## O-33 网关共享 token + per-target 身份缩窄（F1.1 / §9.9）

**目标**：消除「所有 runner 共享同一 `TARGET_AUTH_TOKEN`、可冒名未注册 / 他人 target」的横向移动风险；先做**缩窄版**（强制 enroll token + 自动注册仅限可信 vendor/region），全量 per-target 密码学身份留后续。**已实现的三态鉴权部分见 [runner/features/per-target-auth.md](../runner/features/per-target-auth.md)**。

**现状 / 证据**：`gateway.go:129` `ServeWS` **三态鉴权已落地**（详见 [runner/features/per-target-auth.md](../runner/features/per-target-auth.md)）：① 共享 `GATEWAY_TOKEN` legacy 路径（`:133`）② 一次性 enroll token `ConsumeEnrollToken`（`:135`）③ per-target 凭据 `GetByCredential`（`:137`）。本项「缩窄版」为**加法**：`deployment-runner.yaml:31` `TARGET_AUTH_TOKEN` 仍为 chart 单值跨所有 runner 共享（未做 per-target 随机化），ADR-0001 的 per-target enroll-token **绑定仅部分落地**（消费侧已就，签发/强制 + vendor/region 白名单未做）。

**代码改动点（缩窄版）**：
1. hub 侧 bootstrap 分支除 `vendor`/`region` 外，要求 `X-Enroll-Token` 头匹配配置值（配置项 `EnrollToken`）；缺失/不匹配 → 404（沿用严格模式）。
2. chart 注入 per-target 随机 `authToken`（替换共享值）+ `X-Enroll-Token`（由 `target.enrollToken` 提供）。
3. vendor/region 白名单：自动注册限制为配置的可信集合，越界拒绝。

**验收 gate**：持共享 token 但无/错 enroll token 的 runner 无法冒名注册（404）；两个 target 各用独立随机值互不通用；kind 验证合法 enroll+可信 vendor 注册成功、越权 vendor 拒绝。

**钢人结论**：中可落地，先做缩窄版（enroll token 必填 + vendor/region 白名单）；全量密码学身份（签发/轮换）是跨 hub/runner/chart 完整特性，留后续。注：与 O-31/O-32 同属 runner 安全加固，可同批进 chart 修复。
