> **性质**：计划（**未实现，草稿**，两项均为「产品决策留守」）。状态以 [plans/STATUS.md O-40/O-41](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准。
> **来源**：原 `plans/GAP-FEASIBILITY-STEELMAN-2026-10-20.md`（F2.1、F4.2）已删档，其论据已并入本计划文档；状态以 STATUS 为准。
> **铁律**：本文件只追加；状态判断一律以 STATUS 为准，本文件维护计划规格。
> **文档命运裁定（2026-10-23 分析）**：O-40/O-41 **NOT-NEEDED** —— 纯产品决策留守；STATUS 条目即权威，决策拍板后直接进特性文档，无需提前补设计。

---

## O-40 targets 扩 access_mode（F2.1，产品决策留守）

**目标**：统一纳管面——扩 `access_mode`（agent/kubeconfig/ssh）+ 凭据引用，使 console 能管理所有目标类型（不仅 agent）。

**现状 / 证据**：`API-REFERENCE.md:51` 确认 kubeconfig/ssh 直连不落 `targets`（hub `internal/target` 无 `access_mode`）；console 非 agent 目标无注册入口。

**代码改动点（待产品拍板后）**：定义 `access_mode` 枚举 + 各模式凭据引用方式；评估对既有 agent 通道零影响。

**验收 gate**：kubeconfig/ssh 目标可经 console 注册与管理；既有 agent 通道逻辑不变。

**钢人结论**：中可落地（schema + UI 工作量中等），难点在「非 agent 目标是否需 hub 持久注册 + 凭据引用模型」产品决策。先拍板枚举与凭据引用方式，再评估对 agent 通道影响。与 O-33 身份模型同批评估。

## O-41 同 pipeline 并发 / 排队策略（F4.2，产品决策留守）

**目标**：定义同 pipeline 多次 trigger 的并发上限 / 排队语义，防止资源争抢与重复部署冲突。

**现状 / 证据**：能否多次 trigger 同一 pipeline、有无并发上限/排队未核实（runner 无状态 worker 拉 Pending，理论上可并发多 run）。

**代码改动点（待产品拍板后）**：hub 侧 run 创建加并发约束（上限 / 排队）。

**验收 gate**：并发语义（允许并发 / 串行排队 / 上限 N）按产品决策生效。

**钢人结论**：中可落地，难点在语义拍板（允许并发还是串行排队），非纯技术缺口；当前无负载下不构成问题。先拍板并发语义再落地。
