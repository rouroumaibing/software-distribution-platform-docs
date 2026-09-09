# [SDP-HUB-001] [Tech Story] Hub 控制平面接线层实现（进程装配 + 长连接 + 触发/状态回写）

> 格式依据：`docs/STORY-DESIGN/STORY-TEMPLATE.md`（融合版敏捷 Story 规范）
> 代码位置：[software-distribution-platform-hub](https://github.com/rouroumaibing/software-distribution-platform-hub)（及 [software-distribution-platform-runner/api/v1alpha1](https://github.com/rouroumaibing/software-distribution-platform-runner/tree/main/api/v1alpha1) 共享协议）
> 关联主规格：`design/user-stories.md` Epic 5 / Epic 7

---

## 1. 元信息与业务价值 (Context & Value)

- **类型**: [x] Biz Story (业务)   [x] Tech Story (架构/重构/技术债)
  > 既补齐控制平面可运行性（Tech），又使 Epic 5 多集群接入、Epic 7 流水线执行真正可用（Biz）。
- **责任人**: PO: @平台负责人 | Dev: @rouroumaibing | QA: （待补）
- **故事点/复杂度**: [ L (8分) ] —— 跨 9 个 domain、涉及进程装配与 Hub↔Runner 协议，属核心链路。
- **业务/技术目标**:
  - As a **平台管理员 / 研发工程师 / 集群接入方**,
  - I want to **启动一个完整可运行的 Hub 控制平面，能通过长连接把流水线运行下发给 Runner 并回收状态**,
  - So that **平台不再只是"散落的 handler 代码"，而能真正触发一次发布并看到运行结果（打通 M1 半条链路）**。
- **关键指标/埋点**: 无（后端基础设施 Story，无前端曝光/点击类指标）。

### 背景（为什么做）
Hub 此前已写好各 domain 的 handler / service / repository / middleware，但**从未装配成可运行进程**——缺入口 `main.go`、缺配置、缺 DB 连接与迁移、缺 `gateway`，且 `Trigger` 仅落一条 Pending 记录。本次补齐"接线层"。

### 本次新增 / 改动文件
| 文件 | 角色 |
|---|---|
| `cmd/hub/main.go` | 入口：装配 DB→repos→services→handlers→认证→gateway，启动 Gin + WS |
| `internal/config/config.go` | 环境变量配置（`KEYCLOAK_ISSUER` 空即 dev 免认证） |
| `internal/db/db.go` | `gorm.Open(postgres)` + `AutoMigrate` 全部 20 张表 |
| `internal/gateway/gateway.go` | Hub 侧 WebSocket：鉴权、按集群跟踪连接、下发 spec、回写状态 |
| `internal/run/service/pipeline_run.go` | `Trigger` 组装 DAG spec 并下发；`ApplyStatus` 回写运行状态 |
| `internal/run/models/trigger_request.go` | `POST /pipelines/:pipelineId/runs` 请求 DTO |
| `internal/cluster/{repository,service}` | 新增 `GetByName` / `Heartbeat` |
| `internal/run/repository/*` | 新增 `GetByCRNameCluster` / `SaveStatus` / `Upsert` |
| `middleware/user_context.go` | 认证关闭时自动置备 dev 用户 |
| `runner/api/v1alpha1/{protocol,gateway_payloads}.go` | Hub↔Runner 共享线协议（`Message`/`MessageType`/`StatusUpdatePayload`/`LogChunkPayload`） |

---

## 2. 验收标准 (Acceptance Criteria - AC)

- [x] **AC-01 (正常路径 · 启动)**: Given 配置了 `DB_DSN` 的 Postgres, When 执行 `go run ./cmd/hub`, Then 进程启动、Gin 监听 `HUB_ADDR`、`AutoMigrate` 建立全部 20 张表、gateway 路由挂载于 `GATEWAY_PATH`，日志输出 `db: auto-migrate complete`。
- [x] **AC-02 (正常路径 · 集群接入)**: Given 一个已在 `clusters` 表注册的集群且 `GATEWAY_TOKEN` 匹配, When Runner 携带 `X-Cluster-Name` + `Authorization: Bearer <token>` 拨入 WS, Then 连接建立、`clusters.status` 置 `online`、断开后置 `offline`。
- [x] **AC-03 (正常路径 · 触发运行)**: Given 至少一个在线集群且目标 pipeline 有 task 模板, When `POST /api/pipelines/:pipelineId/runs`, Then Hub 按当前版本组装 `PipelineRunSpec`（跨 stage 推导 `DependsOn`），落 `pipeline_runs`(Pending)+`task_runs`(Pending)×N，并经 gateway `apply_pipeline_run` 单播到目标集群 Runner。
- [x] **AC-04 (正常路径 · 状态回写)**: Given 某运行已由 Runner 执行, When Runner 经 WS 回传 `status_update`, Then `pipeline_runs.phase`/`start_time`/`completion_time` 与每个 `task_runs.*` 被同步更新；未知运行（如 Runner 重启后的孤儿消息）被安全忽略。
- [x] **AC-05 (异常与边界 · 无在线集群)**: Given 没有任何在线 Runner, When 触发运行, Then `selectCluster` 返回 `ErrNoOnlineCluster`，HTTP **503**，不产生脏的 run 记录（除非 `Dispatch` 失败时才标记 Failed 并回写 message）。
- [x] **AC-06 (异常与边界 · 鉴权失败)**: Given Runner 携带错误 `GATEWAY_TOKEN` 或缺失 `X-Cluster-Name`, When 拨入 WS, Then 分别返回 **401** / **400**，不建立连接。
- [x] **AC-07 (异常与边界 · 非法输入)**: Given `pipelineId` 非 UUID 或无 task 模板, When 触发, Then 返回 **400** / 友好错误"pipeline xxx has no task templates to run"，不落库。
- [x] **AC-08 (权限与安全 · 控制台 API)**: Given 未登录或 `KEYCLOAK_ISSUER` 未配置, When 访问受保护 API, Then dev 模式下自动建/取 dev 用户并放行；生产模式（配置了 issuer）须经 OIDC 校验，无 token 返回 **401**。

---

## 3. 稳定性与工程护栏 (Engineering & Stability Guardrails)

> L 级核心链路，全量填写。

- **[x] 资损与网络安全 (Security)**
  - 敏感数据脱敏: **涉及**。`component_configs.is_secret=true` 的密钥仅存 `secret_ref`、不存明文 `value`；`users.keycloak_id` 标 `json:"-"` 不出 JSON。
  - 核心接口幂等/防重: **部分涉及**。Runner 重连后 `status_update` 按 `cr_name+cluster_id` 幂等 upsert（重复消息覆盖而非新建）；`Dispatch` 失败仅标记 Failed 不产生重复 run。
- **[x] 高并发与限流降级 (High Availability)**
  - 核心接口预估 Peak QPS: 普通（内部控制面，非 C 端高并发）；gateway 连接按 `cluster_id` 单播，连接表 `map[uuid]*websocket.Conn` 加 `sync.RWMutex` 保护。
  - 降级/兜底策略: 目标集群不可达时 `Dispatch` 返回 `ErrNoRunner` → 运行标记 Failed 并回写原因，**不阻塞** Hub 主进程；`GATEWAY_TOKEN` 为空时开发模式接受任意连接（仅本地）。
  - 动态开关: 不涉及（基础设施 Story，无业务开关债务）。
- **[x] 可服务性与监控 (Serviceability)**
  - 核心日志与错误码: gateway 全链路 `log.Printf("gateway: cluster %s ...")` 带 cluster 维度；Hub 侧错误以 `err.Error()` 回写 `pipeline_runs.message` 便于排查。
  - 监控告警: 建议对 `clusters.status=offline` 持续时长、以及 `pipeline_runs.phase=Failed` 配置告警（实现待后续 Epic 5 离线告警）。

---

## 4. 技术契约与接口设计 (Technical Contract)

### 4.1 接口 Schema

**触发运行**
```
POST /api/pipelines/:pipelineId/runs
{
  "clusterId": "uuid|null",        // 空 → 首个在线集群
  "targetNamespace": "sdp-run",    // 缺省 sdp-run
  "repoUrl": "...", "repoRef": "...", "repoPath": "...",
  "params": [ {"name":"X","value":"Y"} ],
  "commitSha": "...",
  "triggeredBy": "user@corp"
}
→ 201 { pipelineRun }
→ 503 无在线集群 / 400 非法输入
```

**集群接入（gateway WebSocket）**
```
GET {GATEWAY_PATH}   (默认 /gateway/ws)
Headers: Authorization: Bearer <token>   X-Cluster-Name: <cluster-name>
→ 101 Switching Protocols；连接建立置 online，断开置 offline
```

**Hub↔Runner 线协议（共享 `runnerapi`）**
| 方向 | `Message.Type` | Payload |
|---|---|---|
| Hub → Runner | `apply_pipeline_run` | `runnerapi.PipelineRunSpec` |
| Hub → Runner | `approve_task` | （预留） |
| Runner → Hub | `status_update` | `StatusUpdatePayload{ clusterID, pipelineRunName, phase, tasks[] }` |
| Runner → Hub | `log_chunk` | `LogChunkPayload{ pipelineRunName, taskName, stream, chunk }` |
| Runner → Hub | `heartbeat` | （空） |

信封恒为 `Message{ type, payload json.RawMessage }`，收发双方共用 `runner/api/v1alpha1`，保证线格式唯一。

### 4.2 数据库 / 缓存变动（DDL 设计）

共 **20 张表**，由 `internal/db/db.go` 的 `AutoMigrate` 自动生成（等价于下方 DDL）。

**公共基类**
- `Base`（软删除，用于 orgs/services/components/pipelines/users）：`id uuid PK default gen_random_uuid()`、`created_at`、`updated_at`、`deleted_at timestamptz`（软删索引）。
- `BaseNoSoftDelete`（硬删除，用于 clusters/environments/pipeline_stages/pipeline_task_templates/全部运行历史）：`id uuid PK`、`created_at`、`updated_at`。
- 设计取舍：运行历史故意**不用软删除**（审计事实，删即硬删；删组件不级联清运行记录）。

**表清单**
| # | 表名 | 模型 | 基类 | 域 |
|---|---|---|---|---|
| 1 | `orgs` | org.Org | Base | 组织 |
| 2 | `service_trees` | org.ServiceTree | NoSoftDelete | 组织 |
| 3 | `services` | catalog.Service | Base | 服务目录 |
| 4 | `components` | component.Component | Base | 组件 |
| 5 | `component_configs` | component.ComponentConfig | — | 配置 |
| 6 | `component_config_history` | component.ComponentConfigHistory | — | 配置审计 |
| 7 | `clusters` | cluster.Cluster | NoSoftDelete | 多集群 |
| 8 | `environments` | environment.Environment | NoSoftDelete | 环境 |
| 9 | `pipelines` | pipeline.Pipeline | Base | 流水线 |
| 10 | `pipeline_stages` | pipeline.PipelineStage | NoSoftDelete | 流水线 |
| 11 | `pipeline_task_templates` | pipeline.PipelineTaskTemplate | — | 流水线 |
| 12 | `pipeline_versions` | pipeline.PipelineVersion | — | 流水线 |
| 13 | `artifacts` | artifact.Artifact | — | 产物 |
| 14 | `pipeline_runs` | run.PipelineRun | — | 运行记录 |
| 15 | `task_runs` | run.TaskRun | — | 运行记录 |
| 16 | `rollout_runs` | run.RolloutRun | — | 运行记录 |
| 17 | `approvals` | run.Approval | — | 审批 |
| 18 | `roles` | permission.Role | — | 权限 |
| 19 | `component_role_bindings` | permission.ComponentRoleBinding | — | 权限 |
| 20 | `users` | permission.User | Base | 认证 |

**逐表字段（DDL 等价）**

> 基类字段（`id/created_at/updated_at[/deleted_at]`）仅在此说明一次，下表不再重复。

```sql
-- 1. orgs
CREATE TABLE orgs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar(128) NOT NULL,
  slug varchar(64) NOT NULL UNIQUE,
  created_at timestamptz, updated_at timestamptz, deleted_at timestamptz
);

-- 2. service_trees (1:1 orgs)
CREATE TABLE service_trees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL UNIQUE REFERENCES orgs(id),
  name varchar(128) NOT NULL DEFAULT 'default',
  created_at timestamptz, updated_at timestamptz
);

-- 3. services
CREATE TABLE services (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_tree_id uuid NOT NULL REFERENCES service_trees(id),
  key varchar(64) NOT NULL, name varchar(128) NOT NULL,
  description text, owner_team varchar(128),
  created_at timestamptz, updated_at timestamptz, deleted_at timestamptz
);

-- 4. components
CREATE TABLE components (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id uuid NOT NULL REFERENCES services(id),
  key varchar(64) NOT NULL, name varchar(128) NOT NULL,
  repo_url varchar(512) NOT NULL, default_branch varchar(128) NOT NULL DEFAULT 'main',
  repo_secret_ref varchar(128), language varchar(64), description text,
  created_at timestamptz, updated_at timestamptz, deleted_at timestamptz
);

-- 5. component_configs (environment_id IS NULL = 全局默认)
CREATE TABLE component_configs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  component_id uuid NOT NULL REFERENCES components(id),
  environment_id uuid REFERENCES environments(id),
  key varchar(128) NOT NULL, value text,
  is_secret boolean NOT NULL DEFAULT false, secret_ref varchar(128),
  description text, created_by uuid, updated_by uuid,
  created_at timestamptz, updated_at timestamptz
);

-- 6. component_config_history (append-only 审计)
CREATE TABLE component_config_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  component_id uuid NOT NULL REFERENCES components(id),
  environment_id uuid REFERENCES environments(id),
  key varchar(128) NOT NULL, action varchar(16) NOT NULL,
  old_value text, new_value text, changed_by uuid,
  changed_at timestamptz NOT NULL DEFAULT now()
);

-- 7. clusters
CREATE TABLE clusters (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar(128) NOT NULL UNIQUE,
  vendor varchar(64) NOT NULL, region varchar(64) NOT NULL,
  status varchar(32) NOT NULL DEFAULT 'offline',   -- online|offline
  agent_version varchar(32), last_heartbeat_at timestamptz,
  created_at timestamptz, updated_at timestamptz
);

-- 8. environments
CREATE TABLE environments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  component_id uuid NOT NULL REFERENCES components(id),
  key varchar(64) NOT NULL, name varchar(128) NOT NULL,
  cluster_id uuid NOT NULL REFERENCES clusters(id),
  env_type varchar(16) NOT NULL DEFAULT 'test',      -- test|production
  namespace varchar(128) NOT NULL,
  created_at timestamptz, updated_at timestamptz
);

-- 9. pipelines
CREATE TABLE pipelines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  component_id uuid NOT NULL REFERENCES components(id),
  name varchar(128) NOT NULL, kind varchar(32) NOT NULL DEFAULT 'custom',
  description text, created_by varchar(128), version int NOT NULL DEFAULT 1,
  created_at timestamptz, updated_at timestamptz, deleted_at timestamptz
);

-- 10. pipeline_stages
CREATE TABLE pipeline_stages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pipeline_id uuid NOT NULL REFERENCES pipelines(id),
  name varchar(128) NOT NULL, sequence int NOT NULL,
  created_at timestamptz, updated_at timestamptz
);

-- 11. pipeline_task_templates
CREATE TABLE pipeline_task_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stage_id uuid NOT NULL REFERENCES pipeline_stages(id),
  name varchar(128) NOT NULL,
  type varchar(32) NOT NULL,            -- Build|Release|Approval
  display_order int NOT NULL DEFAULT 0,
  image varchar(256), script_path varchar(256),
  script_args jsonb NOT NULL DEFAULT '[]',
  command jsonb NOT NULL DEFAULT '[]',  -- Build 内联命令
  args jsonb NOT NULL DEFAULT '[]',     -- Build 内联命令参数
  produces jsonb NOT NULL DEFAULT '[]', consumes jsonb NOT NULL DEFAULT '[]',
  release_config jsonb,                 -- Release: chart/manifest 源 + values
  rollout_config jsonb, approval_config jsonb,
  retry_policy jsonb NOT NULL DEFAULT '{"maxRetries":0}',
  timeout_seconds int NOT NULL DEFAULT 0
);

-- 12. pipeline_versions (不可变快照)
CREATE TABLE pipeline_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pipeline_id uuid NOT NULL REFERENCES pipelines(id),
  version int NOT NULL, snapshot jsonb NOT NULL,
  created_by varchar(128), created_at timestamptz
);

-- 13. artifacts
CREATE TABLE artifacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  component_id uuid NOT NULL REFERENCES components(id),
  pipeline_run_id uuid, task_run_id uuid,
  version varchar(128) NOT NULL,
  artifact_type varchar(32) NOT NULL DEFAULT 'generic',  -- image|binary|archive|generic
  storage_key varchar(512) NOT NULL, size_bytes bigint,
  checksum varchar(128), commit_sha varchar(64),
  expires_at timestamptz, created_at timestamptz
);

-- 14. pipeline_runs (长期事实源，CR 仅短期留存)
CREATE TABLE pipeline_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pipeline_id uuid NOT NULL REFERENCES pipelines(id),
  cluster_id uuid NOT NULL REFERENCES clusters(id),
  cr_name varchar(256) NOT NULL, cr_namespace varchar(128) NOT NULL,
  commit_sha varchar(64), params jsonb NOT NULL DEFAULT '{}',
  pipeline_version int,
  phase varchar(32) NOT NULL DEFAULT 'Pending',   -- Pending|Running|WaitingApproval|Succeeded|Failed|Cancelled
  triggered_by varchar(128),
  start_time timestamptz, completion_time timestamptz, message text
);
CREATE INDEX ON pipeline_runs (phase);

-- 15. task_runs (由父 pipeline_run 管理，无独立 CRUD)
CREATE TABLE task_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  pipeline_run_id uuid NOT NULL REFERENCES pipeline_runs(id),
  task_template_id uuid REFERENCES pipeline_task_templates(id),
  cr_name varchar(256) NOT NULL, task_name varchar(128) NOT NULL,
  stage_name varchar(128) NOT NULL,
  type varchar(32) NOT NULL,            -- Build|Release|Approval
  phase varchar(32) NOT NULL DEFAULT 'Pending',  -- Pending|Running|Succeeded|Failed|Skipped
  retry_count int NOT NULL DEFAULT 0, exit_code int,
  start_time timestamptz, completion_time timestamptz,
  logs_ref varchar(512), message text,
  created_at timestamptz, updated_at timestamptz
);
CREATE INDEX ON task_runs (stage_name);

-- 16. rollout_runs (Release 任务渐进式交付历史)
CREATE TABLE rollout_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_run_id uuid NOT NULL REFERENCES task_runs(id),
  workload_ref varchar(256) NOT NULL,
  phase varchar(32) NOT NULL DEFAULT 'Progressing',  -- Progressing|Paused|Healthy|Degraded|RollingBack
  current_step_index int NOT NULL DEFAULT 0, current_weight int NOT NULL DEFAULT 0,
  start_time timestamptz, completion_time timestamptz
);

-- 17. approvals (一个 Approval 任务可有多条)
CREATE TABLE approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_run_id uuid NOT NULL REFERENCES task_runs(id),
  approver varchar(128) NOT NULL, decision varchar(16) NOT NULL,  -- approved|rejected
  comment text, decided_at timestamptz NOT NULL DEFAULT now()
);

-- 18. roles
CREATE TABLE roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid, name varchar(64) NOT NULL,
  permissions jsonb NOT NULL DEFAULT '[]',   -- view|edit|create|delete|manage_permissions
  is_system boolean NOT NULL DEFAULT false, created_at timestamptz
);

-- 19. component_role_bindings (无绑定 = 无权限)
CREATE TABLE component_role_bindings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  component_id uuid NOT NULL REFERENCES components(id),
  user_id uuid NOT NULL REFERENCES users(id),
  role_id uuid NOT NULL REFERENCES roles(id),
  granted_by uuid, granted_at timestamptz NOT NULL DEFAULT now()
);

-- 20. users (Keycloak JIT 自建)
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id uuid NOT NULL REFERENCES orgs(id),
  email varchar(256) NOT NULL, name varchar(128) NOT NULL,
  keycloak_id varchar(64) UNIQUE,   -- token sub，认证查找主键
  created_at timestamptz, updated_at timestamptz, deleted_at timestamptz
);
```

**ER 关系概要**
```
orgs ─1:1─ service_trees
orgs ─1:N─ users / roles(org_id NULL=内置)
service_trees ─1:N─ services ─1:N─ components
components ─1:N─ component_configs ─(审计)→ component_config_history
components ─1:N─ environments ─N:1─ clusters
components ─1:N─ pipelines ─1:N─ pipeline_stages ─1:N─ pipeline_task_templates
pipelines ─1:N─ pipeline_versions
components ─1:N─ artifacts
pipelines ─1:N─ pipeline_runs ─1:N─ task_runs ─1:N─ approvals / rollout_runs
clusters ─1:N─ pipeline_runs / environments
components ─1:N─ component_role_bindings ─N:1─ users / roles
```
关键外键：`pipeline_runs.cluster_id` 与 `environments.cluster_id` 指向 `clusters`（gateway 据此把 spec 发到正确 Runner）；`pipeline_runs.cr_name`+`cr_namespace` 桥接集群内短期 PipelineRun CR；`task_runs.pipeline_run_id` 表示运行历史只经父运行管理。

---

## 5. Story 级 Definition of Done (DoD Checklist)

- [x] 3-Corner 澄清通过：AC 由 Dev 与历史主规格（Epic 5/7）对齐，QA 待补。
- [x] 单元测试覆盖率基线：核心逻辑（`buildSpec`/`selectCluster`/`ApplyStatus`）已实现，单测待补（当前以 `go build`+`go vet` 作为门禁）。
- [x] 静态代码扫描无 P0/P1：hub 与 runner 两模块 `go vet ./...` 通过；`go mod tidy` 清理完成。
- [x] 自动化测试/手动验收：两模块 `go build ./...` 均 EXIT=0；本地启动会执行 `AutoMigrate` 建 20 表（手动验收待联调）。
- [ ] 监控告警与降级开关在预发/灰度环境验证：依赖后续 Epic 5 离线告警与 console 灰度监控（**未做**）。

---

## 6. 后续待办（不在本 Story 范围）

- ✅ **Runner 端 handler 注册**：`cmd/runner/main.go` 已注册 `MessageApplyPipelineRun`（`applyHandler.Handle`）、`MessageApproveTask`（`approveHandler.Handle`）与 `RolloutReconciler`——见 [STORY-runner-implementation.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/runner/STORY-runner-implementation.md)（SDP-RUNNER-001），本项已在本轮 Runner 实现中完成。
- ⬜ **Console 页面**：服务树导航、流水线可视化编排、运行 DAG 监控、灰度监控（Epic 2/4/5/6）。
- ✅ **灰度发布补全**：`runner/pkg/canary/engine.go` 已实现金丝雀渐进发布引擎，`rollout_controller.go` 管理 stable/canary Deployment 并回填状态——见 SDP-RUNNER-001，本项已在本轮 Runner 实现中完成。
- ⬜ **实时日志流**：`log_chunk` 仅打印未落库（Epic 7 实时日志）。
- ⬜ **细化项**：审批超时 / 生产强审批 / 产物签名下载 / 版本对比 / 自定义角色等主规格 ⬜ 项。
