# P0-3 实施计划 — Console 流水线全生命周期 UI（已自 plans/ 迁入 console 域）

> 状态：**A / C / D / B 节全部实施完成**（2026-09-25 收口：A 节 `listGlobal` 直连 + stopgap 下线落地；B「新建入口」实际落在组件详情 · 交付 · 流水线 Tab 的「＋ 新建流水线」；C kind 闸 / D 行内删除此前已落）。当前登记见 [plans/STATUS.md](../../plans/STATUS.md) §1.3。
> 注：运行中心「流水线」视图已在 IA v4.4 移除（归属组件详情），故 §4 中 RunCenterView 的行号引用已过时，A 节实际落地位置为 `useResourceMap.buildResourceIndex`（pipelines 分支改单次 `GET /pipelines`）+ `api/pipeline.ts listGlobal`。
> 依赖前置：P0-1（`/releases` 端点，已落地）、**P0-2（`GET /pipelines` 全局列表，已落地）**。
> 事实基线全部来自 console 仓实代码（file:line 见下），非文档声称。

## 1. 目标与验收 Gate

| 验收项 | 判定 |
|---|---|
| 运行中心「流水线」视图直连真端点 | `GET /pipelines` 返回数据，前端聚合 stopgap 下线 |
| 新建流水线入口存在 | 任意位置可发起 `POST /pipelines` 并落地 |
| 编辑器放开 kind | `build` / `release` / `custom` 流水线均可进入编排 |
| 流水线级删除 | 行内 `DELETE /pipelines/:id` + 确认 |
| Gate 全绿 | `pnpm test:runcenter` 14/14 + 新增 UI 冒烟（新建→编排→删除）+ `vue-tsc --noEmit` 0 错 |

## 2. 现状事实基线（code-grounded）

| 现状 | 证据 |
|---|---|
| 后端 `POST/GET/DELETE /pipelines[/:id]` 齐全 | `hub/internal/pipeline/handler/pipeline.go:33/34/36` |
| 全局 `GET /pipelines`（P0-2 新增） | `hub/internal/pipeline/handler/pipeline.go:36` `rg.GET("/pipelines", h.List)` |
| 后端支持 release/approval 编排 | `hub/internal/pipeline/models/pipeline.go:14`（`kind` 自由字符串）；`task_template.go:19`（`Type Build/Release/Approval`） |
| 前端 `pipelineApi` 已含 `create`/`remove` | `console/src/api/crud.ts:8/17`（`createCrud('/pipelines')`） |
| **无任何「新建流水线」UI 入口** | 全仓 grep `新建流水线|pipelineApi.create` 仅命中无关项；`PipelinesTab.vue:36` 注释「新建入口走服务树/触发对话框已有路径，此处仅编排已有流水线」 |
| 编辑器仅 `build` 可达（两处闸） | `RunCenterView.vue:202-207` `if (p.kind !== 'build')`；`PipelinesTab.vue:24-29` 同 |
| 前端聚合 stopgap 待下线 | `useResourceMap.ts:5-7`（「等全局聚合端点落地后本文件可下线」）；`RunCenterView.vue:14-15,42-43` |
| 编辑器已支持三类任务 | `PipelineEditorView.vue:70-84`（`taskSummary`/`typeIcon` 覆盖 Build/Release/Approval） |

**结论**：P0-3 缺口几乎全在前端；后端零缺口（P0-2 已补最后一块）。

## 3. 拆分：设计稳定项 vs 设计依赖项

> console UI 设计（v3 IA）仍在调整，故按「会不会被设计推翻」二分：

### ✅ 设计稳定（设计定稿前即可实现）
- **A. 下线前端聚合 stopgap，接真端点**
- **C. 放开 kind 限制（删两处闸）**
- **D. 流水线级删除（加行内动作）**

### ⏸ 设计依赖（**等 v3 IA 定稿才做**）
- **B. 新建流水线入口的落点与表单形态**

  v3 重设计可能把「新建」放在运行中心工具栏、服务树右键、或独立「流水线」页；表单是否复用 `ResourceCascade` 选组件、是否分 build/release/custom 向导——这些属「还在调整」的部分，**不在此计划实现，待设计锁定后补 B 节细化**。

## 4. 逐文件改动清单

### A. 数据层：接真端点、下线 stopgap

**`console/src/api/pipeline.ts`**
- 新增 `listGlobal: (p?: Pagination) => listPaged<Pipeline>('/pipelines', p)`（复用 `listPaged`，镜像 `listByComponent`）。

**`console/src/composables/useResourceMap.ts`**
- `buildResourceIndex()` 体：删除 org→service→component→pipeline 四级嵌套循环（`:38-64`），改为一次 `pipelineApi.listGlobal({ page: 1, pageSize: AGG })`,`map` 成 `PipelineRef[]` + `byPipelineId`。
- 保留 `PipelineRef` / `ResourceIndex` 接口与 `byPipelineId` —— **releases 视图仍需它按 `kind==='release'` 过滤运行**（`:141`），不能整文件删。
- 文件头注释（`:1-7`）更新：说明「全局端点已落地，改为单次 `GET /pipelines`；service-tree 全量遍历已移除」。

**`console/src/views/RunCenterView.vue`**
- `load()` 的 `pipelines` 分支（`:125-131`）：`idx.pipelines` 现来自服务端，去掉客户端 `slice` 分页，改为传 `page/pageSize` 给 `listGlobal` 服务端分页；删 `AGGREGATE_SCAN`（流水线视图不再需要，仅 releases 视图保留）。
- `releases` 分支（`:133-146`）暂不变（`GET /releases?scope=global` 即 N-3 仍 pending，仍前端按 `kind` 筛）。
- 顶部注释（`:12-15`）更新：数据源从「前端聚合」改为「`GET /pipelines` + 仍用索引补 kind 名」。

### C. 放开 kind 限制

**`console/src/views/RunCenterView.vue:202-207`**（`openPipeline`）
- 删 `if (p.kind !== 'build') { toast.err(...); return }`，改为任意 kind 直接 `router.push('/pipelines/'+p.pipelineId)`。可选：release/custom 进入时给一行 info toast「release/custom 编排已开放」。

**`console/src/views/component/tabs/PipelinesTab.vue:24-29`**（`openEditor`）
- 同上，删 `kind!=='build'` 闸，直接 push 进编辑器。

> 编辑器 `PipelineEditorView.vue` 已能渲染 Build/Release/Approval 三类子任务（`:70-84`），无需改。

### D. 流水线级删除

**`console/src/views/RunCenterView.vue`** — `pipelines` 表（`:247-265`）
- 末列（现 `<a>编排 →</a>`，`:262`）旁加「删除」动作：`pipelineApi.remove(p.pipelineId)` + `confirm()`/复用 `Modal` 二次确认；成功后 `indexPromise` 失效重拉或本地剔除该行。

**`console/src/views/component/tabs/PipelinesTab.vue`** — 表（`:42-53`）
- 同加行内删除（`pipelineApi.remove(p.id)` + 确认）。

### B.（待定，设计依赖）新建流水线入口

> 实现细则等 v3 IA 定稿。骨架已备：`pipelineApi.create({ componentId, name, kind, description })` 可用；选组件可复用 `components/ResourceCascade.vue`。本计划在 B 定稿前**不实现**，避免落点/形态返工。

## 5. Gate 与验证

```bash
cd software-distribution-platform-console
pnpm install                      # 若需
vue-tsc --noEmit                  # 类型 0 错
pnpm test:runcenter               # 14/14 通过（既有契约测试）
node scripts/runcenter-url-smoke.mjs   # URL 契约冒烟
```

新增 UI 冒烟（手动或脚本化）：
1. 运行中心「流水线」视图 → 数据来自 `GET /pipelines`（非 service-tree 遍历）；
2. 点击 `release`/`custom` 流水线 → 能进编辑器编排（无「仅 build」拦截）；
3. 行内删除 → `DELETE /pipelines/:id` 成功，列表更新；
4. （B 定稿后）新建流水线 → `POST /pipelines` 成功，出现在列表。

## 6. 风险与开放问题

- **B 节依赖 v3 IA 落点**：在定稿前强行实现会返工，故本计划将 B 单列 hold。
- **releases 视图筛选**：全局 `GET /releases` 端点**已实现**（hub `internal/run/handler/release.go`），但当前仅支持 `pipelineRunId` 参数；`scope=global&state=paused` 形态的筛选后端未支持（`paused` 属 Rollout 任务级状态，见 CONSOLE-UI-DESIGN §7.6 / 附 A N-3，已登记 STATUS §2 #14）。releases 视图暂保持现状；不属 P0-3 范围。
- **分页一致性**：A 节将 pipelines 视图改为服务端分页，需确保 `RunCenterQuery`（`constants/runCenter.ts`）的 `page` 已贯穿（当前已支持）。
- **stopgap 不能全删**：`byPipelineId` 供 releases 视图按 kind 过滤运行，仅瘦身为单次 `GET /pipelines`，不整文件删除。
