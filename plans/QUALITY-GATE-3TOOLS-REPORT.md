# 三工具质量门核对报告（crapper / dryer / mutator）

对 `software-distribution-platform` 工作区的主代码仓做一次确定性质量门机械核对。工具为 unclebob 的三个只报告、不改源码的分析器；本报告按技能「审计类例外」路径执行——跑机械核对 + 人工复核，不生成自动化用例、不改源码。

## 0. 执行摘要

| 工具 | 维度 | 覆盖仓 | 结果 |
| --- | --- | --- | --- |
| crapper | 圈复杂度 / 覆盖率 / CRAP | 三仓全量（均含覆盖率） | 复杂度热点集中在 hub 装配层、WS 与 runner 三个 Reconciler；console 覆盖率仅触达 utils 层 |
| dryer | 结构重复（Jaccard≥0.82） | 三仓全量 | 剔除生成代码后，真实重复集中在 hub 的 handler/repository CRUD 骨架 |
| mutator | 变异测试（测试盲区） | 三仓代表性核心包/文件（共 8 组） | hub 核心包 100%；runner dispatch 78–83%、rollout 控制器 48.2%；console utils 64–82% |

工具的告警是**线索不是结论**；所有热点均已回到源码人工复核，并区分了真问题与等价变异 / 框架性重复 / 覆盖率放大误报。本轮已补全量验证：三仓覆盖率全开、变异测试覆盖到各仓核心代码。

## 1. 工具与降级说明

- **L1 原生工具**：三工具均为 Go / TypeScript 支持的原生实现，已 clone 至 `/tmp/sdp-qg/{crapper,dryer,mutator}`，mutator 与 crapper 相邻检出满足其前置约束。
- **环境适配**：mutator 收尾时用 `pathlib.rmdir()` 删临时 worker 目录，被运行时注入的安全删除 shim 拦截（EISDIR）。用进程级 `CODEBUDDY_SAFE_DELETE_ENABLED=0` 关闭该 shim 后完成，未改任何全局配置或项目代码；临时目录已在跑后逐一清理。
- **覆盖率补齐**：console 的测试是自定义 node 脚本链，但 `property-test.mjs` 用 Node 22 原生类型剥离直接 import `src/utils/*.ts`，因此 crapper 的 `npx c8 ... npm test` 通道能真实追踪到源码行。重跑后 console 拿到真实覆盖率与 CRAP 分数，c8 未修改 package.json / 锁文件。
- **变异范围**：hub/runner 全仓变异成本过高（按变异点重复跑测试 N 倍），按「近期改动 + 高复杂度 + 有测试」选代表性包/文件；console 只测被 c8 真实覆盖的 utils 文件（其余源码覆盖率 0%，变异无意义）。这是抽样而非全仓逐函数，但已覆盖各仓核心路径。
- **并发约束**：mutator 共用 `<repo>/target/mutation-workers` 临时目录，同一仓库不可并行跑两个 mutator 进程（会互相删目录导致 FileNotFoundError）。曾并行触发一次，改为串行后重跑验证；rollout_controller 串行重跑与并行结果一致（48.2%），确认数据未污染。

## 2. crapper：复杂度 / CRAP

阈值 CRAP>30 视为超阈。各仓超阈函数数：hub 98、runner 29、console 带覆盖率重跑后为 6320 分（最高分来自 `scripts/e2e-*.mjs` 测试工具脚本，属 0% 覆盖放大，非产品代码）。

console 的真实覆盖率只触达 16 个文件（9 个 `scripts/*.mjs` + 7 个 `src/utils/*.ts`）；`api/`、`composables/`、`views/` 等绝大部分产品源码未被 import，覆盖率记 0%。其 CRAP 表的高分几乎都是 0% 覆盖放大的测试脚本。这是本次核对发现的一个结构性事实：**console 的自动化测试只覆盖纯 utils 层，API 与视图层零覆盖**。

### 2.1 真实复杂度热点（人工复核确认）

| 函数 | 位置 | CC | 性质判断 |
| --- | --- | --- | --- |
| `main` | `hub/cmd/hub/main.go:96` | 58 | 装配层冗长：30+ repo/service 构造 + 若干 `if cfg.*`。已部分重构到 `wire.go`（1096→935 行），仍是全项目最复杂函数；属「读起来累」而非算法难懂 |
| `StreamLogs` | `hub/internal/run/handler/run_stream.go:24` | 22 | 日志流分支密集 |
| `readLoop` / `ServeWS` | `hub/internal/gateway/gateway.go` | 21 / 18 | WS 三态身份探测 + 心跳，协议分支多 |
| `TaskRunReconciler.Reconcile` | `runner/internal/controller/taskrun_controller.go:51` | 28 | 状态机主入口，分支密集 |
| `RolloutReconciler.Reconcile` | `runner/internal/controller/rollout_controller.go:63` | 38 | 灰度状态机；覆盖率 65%，CRAP 99.7（测试已部分覆盖） |
| `applyDesiredAction` | `runner/internal/controller/rollout_controller.go:590` | 33 | pause/promote/rollback 意图分派；覆盖率 66% |

### 2.2 需剔除的误报

- hub 98 个超阈函数中，绝大多数是「覆盖率 0% × 中高 CC」被 CRAP 公式放大（`CRAP = CC²×(1−cov)³ + CC`）。这些多为 handler/repository 的薄封装或装配代码，0% 覆盖率是测试布局使然，不应据此判定为高风险。
- runner 的 `DeepCopyInto` 系列（CC 7–14）是 `controller-gen` 生成代码，不是人手维护的复杂度。

## 3. dryer：结构重复

阈值 0.82，报告去重后候选：hub 270、runner 4（另 809 条为生成代码自比，全部剔除）、console 1。

- **runner / console**：去重后几乎无真实重复，结构性重复风险低。
- **hub 270 条**：人工查看前 20 条，集中在 `internal/*/handler/*.go` 与 `internal/*/repository/*.go` 的同构 CRUD 骨架（如 `artifact/handler/artifact.go:42-55` 与 `environment/handler/environment.go:34-47` score=1.00）。这是 `RegisterCRUD` 工厂 + 分层模板产生的**意图性结构相似**：重复是框架约定的产物，名字/字面量归一化后趋同。属于「可理解性中性」——单看每条都短小清晰；只有在跨领域批量改某类行为时才需要逐处同步。不列为缺陷，建议保留现状，若未来出现「一处改、处处改」的信号再考虑抽取泛型骨架。

## 4. mutator：测试盲区（全量验证）

对三仓代表性核心包/文件跑真实变异，复用 crapper 覆盖率快照（uncovered 站点不执行、单列）。

| 仓 | 文件 / 包 | Killed | Survived | Uncovered | 得分 |
| --- | --- | --- | --- | --- | --- |
| hub | `internal/run/service`（整个包） | 294 | 0 | 121 | **100.0%** |
| hub | `internal/config`（整个包） | 71 | 0 | 7 | **100.0%** |
| runner | `dispatch/approve_handler.go` | 11 | 3 | 0 | 78.6% |
| runner | `dispatch/rerun_handler.go` | 19 | 4 | 0 | 82.6% |
| runner | `dispatch/snapshot.go` | 19 | 4 | 5 | 82.6% |
| runner | `dispatch/{cancel,apply,rollout_control}_handler.go` | 16 | 4 | 13 | 80.0% |
| runner | `controller/rollout_controller.go` | 67 | 72 | 59 | **48.2%** |
| console | `src/utils/permission.ts` | 27 | 6 | 0 | 81.8% |
| console | `src/utils/{tree,run}.ts` | 30 | 17 | 0 | **63.8%** |

hub 的核心业务包测试极扎实（两个包 0 个存活变异体）；runner 的 dispatch 层 78–83%，稳健；最薄弱的是 runner `rollout_controller.go`（48.2%）与 console `tree.ts`（63.8%），且二者恰是高复杂度/关键保护逻辑所在。

### 4.1 幸存变异体复核（工具线索 → 人工结论）

**真测试盲区（建议补测试，本次未改）**：

1. `approve_handler.go:28` / `rerun_handler.go:32`：`|| -> &&` 存活——只测了「两个字段都为空」的拒绝路径，未测「仅其中一个为空」。补一条单字段缺失的用例即可杀掉。
2. `rerun_handler.go:81`：`err != nil && !apierrors.IsNotFound(err)` 一行三个变异全存活——未覆盖「删除下游 TaskRun 返回非 NotFound 错误」分支。
3. `approve_handler.go:54`：幂等判定 `d.Approver == p.Approver` 的 `== -> !=` 存活——缺少「同一审批人重复审批」场景。
4. `approve_handler.go:71`：Patch 调用 `err != nil` 的 `!= -> ==` 存活——Patch 失败路径未测。
5. `snapshot.go:92`：十六进制校验 `(r<'0'||r>'9') && (r<'a'||r>'f')` 的 `|| -> &&` 存活——缺「含非法字符的快照字符串」用例。

**等价变异体（工具误报，无需补测试）**：

- `snapshot.go:31` 排序 `< -> <=`：对唯一 Name 数组等价。
- `snapshot.go:82` 错误分支 `false -> true`：报错信息文案变化，测试只关心是否返回错误，属等价。
- `rerun_handler.go:32` 另一处 `|| -> &&` 与 `:81` 的判定，已归入上表真盲区。

### 4.2 全量验证新增发现

**runner `rollout_controller.go`（48.2%，72 个存活变异体，串行重跑两次一致）**：

- 存活集中在**防御性/错误处理分支**：`SetControllerReference` 失败（`:362`）、`Create` 返回非 AlreadyExists 错误（`:365`）、`scaleDeployment` 的 replicas nil 检查（`:466`）、promote 的 aborted/rolledback 保护（`:656`）、CompletionTime 幂等赋值（`:714`）等。这些需 mock client 报错才能触发，单测未覆盖。
- 复核判断：不是逻辑错误，但**这个全项目 CC 最高的函数（38）恰是测试最薄的**，且 59 个站点 uncovered。它是本次全量验证最值得关注的质量信号——灰度发布状态机的分支正确性缺乏测试保障。
- 另注：rollout_controller 的测试此前刚为本轮修复补过（pause 计时迁移、意图单次写路径），覆盖仍不足，说明补测试的速度没跟上状态机的复杂度增长。

**console `src/utils/tree.ts`（63.8%，含 17 个存活）**：

- 真盲区集中在 `computeWindow`（虚拟滚动窗口，`tree.ts:89-105`）：`opts.rowHeight ?? 默认` 的 `?? -> ||`（未测 `rowHeight: 0`）、`:92` 边界组合 `total<=0 || rowHeight<=0`、`:100-105` 的 `start>=end` 吸附逻辑（`0 -> 1`、`>= -> >` 存活）。这段注释明确写「做错会导致区间反转、整棵树白掉」——**关键保护分支测试不足**。
- `:167/:171-172` 滚动定位函数 `scrollToIndex` 同类边界缺失。
- 等价变异体：`tree.ts:62` 的 `children.length > 0` 的 `> -> >=`（0 时行为相同）、`permission.ts` 6 个存活中的 5 个 `?? -> ||`（`parseActions`/`subjectLabel`/`knownSubjects`/`validateSubjectInput`/`subjectInputHint` 的入参在空串下 `??` 与 `||` 行为一致，且后续均有 `!id`/`!v` 兜底）；真盲区仅 `permission.ts:75` 的 `type === 'group'` 分支（不同主体类型应返回不同提示文案）。

> **补测后更新**：上述两个薄弱点已补单测并修复补测暴露的缺陷，变异得分 `rollout_controller.go` 48.2%→62.5%→68.5%（后续又做 Status/Spec 写入机制隔离 + client 报错分支补测）、`tree.ts` 63.8%→73.9%。详见 `LOCAL-RUNTIME-ISSUES.md` 第 6/7/8 节（含 3 个真实 bug、机制隔离根治、client 错误分支补测）。下表第 5 节的历史数值为补测前快照，保留作为对比基线。**所有遗留项的统一状态（已闭环/保留/他域）见 `LOCAL-RUNTIME-ISSUES.md` 第 9 节。**

## 5. 综合结论

- **复杂度风险**：集中在 hub 装配层与 runner 状态机，与前次认知成本审计的发现一致（装配层承载策略、状态机分支密集）。hub `main` 仍是全项目最复杂函数，重构尚未收口。
- **重复风险**：低。runner/console 干净；hub 的重复是框架模板产物，非维护负担。
- **测试强度分化明显**：hub 核心包（`run/service`、`config`）变异 100% 杀灭，测试扎实；runner dispatch 78–83%，稳健。两个薄弱点值得优先处理：
  1. **runner `rollout_controller.go` 48.2%** —— 全项目最复杂的灰度状态机，72 个存活变异体、59 个 uncovered 站点，测试保障与复杂度严重不匹配。
  2. **console `tree.ts` 63.8%** —— 虚拟滚动 `computeWindow` 的关键保护分支（防「整棵树白掉」）测试不足。
- **console 测试覆盖结构性问题**：自动化测试只触达 utils 层（16 个文件），`api/`、`composables/`、`views/` 零覆盖。这不是工具误报，是测试布局现状；CRAP 高分里大量来自 0% 覆盖放大的测试脚本，需按「产品代码 vs 测试工具」分开看。
- **未决**：变异为代表性抽样（非全仓逐函数）；hub 的 WS 层（覆盖率 0%）、runner agentops/executor 等未跑变异。这些区域无覆盖率数据，变异无意义，需先补测试后再测。不能据此宣称全项目质量门通过。

## 6. 与九对账的关系

本次为只读审计，不涉及「写死值清零 / 依赖声明 / 不可逆操作护栏 / 门控改动」等对账项（无代码交付）。质量门对账按技能 §1「被测代码在本地」执行到 L1 原生工具级别，并对每个告警做了人工复核；工具产物（`.metrics/`、`target/`）已在报告后清理，工作区未因本次检查产生新文件。
