# Hub REST API 参考与 old→new 接口对账

> **权威端点清单（单一真相源）**。本文档由直接读取 `software-distribution-platform-hub/cmd/hub/main.go` 与各 `internal/*/handler/*.go` 的 `RegisterRoutes` 得出（非推测，核对日期 2026-09-22）。
> Swagger（`hub/docs/docs.go` / `swagger.json` / `swagger.yaml`）是同一清单的自动生成产物，不在此重复。
> 关联文档：`hub/DATA-MODEL.md`（数据模型）、`hub/DELETE-CONTRACT.md`（删除契约）、`console/CONSOLE-UI-DESIGN.md`（前端 IA / 运行中心）、`runner/STORY-runner-implementation.md`（WS 线协议）。

---

## 0. 总览

- **基路径**：`/api/v1`（由 `main.go` 的 `api := r.Group("/api/v1")` 统一承载）。除 Runner WebSocket 网关与本地制品签名路由外，**所有 REST 端点都在该组下**。本文 path 省略 `/api/v1` 前缀，与 `DATA-MODEL.md` 约定一致。
- **鉴权**：生产模式经 Keycloak OIDC 中间件（`middleware.Authenticator` + `UserContext`）；dev 模式（`KEYCLOAK_ISSUER` 空）自动置备 dev 用户放行。组件级路由由 `RequirePermission` 包裹（dev 模式裸挂载）。
- **Runner 网关**：`GET {GATEWAY_PATH}`（默认 `/gateway/ws`）WebSocket，Runner 拨入。**非 REST**，不计入下方清单。
- **通用 CRUD 形状**：`orgs` / `services` / `targets` 经 `common.RegisterCRUD[T]` 生成 `POST /x` · `GET /x/:id` · `PUT /x/:id` · `DELETE /x/:id`；列表端点是否额外暴露见各资源说明。

---

## 1. old 后端 API 组成（`old/` 下两套，两次演进）

### 1.1 `go-devops`（beego，最旧）
- 鉴权 `/api/auth/*`：`/login`(PWD) `/register` `/refresh` `/logout` `/users`(CRUD) `/users/:id` `/sms` `/sms/login` `/wechat/check` `/wechat/callback` `/qq/callback`
- 资源 `/api/*`：`/servicetree`(CRUD) · `/component`(CRUD + `/:id/pipelines|environments|products|changes|parameters|parameters/:environment_id`) · `/pipeline`(CRUD + `/:id/jobs` 触发/查询) · `/environment` · `/product` · `/change`（均 CRUD）
- 系统 `/api/version` · `/api/healthz`

### 1.2 `go-devops-gin`（gin，过渡版，最接近现 hub）
- 公开 `/api`：`/health` · `/version` · `/login` · `/register` + swagger
- 鉴权组 `/api/v1`：`/servicetree`(CRUD + `/:id/children`) · `/service/component`(CRUD + `/pipeline|/env|/product|/changelog|/parameter|/parameter/:id`) · `/service/pipeline` · `/service/env` · `/service/product` · `/service/change`（均 CRUD）
- **没有** orgs / services / targets / runs / releases / artifacts / 权限 等现 hub 概念。

> 结论：`go-devops-gin` 是现 hub 的直系前身——已把服务树抬到 `/api/v1/servicetree`、把 component/pipeline/env/product/change 收在 `/api/v1/service/*` 下，但资源模型仍停留在"扁平 + service 前缀"阶段。

---

## 2. 现 hub 端点清单（代码实测，按资源分组）

### 组织 / 服务树 / 服务
- `POST /orgs` · `GET /orgs`（列表）· `GET /orgs/:id` · `PUT /orgs/:id` · `DELETE /orgs/:id`
- `GET /orgs/:id/service-tree`（读取该 org 的服务树）
- `POST /services` · `GET /services/:id` · `PUT /services/:id` · `DELETE /services/:id`
- `GET /service-trees/:id/services`（列出某服务树下的 service）
- `GET /orgs/:id/services`（**2026-09-22 新增**；按**组织**列其直接子层 service，一次把组织 id 解析成 1:1 服务树再查询 —— console 服务树页懒加载只有组织 id，该端点替它省掉 `GET /orgs/:id/service-tree` 那一跳。组织不存在时错误向上抛，**不静默返回空列表**）
- ⚠️ **无全局 `GET /services` 列表端点**（列表只走 `GET /service-trees/:id/services` 或服务树）；与 console 经树导航的使用方式一致。

### 接入管理（目标注册表）
- `POST /targets` · `GET /targets`（列表）· `GET /targets/:id` · `PUT /targets/:id` · `DELETE /targets/:id`
- **语义见 `DATA-MODEL.md` §9**：`targets` 一行 = 一个部署在被管集群内、出站回连 hub 的 Runner Agent（**目标侧**注册表，**不含任何凭据列**）；`environments.target_id` 为 **NOT NULL** 引用本表，故"注册目标"是建环境的前置步骤。
- ⚠️ **删被环境引用的目标**现为 **FK 报错（500）**，非 `409`（`DELETE-CONTRACT.md` §6 已登记、未修）。
- ⚠️ **网关鉴权偏弱**：`GATEWAY_TOKEN` 为**全局共享** bearer token，目标身份由 Runner 自报 `X-Target-Name` 决定，**无 per-target enroll token**（`DATA-MODEL.md` §9.1）。
- **单机版**（平台与目标同集群）下那一行目标指向的集群**恰好也是平台自身所在集群**，仍是**一行**、不新增对象；**但 runner 的组件身份不因此改变**（2026-09-21 二次裁定，`DATA-MODEL.md` §9.3）。Gen0 安装时 console / hub / runner **同批装齐**，故**平台自身集群那一行在接入管理里天然呈"已装 runner"**、动作是**升级**（`DATA-MODEL.md` §9.3 / §9.9）。
- **runner 的安装 / 升级是 ① 能力层动作**（2026-09-21 二次裁定）：**逻辑全部落在 hub**，console 只调用 API；runner 是接入侧代理组件、**不属"平台自身"**，故不触发 §5.4 的自升级禁令。目标版本取自**版本矩阵 CM**（`DATA-MODEL.md` §9.9 / §9.10）。
- ⚠️ **本表只覆盖 `agent` 通道的目标（2026-09-21 裁决）**：`kubeconfig` 直连的集群与 `ssh` 直连的非容器主机**不落 `targets`**，需扩表承载（`DATA-MODEL.md` §9.7）。因此"平台能纳管的目标 = `GET /targets` 的结果"这一推论**已不成立**。

**待补端点（尚未实现，仅登记形状；通道归属见 `DATA-MODEL.md` §9.5）**

| 端点 | 用途 | 通道 | 状态 |
| --- | --- | --- | --- |
| `POST /credentials` · `GET /credentials` · `GET /credentials/:id` · `DELETE /credentials/:id` | 凭据托管（**只存 ref**，API 只回显 `xxxSet: bool`，明文不落 DB） | `kubeconfig` / `ssh` | ❌ 未实现 |
| `POST /credentials/parse-kubeconfig` | 解析粘贴的 kubeconfig，回显 `server` / `ca` / `skipTLSVerify` / `authMode` / `context` / `namespace`（**拒绝 `exec:` 插件**） | `kubeconfig` | ❌ 未实现 |
| `POST /environments/:id/test` | 连接测试（**逐项 checklist**，见 console §7.12.5） | 全部 | ❌ 未实现 |
| `POST /environments/:id/exec` | 直连执行命令 / 脚本（**需流式输出**） | `kubeconfig` / `ssh` | ❌ 未实现 |
| `POST /targets` · `GET /targets` · `GET /targets/:id` · `PUT /targets/:id` · `DELETE /targets/:id` | 非容器 / 直连目标注册表（`DATA-MODEL.md` §9.7） | `kubeconfig` / `ssh` | ❌ 未实现 |
| `GET /package-versions`（暂名） | **版本矩阵**：返回 `console` / `hub` / `runner` 三个版本号（读 `package-versions` ConfigMap，只读；三值由**人工维护**在 `build/hub/versions.yaml`，遵循 SemVer 2.0.0）。**CM 与 env 已就位**（hub chart：模板 `configmap-package-versions.yaml` + env `PACKAGE_VERSION_*`，见 `DATA-MODEL.md` §9.10），端点本身未实现 | 全部 | ❌ 未实现（载体已就位） |
| `POST /targets/:id/install`（暂名） | **接入编排**：向目标下发安装 runner，版本取版本矩阵 CM；成功后 runner 出站回连（`DATA-MODEL.md` §9.9） | `kubeconfig`（bootstrap） | ❌ 未实现 |
| `POST /targets/:id/upgrade`（暂名） | **接入编排**：把已装 runner 升到版本矩阵 CM 里的版本；前置 = `agent_version` 上报 + per-target 身份（`DATA-MODEL.md` §9.9） | `kubeconfig`（bootstrap） | ❌ 未实现 |

> ⚠️ **安全提示**：`kubeconfig` / `ssh` 通道下 **hub 持有"进入目标"的凭据**。风险是**按条线性叠加**、**不是"爆炸半径反转"**（2026-09-21 二次裁定）：凭据与条目**一一对应**、**无共享万能凭据**，单条失守**不横向扩散**；前提是只存 ref、且 ref 指向 hub 信任域之外（`DATA-MODEL.md` §9.5-2 / §9.7）。安全边界重述见 [README.md §5.6](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/README.md)。

### 组件 / 配置 / 环境 / 制品 / 权限绑定
- `POST /components` · `GET /components/:id` · `PUT /components/:id` · `DELETE /components/:id`
- `GET /services/:id/components`（按 service 列组件；**无全局 `GET /components` 列表端点**）
- `GET /components/:id/configs` · `PUT /components/:id/configs/:key` · `DELETE /components/:id/configs/:key`
- `GET /components/:id/environments`
- `GET /components/:id/pipelines`
- `GET /components/:id/artifacts`
- `POST /components/:id/role-bindings` · `GET /components/:id/role-bindings` · `DELETE /role-bindings/:id`

### 流水线 / 阶段 / 任务
- `POST /pipelines` · `GET /pipelines`（列表）· `GET /pipelines/:id` · `PUT /pipelines/:id` · `DELETE /pipelines/:id`
- `GET /components/:id/pipelines`
- `POST /pipelines/:id/stages` · `GET /pipelines/:id/stages`
- `PUT /stages/:id` · `DELETE /stages/:id`
- `POST /stages/:stageId/tasks` · `GET /stages/:stageId/tasks`
- `PUT /tasks/:id` · `DELETE /tasks/:id`

### 流水线定义版本（历史 / 对比 / 回滚，C-09）
- `GET /pipelines/:id/versions`（列表，新→旧；`?limit=` 默认 50、上限 200，**超限返回 400 而不是静默夹取**；列表**不含快照体**）
- `GET /pipelines/:id/versions/:version`（单版快照体）
- `GET /pipelines/:id/versions/:version/diff?against=<基准版号>`（以 `against` 为基准看 `:version` 改了什么；**方向性**：`:version` 更旧时 added/removed 互换。两者都必填）
- `POST /pipelines/:id/versions/:version/rollback`（把**结构**回填到该版，并**记为新的一版**）

**语义（与实现一致，勿按其它工具的心智模型推断）**
- 版本在**结构性保存**时自动留档：阶段 / 子任务的增删改都会触发快照；只改元信息（name/kind/description）不产生新版本。
- **唯一**的版本号推进点是该服务；body 与上一版**逐字相同**时**去重**（console 一次「保存」会发多条 no-op PUT，不去重会刷出一串空版本）。
- diff **按对象名**（阶段名 / 子任务名）对齐，不按行 id —— id 跨版本必然变化。
- **回滚是追加语义**：只重建阶段与子任务，**不改**流水线元信息（name 受组件内 partial unique index 约束，改名回滚会撞键）；**旧版本行永不删除或改写**。响应 `{restoredVersion, newVersion, stages, tasks}`。

### 组件级角色（§7.3 / B-11 自定义角色）
- `GET /component-roles` · `GET /component-roles/:id`（**读**：挂裸 `api`，供 console 角色选择器；任何有组件级权限的用户都可见）
- `POST /component-roles` · `PUT /component-roles/:id` · `DELETE /component-roles/:id`（**写**：开启鉴权后要求**平台级** `user:manage` —— 角色是权限来源，能改角色 = 能给自己加权限）

**语义**
- `orgId` 为空 = 内置角色（`component-viewer` / `-editor` / `-approver` / `-admin`，**不可改不可删**）；非空 = 组织自定义角色。
- 唯一性：自定义角色 **(org_id, name)** 在组织内唯一；内置角色 **name 全局唯一**。请求体里的 `id` / `isSystem` / `createdAt` 由服务端拥有，传入即被忽略（无法伪造内置角色）。
- `orgId` **不可通过 PUT 迁移**：挪组织会静默改变"它授权谁"。
- `actions` 必须是**非空**的字符串 JSON 数组（空数组 = 谁也不授权，属误配，直接 400）。
- 删除仍有绑定时 `409 + {reasons}`（带引用条数），拒绝而非留下指向不存在角色的孤儿绑定。

### 流水线请求体（创建 / 更新）

console 编排器「保存」时生成的标准请求体，统一映射：
- **新建**：`POST /pipelines`（body 不含 `id`）
- **更新**：`PUT /pipelines/:id`（body 同结构；`:id` 取 `GET /pipelines` 返回的流水线主键）

该 contract 由 `console/CONSOLE-UI-原型.html` 的 `buildPipelineRequest()` 生成（JSON / YAML 可切换预览），字段名与 `internal/pipeline/models`（pipeline.go / stage.go / task_template.go）对齐。

**请求体字段**

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `componentId` | string(uuid) | 所属组件 uuid（→ `components.id`；组件详情页查询作用域主键，见 console 重设计文档 uuid 改造） |
| `name` | string | 流水线名称（组件内唯一，→ `pipelines.name`） |
| `kind` | string | `build` \| `release` \| `custom`（驱动默认 DAG 模板，见 `DATA-MODEL.md`） |
| `description` | string? | 描述；空则省略 |
| `stages[]` | array | 阶段列表，**按 `sequence` 顺序执行** |
| `stages[].name` | string | 阶段名（→ `pipeline_stages.name`） |
| `stages[].sequence` | int | 执行顺序，从 1 递增 |
| `stages[].executionMode` | string | `parallel` \| `serial`：阶段内子任务并行 / 串行（→ `pipeline_stages.execution_mode`）。✅ **已落地（2026-09-22）**：字段可写可读（迁移 `migrations/0010`）；**⚠️ `serial` 的调度行为仍未实现**（backlog C-06），当前只做 API ↔ DB 往返 |
| `stages[].tasks[]` | array | 子任务，**按 `displayOrder` 排序** |
| `stages[].tasks[].type` | string | `Build` \| `Release` \| `Approval`（→ `pipeline_task_templates.type`，runner 派发码）。**派生字段，产品层不暴露为「类型」**：有 `release_config`/`rollout_config` → `Release`（产品语言＝「发布任务」，即阶段任务在做什么），有 `approval_config` → `Approval`（产品语言＝「人工审核阶段」），否则 `Build`（产品语言＝「构建/运行任务」）。三者均为对阶段任务的描述，并非用户可选的类别；`type` 仅作请求体序列化产物进入 hub 供 runner 派发（2026-09-17 用户拍板：UI 不出现 Build/Release/Approval 原词、改用产品语言描述；不引入模版目录） |
| `stages[].tasks[].name` | string | 子任务展示名（→ `pipeline_task_templates.name`） |
| `stages[].tasks[].displayOrder` | int | 阶段内顺序，从 1 递增 |
| `stages[].tasks[].image` | string? | Build 类型：镜像（如 `localhost:5000/toolchain/go:1.22`） |
| `stages[].tasks[].command` | string[]? | 命令，数组形式（如 `["go","test","./..."]`） |
| `stages[].tasks[].args` | string[]? | 参数，数组形式 |
| `stages[].tasks[].timeoutSeconds` | int? | 超时（秒） |

**示例（JSON）**
```json
{
  "componentId": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "name": "日常流水线",
  "kind": "build",
  "description": "编译、构建镜像与单元自测",
  "stages": [
    {
      "name": "构建",
      "sequence": 1,
      "executionMode": "parallel",
      "tasks": [
        {"type": "Build", "name": "compile & test", "displayOrder": 1, "image": "localhost:5000/toolchain/go:1.22", "command": ["go","test","./..."]},
        {"type": "Build", "name": "docker build", "displayOrder": 2, "image": "localhost:5000/toolchain/go:1.22", "command": ["docker","build","."]}
      ]
    },
    {
      "name": "测试",
      "sequence": 2,
      "executionMode": "serial",
      "tasks": [
        {"type": "Build", "name": "pytest -q", "displayOrder": 1, "image": "localhost:5000/toolchain/python:3.12", "command": ["pytest","-q"]}
      ]
    }
  ]
}
```

**与 hub 实际端点的对账（重要）**：现 hub `POST /pipelines`（见上）为**扁平创建**——对应 handler 仅取 `componentId / name / kind / description`，阶段 / 任务经 `POST /pipelines/:id/stages` → `POST /stages/:stageId/tasks` 级联写入（与 §2 端点清单一致）。因此 console 发出的完整 DAG body **当前不能直接被单个 `POST /pipelines` 消费**，需由 console 展开为「先 `POST /pipelines` 建壳 → 再逐个 `POST /pipelines/:id/stages` + `POST /stages/:stageId/tasks` 填充」，或待补「整 DAG 一次提交」端点（见 `console/CONSOLE-UI-DESIGN.md` 附 A · N-7 / NOTE.editor）。本文仅定义 **contract（请求体形状）**；落地形态以 `hub/internal/pipeline/handler/pipeline.go` 代码为准。

### 运行 / 审批 / 回滚
- `POST /pipelines/:id/runs`（触发）· `GET /pipelines/:id/runs`
- `GET /runs` · `GET /runs/:id` · `GET /runs/:id/tasks` · `GET /runs/:id/progress` · `GET /runs/:id/log` · `GET /runs/:id/tasks/:name/log`
- `POST /runs/:id/redispatch` · `POST /runs/:id/tasks/:name/rollout`
- `POST /pipelines/:id/runs/:runId/tasks/:taskName/decision`（审批）

**触发期策略校验（B-11，均在 `buildSpec` 之后、创建 Run 之前）**
- **生产强审批**：目标是生产环境时要求该流水线含审批门；不满足 → `409 + {reasons}`（`ERR.08409005`）。**fail-closed** —— 目标环境类型解析不出来时**拒绝触发**，而不是放行（放行等于静默绕过审批）。console `TriggerRunDialog` 把该结构化拒绝**原样渲染**在对话框内，不只弹一句 toast。
- **审批超时**：等待审批超过该任务审批配置的时限后自动判超时；作业 `APPROVAL_TIMEOUT_INTERVAL`（默认 `60s`）扫描。**顺序是先派发 runner 拒绝、再记 hub 侧关闭**（状态 `Cancelled`），目标离线则**顺延**重试，不写坏状态。运维主体记为 `system:approval-timeout`。

### 跨资源搜索
- `GET /search?q=&type=&limit=`（**2026-09-22 新增**；console 服务树页搜索与 ⌘K 浮层的导航数据源）
  - `q`：关键词，**与 `name` 和 `key` 做 `ILIKE` 匹配**（大小写不敏感；`%` / `_` / `\` 会被转义，不会当成通配符）。`q` 为空返回 `[]` —— **不做全表扫描**（"打开浮层即可浏览"是客户端行为）。
  - `type`：逗号分隔，取值 `service` / `component` / `pipeline`；缺省或为空 = 三类全搜。未知取值**返回 400**（`ERR.01400002`），不静默忽略。
  - `limit`：**每类各取**条数，默认 20、上限 50（超过返回 400，`ERR.01400003`）。故响应最多 `len(type) × limit` 条。
  - 响应：`{ data: [ { type, id, name, path, keyword? } ] }`。`path` 是**展示用**的所属层级（`组织` / `组织 / 服务` / `组织 / 服务 / 组件`），用于区分同名资源（console `CONSOLE-UI-DESIGN.md` §4.1 的硬要求）。`keyword` 是参与匹配但不展示的别名（service.key / component.key）。
  - 排序：每类内 `精确命中 > 名称前缀 > 名称包含`，同档按名称升序（`utils/search.ts` 的客户端分档打分与此同源）。
  - 软删资源不出现（`orgs` / `services` / `components` / `pipelines` 逐表过滤 `deleted_at IS NULL`；`service_trees` 无 `deleted_at` 列，仅作 JOIN 桥）。
  - **不做权限过滤**（刻意）：只回导航信息（类型 / 名称 / 路径 / id），资源访问仍由各详情端点把关。收窄需等账号权限模型的 D1–D6 拍板（见 `console/CONSOLE-UI-DESIGN.md` 附 I.5）。
  - 实现：`internal/search`（models / repository / service / handler）；查询形状由 DB-free 回归测试钉住（`internal/search/repository/search_dryrun_test.go`）。

### 发布
- `POST /releases` · `GET /releases`（列表）· `GET /releases/:id` · `PUT /releases/:id` · `DELETE /releases/:id`

### 制品
- `GET /components/:id/artifacts` · `GET /artifacts/:id` · `GET /artifacts/:id/download` · `POST /artifacts/upload-url` · `DELETE /artifacts/:id`
- 本地存储驱动时，下载经根引擎的 HMAC 签名路由（绕过 `/api/v1` 鉴权，浏览器凭签名直下）。
- **签名下载（B-11 已核对）**：`GET /artifacts/:id/download` 返回**短时效签名 URL**（S3 / MinIO = presigned，Local = hub HMAC 签名回源），console 不持有对象存储凭据、不经中转。此为既有实现，非本轮新增。
- **孤儿对象对账（B-16 对账，周期性、仅报告）**：非 HTTP 端点，是 hub 内后台作业。`ARTIFACT_RECONCILE_INTERVAL`（默认 `0` = **关闭**）> 0 时按该间隔扫描，比对 DB 的 `storage_key` 与对象存储的实际对象，报告"有行无对象 / 有对象无行"。**只报告，绝不删除**（孤儿可能来自进行中的上传）。`ARTIFACT_RECONCILE_PREFIX` 可限定扫描前缀。**驱动未实现 `Enumerator` 接口时不报"干净"，而是告警"未启用对账"** —— 避免把"查不了"读成"没问题"。

### 权限（用户 / 角色 / 组件角色 / 绑定）
- `GET /users` · `GET /roles` · `GET /component-roles` · `GET /component-roles/:id`
- ✅ **组件级自定义角色**（2026-09-22 本轮，B-11）：`POST /component-roles` · `PUT /component-roles/:id` · `DELETE /component-roles/:id`。**读**挂裸 `api`（console 角色选择器要用）；**写**与平台级角色同组，开启鉴权后要求平台级 `user:manage`（角色是权限来源，能改角色 = 能给自己加权限）。`orgId` 为空 = 内置（不可改不可删）、非空 = 组织自定义；唯一性 `(org_id, name)`（内置角色名全局唯一）；`orgId` 不可通过 PUT 迁移；`actions` 必须非空；仍被绑定引用时删 `409 + {reasons}`。详见 §2「组件级角色」。
- `POST/GET/DELETE /components/:id/role-bindings`（见上）
- ✅ **平台级**（2026-09-22 注册，C-10 已落地）：`GET/POST /platform-roles` · `GET/PUT/DELETE /platform-roles/:id` · `GET/POST /platform-role-bindings` · `DELETE /platform-role-bindings/:id`（`GET` 支持 `?orgId=` / `?subjectType=` / `?subjectId=`，且**一并返回已过期的绑定**以便清理）。内置角色（`isSystem`）不可改不可删；角色仍被绑定引用时删除返回 `409 + {reasons}`；主体按 §5.3 校验（`user` = token `sub`；`group` = claim **逐字**、带前导斜杠；`/org:` 为保留前缀，不得作绑定主体）。
- ✅ **权限模型四表 / 审计 / 申请流**（2026-09-22 第八批，`ACCOUNT-PERMISSION-MODEL.md` §3 / §5.1③ / §6 / §7.2）：
  - `GET/PUT/DELETE /resource-ownership`（`?resourceType=&resourceId=`）—— 资源归属**权威源**（§3）；`PUT` 体 `{resourceType, resourceId, ownerOrg, allowedOrgs[]}`。
  - `GET/PUT /role-api-mappings`（`?roleKind=platform|component&roleId=`）· `DELETE /role-api-mappings/:id` —— 「角色 → 接口」映射的**可审阅注册表**（§5.1③）；`PUT` 体 `{roleKind, roleId, actions[]}`（整体替换），启动时 `SyncFromRoles` 与角色定义对账。
  - `POST/GET /permission-requests`（`?status=`）· `POST /permission-requests/:id/approve` · `POST /permission-requests/:id/reject` —— 权限申请审批流（§7.2）；**通过时写绑定并带 `expires_at`**。
  - `GET /userinfo` —— 当前主体的 `subject` / `username` / `groups` / `orgs`（`/org:` 载体解析）/ `roles`（§8 #3）。**仅 UX 用，非安全边界**。
  - **守卫（§11 步骤 4）**：以上平台级路由在**开启鉴权后**统一要求平台级 `user:manage`（种子 `/sdp-admin` 组 → `sdp-admin` 角色即含该动作）；鉴权关闭（dev）时仍裸挂。
  - **审计**：所有 `POST/PUT/PATCH/DELETE` 由 `middleware/audit.go` 统一写 `audit_log`（§6），业务代码零手写。

### Runner 网关
- `GET {GATEWAY_PATH}`（默认 `/gateway/ws`）WebSocket；非 REST。

---

## 3. old → new 映射

| old（gin / beego） | new hub | 说明 |
| --- | --- | --- |
| `/api/servicetree`(CRUD) | `GET /orgs/:id/service-tree` + `POST/GET/PUT/DELETE /services` | 服务树由"独立树资源"变为"org 1:1 树 + services 子资源"；节点删除见 §4 |
| `/api/component`(CRUD) | `POST/GET/PUT/DELETE /components` + `GET /services/:id/components` | 组件恒属于 service |
| `/api/component/:id/pipelines` | `GET /components/:id/pipelines` | 保留（路径改复数） |
| `/api/component/:id/environments` | `GET /components/:id/environments` | 保留；环境改为组件作用域（旧另有独立 `/api/environment`） |
| `/api/component/:id/products` | —（删除） | 产品分组在现模型无对应，见 §5 |
| `/api/component/:id/changes` | —（删除） | 变更日志由 runs/releases 历史覆盖，见 §5 |
| `/api/component/:id/parameters`(env 作用域) | `GET/PUT/DELETE /components/:id/configs`(key + environmentId) | 重命名为 configs；语义近似（组件级键值配置） |
| `/api/pipeline`(CRUD) + `/:id/jobs` | `POST/GET/PUT/DELETE /pipelines` + `POST/GET /pipelines/:id/runs` | jobs→runs，且 runs 升级为完整执行态子系统 |
| `/api/environment`(CRUD) | `GET /components/:id/environments` | 环境不再有顶层端点，归组件作用域 |
| `/api/product` `/api/change`(CRUD) | — | 删除，见 §5 |
| `/api/auth/*`(login/register/sms/wechat/qq) | Keycloak OIDC（外部 IdP） | 自建认证下沉到 IdP；`GET /users` 仅列出 |
| — | `orgs` / `targets` / `stages` / `tasks` / `runs` / `releases` / `artifacts` / `role-bindings` | 现 hub 新增能力（多租户 / 接入 / 编排 / 执行 / 发布 / 制品 / RBAC） |

---

## 4. 删除端点契约（与 `DELETE-CONTRACT.md` 对齐）

- **服务树节点删除**：现 hub **无 `DELETE /api/servicetree/:id`**（该路由不存在）。树节点 ∈ {Service, Component}，对应 `DELETE /services/:id`（service 节点，级联其 components）、`DELETE /components/:id`（叶子）。级联校验 + `409 + {reasons}` 模式不变（详见 `hub/DELETE-CONTRACT.md`）。
- **流水线删除**：`DELETE /pipelines/:id`（级联校验待落地，同契约）。

---

## 5. 被删除 / 下沉的资源与合理性（详见 §7 钢人论证）

- **product / change**：first-class 资源在现 hub 被移除；change 由 runs/releases 历史取代，product 分组暂无对应。若 console 需要产品级 / 变更历史视图，这是当前缺口（须决策是否补回）。
- **parameters → configs**：改名 + 作用域表达变化（env-keyed → key + `environmentId` query），语义保留。
- **auth 自建 → Keycloak**：登录 / 注册 / 短信 / 微信 / QQ 登录全部下沉到 IdP；hub 只做 OIDC 校验 + 内部 RBAC。

---

## 6. 已知缺口（backlog，非文档错误）

- `GET /runs/:id/stage-progress`：`DATA-MODEL.md` §6.5 已确认新增、**待实现**（现仅 `GET /runs/:id/progress`）。
- ~~`platform_roles` / `platform_role_bindings` HTTP 端点：待补（P1-1）~~ ✅ **已补（2026-09-22，C-10）** —— 见本节上一行。
- 全局 `/pipelines` 与 `/releases` 列表：**已实现**（2026-09-15 之后的代码新增）。早期文档（如 `console/CONSOLE-UI-DESIGN.md` 附 A N-3）曾称"无全局 /pipelines、无 /releases 端点"，已过时；本文即其更正，console 文档 N-3 已同步更新。

---

## 7. 设计合理性：双向钢人论证（old vs hub）

**命题**：现 hub 的资源导向、复数名词、父作用域子路由的 REST 设计，相比 old 的扁平 `/api/<资源>` 或 gin 的 `/api/v1/service/<资源>` 分组，是否更合理？

### 正方（现 hub 更合理）
1. **与导航层级同构**：console 懒加载链 `org → service → component` 精确对应 `GET /orgs` → `/services` → `/components`，父作用域子路由（`/components/:id/environments`、`/components/:id/pipelines`）让"组件页管理其全部资源"成为 API 事实（`DATA-MODEL.md` §3 不变式）。old 把 component/pipeline/env 挂在 `/api/component/:id/...` 与 `/api/pipeline` 两个平行平面，组件页聚合需跨多个根资源拼装。
2. **复数资源 + 统一 CRUD 形状**：hub 用 `common.RegisterCRUD[T](rg, "/orgs", svc)` 统一生成 `POST/GET/:id/PUT/:id/DELETE/:id`，新增资源成本极低、契约一致；old beego 每个资源手写 `beego.Router` 四行，gin 版虽分组仍逐路由手写，易漂移。
3. **能力是严格超集**：orgs（多租户）、targets（接入目标生命周期）、stages/tasks（编排 DAG）、runs（快照式执行态）、releases（发布）、artifacts（制品存储）、role-bindings（RBAC）全是 old 没有；pipeline `jobs` 升级为完整 runs 子系统（下发 / 状态回流 / 重派 / 审批 / 回滚），覆盖"构建 → 测试 → 发布到多环境"的北极星目标（`README.md` §5.1）。
4. **鉴权内聚**：权限判定落在 hub 路由 / 中间件（`RequirePermission` + §7 两层 RBAC），组件级 action 与资源 URL 直接对应（`POST /components/:id/pipelines` → `pipeline:create@component_id`）；old 把登录 / 注册 / 短信 / 微信 / QQ 散在 `/api/auth/*`，授权与资源割裂。

### 反方（old 有可取之处 / 现 hub 的代价）
1. **product / change 被砍是能力回退**：old 把"产品"和"变更日志"作为一等实体，现 hub 完全移除——若 console 需要"某产品下所有组件 / 某组件的历史变更"视图，现模型无原生支撑，要靠 runs/releases 历史反推，查询成本高。
2. **自建 auth 下沉到 Keycloak 牺牲自包含**：old 一套 `/api/auth/*` 即可自注册 / 登录 / 短信 / 第三方，现 hub 强依赖外部 IdP 才能跑通登录；离线 / 内网无 IdP 时需额外部署 Keycloak，部署面变大（dev 模式靠免认证绕过，生产必须具备）。
3. **服务树从"单树资源"拆成 org + services + components 三层**，删除 / 移动节点的级联语义变复杂（见 §4）；old 一个 `DELETE /api/servicetree/:id` 递归清整棵子树，现 hub 需分别删 service/component 并各自级联，`DELETE-CONTRACT.md` 的 409 级联校验尚未落地，短期反而比 old 弱。
4. **参数（parameters）从 env 作用域的一等子资源降级为 key + `environmentId` query 的 configs**，旧 `/api/component/:id/parameters/:environment_id` 直读某环境参数的语义丢失，需前端带 query 拼。

### 钢人结论
- **方向正确**：现 hub 的资源导向 + 父作用域 + 复数统一 CRUD，是支撑"多租户 + 组件为锚 + 运行 / 发布编排"目标的更优形态，且与 console 导航、RBAC action 一一对应；old 的扁平 / 分组 URL 与散落 auth 不适合该目标。
- **两类真实代价须记录而非忽视**：
  - **能力回退（需决策）**：product / change 是否需要在现模型补回（产品分组、变更历史视图）——若 console 路线图需要，应在 hub 加 `products` 或在 component 加 `changelog` 视图；当前当作"有意精简"，但须在 console 文档显式说明不再提供产品 / 变更一级入口，避免旧前端 / 用户预期落空。
  - ~~**短期缺口（须补）**：`DELETE-CONTRACT.md` 的 service/component 级联 409 校验、`platform_roles` 端点、`stage-progress`~~ —— 前两项**已于 2026-09-22 落地**（级联 409 见 `DELETE-CONTRACT.md` §6.6；`platform_roles` 端点见本文件「权限」小节 / `STORY-BACKLOG.md` C-10）。
- **文档漂移（本次修正）**：附 A N-3 / 校准 S2 称"无全局 /pipelines、无 /releases 端点"已不成立（代码已加）；`DATA-MODEL.md` 的 `POST /runs`、`DELETE-CONTRACT.md` 的 `DELETE /api/servicetree/:id`、`STORY-hub-implementation.md` 的 `POST /api/pipelines/:pipelineId/runs` 均为旧形态，本次一并修正（见各文档变更记录）。
