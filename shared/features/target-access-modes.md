> **来源**：[plans/target-runtime.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/target-runtime.md)（O-40 设计草案）；上游裁决 `DATA-MODEL.md` §9（targets 语义）与 `shared/ADR-0001-runner-first-connect-enrollment.md`（agent 通道身份）。
> **拆分说明**：plans 文档是**设计起草记录**，本文件是**行为规格**（target 三种接入模式如何注册、校验、与 agent 通道共存）。
> **铁律**：本文件**只追加**——新增修订轮次追加到文件尾，禁止改写历史段落；状态判断一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准，本文件只维护行为规格。

---

## 1. 问题与目标

`targets` 表此前只有 agent 通道字段（`EnrollToken`/`RunnerCredential`）+ `TargetKind`（k8s/host）：kubeconfig 直连集群与 ssh 直连主机不落 `targets`，console 统一纳管面缺非 agent 目标的注册入口。目标：扩 `access_mode` 使 `targets` 成为三类目标的统一注册表，agent 通道行为零影响。

## 2. 字段语义（迁移 0022）

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| `access_mode` | varchar(16)，NOT NULL，默认 `agent` | `agent`（runner 出站回连，唯一有 runner 在跑的模式）/ `kubeconfig`（直连集群）/ `ssh`（直连主机） |
| `credential_ref` | varchar，可空 | 指向凭据的引用字符串（kubeconfig / ssh 模式必填；agent 模式留空） |

- **一致性校验**（target service Create/Update 双入口）：`kubeconfig`/`ssh` 必须带非空 `credentialRef`，`agent` 必须留空；`access_mode` 空值归一为 `agent`，非法值 400。
- **存量行兼容**：迁移默认 `agent`，既有 agent target 行为零迁移动作、行为不变。

## 3. 通道边界（agent 透明原则）

- `agent_op.go` / 网关 WS 鉴权 / enroll 流程**不读** `access_mode`：`RunnerCredential` 仅在 `agent` 模式下由首连 enrollment 产生（ADR-0001），非 agent 模式不生成 `EnrollToken`/`RunnerCredential`。
- 非 agent 模式的连接执行（按 `credentialRef` 取凭据直连）由 console/执行器按引用实现——**本期只落注册表与校验**，直连执行器（kubeconfig apply / ssh exec）待后续立项；凭据存在性校验（`credentials` 表反查）随执行器一并落。

## 4. 验证 gate

- 单测/回归：agent 默认（不传 access_mode 落 `agent`）、kubeconfig 缺 credentialRef 拒绝、ssh 带 credentialRef 正常（hub `go test` 全绿）。
- API 契约：`API-REFERENCE.md` targets 节已登记 `access_mode`/`credential_ref`。

## 5. 变更历史

| 日期 | 变更 |
| --- | --- |
| 2026-10-26 | 首次成文：O-40 行为规格，随代码落地（迁移 0022 + service 校验，hub 31 包 gate 绿）。 |
