# Console UI 验证结构缺口 — Gap 跟踪

> 关联：[console-ui-verification-testcases.md](console-ui-verification-testcases.md)（38 条用例计划）、[STATUS.md](STATUS.md)（进度权威）、`console/scripts/criteria.mjs`（判据契约 SSOT）、`console/scripts/seed-fixtures.mjs`（可复用造数）。
> 适用范围：`software-distribution-platform-console` + hub 数据模型。
>
> **状态**：2026-11-21 在 kind 集群以真实认证 + 契约关卡逐条执行。凡「前端无 DOM / 无任务类型 / DB 无字段」的用例属**产品结构缺口**，不能靠造数补齐，也不写成测试通过——集中登记于此，转产品待办。测试侧已用 `suite.skip` 显式标注并附缺口编号，不虚报进度。

## 1. 结论（一句话）

16 条原「未展开」用例中，**可造数/可真验的 12 条已展开并通过**（B07/B09/B10/B11、S06/S07/S09、F06 等）；另有 **8 条涉及产品结构缺口**（B08 三卡、S06 禁用策略、S09 错误重连态、S10 形状、F03~F05 四类流水线、B03 多层树、P02 org_admin、V01/V03/V05 人工步骤），需产品/工程侧实现或人审后才有完整验证对象。

> 口径说明：上面两组编号**存在交集**（如 S06、S09 既已部分展开、又仍有结构缺口），是「展开进度」与「缺口类型」两个维度的交叉标注，非互斥分类，不可按 12+8 相加。用例总数以 `console-ui-verification-testcases.md` 的 38 条为准。

## 2. 缺口清单（结构缺失，非测试问题）

| 编号 | 优先级 | 位置 | 缺口（前端/后端现状） | 用例影响 | 建议修复 |
|---|---|---|---|---|---|
| G1 | P1 | `DashboardView.vue:95-138` | 总览只有 KPI 四卡 + 最近运行表，**无「待我审批/失败/暂停」三张待办卡 DOM**；「待我审批」语义退化为运行中心 `phase=WaitingApproval`（assignee=me 未落地），「暂停」筛选项被刻意删除 | B08 无验证对象，SKIP | 按 ui-05 总览卡契约补三卡 DOM + 深链筛选；先落地 `assignee=me` 与 paused 聚合 |
| G2 | P2 | `MainLayout.vue` / `AuditTab.vue` / `api/http.ts` | 403 三策略只有「隐藏」（角色守卫）与「可点后拦截」（全局跳页 + AuditTab 锁态）；**无「禁用+tooltip 所需权限」的权限态 disabled**（现有 disabled 全是业务态） | S06 第三条策略缺验证对象，契约按已实现两策略判定 | 抽通用 `v-permission` 指令，无权限按钮 disabled + title 标所需 action |
| G3 | P2 | `RunMonitorView.vue:94-98` / `LogsTab.vue:55-59` | 日志区 `catch` 静默置空，**无错误重试态 DOM、无断线重连态**；全局无 skeleton 骨架 DOM | S09 只能验面板+空态，错误/重连缺对象 | 日志区加 error/refetch 状态与重连 UI；补骨架组件 |
| G4 | P2 | `StatusBadge.vue:8-29` / `tokens.css:185-196` | 五态统一「圆点 + 文字」，**五种状态无五种形状**（旋转/空盒/警告三角/对勾/锁），灰阶下仅靠颜色+文字区分 | S10 形状可辨无法机器判定，SKIP | 五态各给独立 SVG shape/图标，形状语义不依赖颜色 |
| G5 | P1 | `utils/pipeline.ts:18,49-53` / `PipelineEditorView.vue` | 任务类型仅 `Build/Release/Approval`（**无 Test**），四类流水线无专用编排入口；`kind` 仅分类标签不过滤编排内容 | F03 版本归档、F04 转测、F05 生产无验证对象，SKIP | 按 ui-04 四类流水线补任务类型与编排模板（归档/转测/审批门禁/多环境） |
| G6 | P3 | hub DB `services`/`service_trees`（无 `parent_id`） | 服务树层级仅 org→tree→services 两层平铺，**无父子树节点** | B03 多层懒加载/虚拟滚动无数据基础，标 known-gap | 若产品需要多层树，DB 加 `parent_id` + 递归查询 + 前端按层懒加载 |
| G7 | P2 | `cmd/hub/auth_setup.go:48-62` / `session/model.go` | cookie session 只回填 `Subject/Username/Groups`，**不回填 OrgAdmins**（仅 Bearer token 路径带 `org_admin` claim）；本地 KC 写 `org_admin` attribute 后 password grant 回落 `UPDATE_PASSWORD` | P02 组织管理员视角无法用 cookie 会话建立，标 known-gap | session 表加 org_admins 列并在 auth_setup 回填；或 E2E 改用 Bearer token 路径 |
| G8 | P2 | `evidence/baseline/manifest.json` / `REVIEW.md:20` / `ci.yml` | 基线 `confirmedBy=null`（人审未做）；漂移 reviewer 须人签；`commitBinding` 仅文字声明，**CI 无机器校验、`review_required_paths` 未含 `evidence/baseline/**`** | V01/V03/V05 标 known-gap | 人工确认基线首版；CI 加 protected_paths 校验 step；review_required_paths 纳入 baseline |

## 3. 修复顺序建议

1. **G1 / G5（P1）**：总览待办卡与四类流水线是 ui-04/ui-05 明列的验收对象，缺则 L4 业务链路 DoD 不达标。
2. **G7（P2，阻塞 P02）**：session 回填 org_admins 后组织管理员视角可测，且是真实运行时问题（cookie 会话用户拿不到组织权限）。
3. **G2 / G3 / G4（P2）**：权限策略、错误态、可辨图标是五态规范硬要求。
4. **G6 / G8（P3）**：多层树属产品增强；治理人审由工程流程补齐。

## 4. 验收 gate

每项修复后在 `console/scripts/criteria.mjs` 恢复对应契约的完整正向判据（移除 `knownGap` 标注与 SKIP），跑 `node scripts/seed-fixtures.mjs` + 对应套件，契约 PASS 且两轮全量压测 `failed=0` 方可勾闭环。
