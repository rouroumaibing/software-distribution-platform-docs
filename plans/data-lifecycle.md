> **性质**：计划（**设计草案，待落地**）。状态以 [plans/STATUS.md O-37](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为准（关联 O-26 备份策略）。
> **来源**：原 `plans/GAP-FEASIBILITY-STEELMAN-2026-10-20.md`（C1）与 `plans/PLAN-DRAFT-ACTIONABLE-2026-10-20.md`（C1）已删档，其论据已并入本计划文档；状态以 STATUS 为准。
> **铁律**：本文件只追加；状态判断一律以 STATUS 为准，本文件维护计划规格。
> **命运裁定反转**：原 `NOT-NEEDED-NOW` 占位——2026-10-26 再分析判定为**可落地**：保留基线已由 ArtifactGC 同型模式给出范本，审计/运行日志无限增长是真实风险，不再推迟。

---

## O-37 审计 / 运行日志 / 制品保留与 GC（C1）

**目标**：定义分级保留基线 + 定时 GC，防止审计日志、`pipeline_run`/`task_run` 运行日志、历史制品版本无限增长；与 O-26 备份策略协同（GC 删前先确认已过备份窗口）。

**现状 / 证据（source-grounded 2026-10-26）**：
- 制品 GC 已有成熟范本：`internal/artifact/service/gc.go`（`ArtifactGC`，按 `expires_at IS NOT NULL AND expires_at < ?` 取数、`cleanup_state` 双谓词、批处理 `DefaultArtifactGCBatch=100`、默认关闭 `ARTIFACT_GC_INTERVAL=0`）+ `gc_test.go` 全覆盖；但**只覆盖制品对象**，且默认关闭。
- 审计日志：`internal/permission/models/audit_log.go:13` `AuditLog` 带 `CreatedAt`，但 `internal/permission/repository/audit_log.go` 无任何按龄清理路径。
- 运行日志：`pipeline_run`/`task_run` 有终态字段与时间戳，但无保留期/清理作业；长尾终态 run 永久留存。
- 配置项：`internal/config/config.go:107-124` 已有 `ArtifactGCInterval`/`ArtifactGCBatch` 范式，可同型扩展。

**设计方案（复用 ArtifactGC 模式，新增三类 retention job）**：
1. 配置层（仿 `config.go:107`）：`AuditLogRetentionDays`、`RunLogRetentionDays`、`ArtifactVersionRetention`（按版本数或天数滚删）三档，默认 0=关闭（删数据作业必须显式开启，与 ArtifactGC 一致）。
2. 新增 `internal/retention` 包，三个 GC job 复用 `ArtifactGC` 的「批处理 + 先标记后删 + 可重试 `cleanup_state`」骨架：
   - `AuditLogGC`：`DELETE FROM audit_logs WHERE created_at < now()-RetentionDays`（审计合规长留，默认窗口最大）。
   - `RunLogGC`：仅删 `phase` 为终态且 `finished_at < now()-RetentionDays` 的 `pipeline_run`/`task_run`（**非终态一律不动**，防误删进行中数据）。
   - `ArtifactVersionGC`：在 `ArtifactGC` 之外，对「同 component 超过 N 个历史版本」的过期版本滚删（与 `ArtifactGC` 的 `expires_at` 路径互补）。
3. 调度：在 `main.go` 现有 periodic 启动处挂三个 ticker（与 `ArtifactGC.Run(ctx, interval)` 同型）。
4. 与 O-26 协同：文档约定「GC 删除前确认该数据已过备份保留窗口」作为非直觉约束注释，避免删掉尚未备份的审计记录。

**落地步骤**：
1. `config.go` 加三档 retention 配置 + env 绑定（默认 0）。
2. `internal/retention/{audit,run,artifact_version}_gc.go` 三文件，复用 `ArtifactGC` 骨架（先写 `RunOnce` + 单测，再挂 ticker）。
3. `main.go` 启动 ticker，沿用 `ArtifactGC.Run` 模式。
4. `migrations/` 无需变更（均为 `DELETE`，无 schema 改动）。

**验收 gate**：`go build/vet/test` 全绿；`retention` 单测覆盖「仅删终态/超龄」「批处理有界」「默认关闭不删」三场景（对齐 `gc_test.go` 契约）；手动设 `RunLogRetentionDays=0` 验证默认不删。

**钢人结论**：高可落地。范本现成、改动增量、可逆（默认关闭）；唯一真实风险是 run 日志删错，已用「仅终态+超龄」双保险消除。不再判为「等以后」。
