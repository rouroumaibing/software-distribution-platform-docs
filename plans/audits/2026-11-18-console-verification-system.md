# 审计报告：console 仓库验证体系体检

- 审计对象：`software-distribution-platform-console`（main@cc144ef；工作区有未提交改动：`.github/workflows/ci.yml`、`package.json` 修改，`verify.yaml`、`REVIEW.md`、`governance/`、`scripts/lint.mjs`、`scripts/property-test.mjs` 等资产待提交）
- 审计日期：2026-11-18
- 审计模式：**建议模式**——仓库有 `governance/redlines.yaml`（起步最小集：阈值/保护路径/风险模式，非权威策略），无契约、`required_rules` 未设，门禁未 enforce。按采纳边界，本报告为**建议清单，非合规判定**；治理骨架不构成违规。
- 审计类型：验证体系 survey（`verification_gate_check.py --survey`）+ 四道 gate 本地实测 + 文档一致性 + flaky 实跑（`static_risk_check.py`）+ 属性测试实跑 + 人工核对
- 独立性声明：**非独立验证**——同一会话内由执行审查的 Agent 兼任，未经干净会话独立复核；高风险结论须人精读原始证据。
- 证据口径：结论均附命令输出 / 文件路径 / 字段值。survey 为形态探测，miss 不构成违规。机器推算仅供参考，关键断言须人核原文。
- 覆盖规范：按 harness-workflow `verification-program.md` §6，覆盖表逐条处置 §0/§1/§3/§4 全节（含 §4.10 前端视觉规格）与 VP-01~07，每条「已建议」去向可核，并列子项拆行；§0 证据措辞与实证数字（+10 分/最难任务收益最大）、§3 能力+平台适配器分离口径（agent 无关的本地强制点 + 各 agent 完成时事件作可选加速器）、§4.5 拦截谓词、§4.8 实证评分口径（golden set 一句话答案/只有正确描述该 bug 才得分）等"机检管不到"的语义项按蓝图原文人工核；报告落盘前经 `report_gate.sh` 单一入口机检（一次跑完 `coverage_table_check.py` + `stage_consistency_check.py` 并聚合退出码）。

---

## 一、结论摘要

console 仓库的验证地基比一般前端项目扎实：CI 有 lint + typecheck（vue-tsc）+ test（8 套件契约冒烟 + 属性测试）+ build 四步、frozen lockfile、并发控制与最小权限，本地实测四道 gate 全 rc=0；8 个契约冒烟套件合计 187 条断言（22+26+71+22+21+14+5+6）全过，`scripts/property-test.mjs` 实跑 12018 checks PASS，无 skip/空断言凑绿；文档一致性 PASS；`static_risk_check.py` 对测试路径全量实跑 PASS（0 处 sleep/rerun/skip/flaky 信号）。这些都是真实可复查的优点。

但按 D1~D12 诊断，体系整体处于**建设早期**——D1 静态门、D2 冒烟、D4 verify 资产、D11 flaky 治理已有骨架，D3 属性测试已实跑；而证据协议（D7）仍缺失，验证戳（D8）、判卷独立性（D9）、升级策略（D10）只有配置/清单骨架、无提交期与判卷实装，漏检回流（D12）缺失，前端视觉判据（D4b）缺失；按 §3 阶段归属表：P0 阶段（D1/D7/D10）D1 达标、D10 部分、D7 缺失，P1 阶段（D4/D8/D9）D4/D8/D9 均部分，P2 阶段（D3/D5/D11/D12）D3 部分、D11 达标、D5 当前不适用、D12 缺失。console 作为 Vue3 前端交互仓库，还有三处特有发现：

1. **verify 的 done 停在静态门**——`verify.yaml` 三字段齐，done 指向 typecheck/test/build 的日志与静态文本断言（S12/S6），能守住"契约字符串没被改坏"，但不证明真实系统行为工作（D4 行为维只部分达标，难欺骗性弱于真 E2E）。
2. **无前端视觉验证与异常态驱动**（§4.10）——仓库无 playwright/puppeteer/截图基线依赖，无截图比对、无异常流程（网络失败/空数据/超时/权限/弹窗抽屉各态）的可判卷覆盖。界面回归目前完全依赖上述静态文本断言，agent 没有"手和眼"。
3. **治理骨架已落、通电不足**——`governance/redlines.yaml` 有验证戳覆盖率与连续失败阈值、`REVIEW.md` 列七条判卷条目与五条独立性机制（S12），但 31 个 commit 中 0 个带验证戳（S3）、无提交期盖章/hook、无门禁拦截谓词；`governance/golden-set.md` 存在但无持续度量与分阶段 recall 实装。

**没有发现任何阻断级违规或升级触发**（无 diff、无契约、无高风险变更在放行），不出具合规失败判定；以下全部为修改建议。蓝图覆盖处置见第七节。

---

## 二、证据总表（D1~D12 逐维核对）

| 维度 | 判定 | 证据 |
| --- | --- | --- |
| D1 静态门 | ✅ 达标 | CI `.github/workflows/ci.yml` 有 lint/typecheck/test/build 四步（S2）；本地四道 gate 实测均 rc=0（S4） |
| D2 单元测试 | ⚠️ 部分 | 8 个 smoke 套件共 187 条断言全过（S5）；但均为源码/配置文本断言，非行为级单测；无正式单测框架（无 vitest/jest） |
| D3 属性测试 | ⚠️ 部分 | `scripts/property-test.mjs` 实跑 PASS（600 rounds × 5 groups + phase invariants，12018 checks，S11），四模式均有用例；survey `test_types.property.dep=[]`（自研生成器），属性陈述未人审固化 |
| D4 E2E / verify 资产 | ⚠️ 部分 | survey `verify_asset=['verify.yaml']`（S3）；三字段齐、done 指向 typecheck/test/build 日志（S12）；8 套件契约冒烟为静态文本断言（S6），无真跑完整用户流的 done 判据 |
| D4b 前端视觉判据 | ❌ 缺失 | 无 playwright/puppeteer/截图基线依赖与资产（S8）；无截图比对、无异常态驱动清单。console 有前端交互，本节适用 |
| D5 差分测试 | ⛔ 当前不适用 | 无"可并行运行的旧实现"（见 S7），非缺口 |
| D6 CI 边界 | ✅ 基本达标 | L0 验证层（ci.yml）/ L1 发布层（release.yml）分离，frozen lockfile + concurrency + permissions 收窄；lint/typecheck/test/build 顺序执行；缺 coverage/mutation 门 |
| D7 证据协议 | ❌ 缺失 | 无 `Verified:`/`Evidence:` trailer 约定（git 全历史 `Verified:` 计数=0，S3）；无证据落点规范；截图未作为一等证据类型 |
| D8 验证戳 | ⚠️ 部分 | `governance/redlines.yaml` 有 `thresholds.verification_stamp`（lookback=50, min_ratio=0.8）骨架（S12）；survey `stamped=0, total=31, ratio=0.0`（S3），无提交期盖章/hook 实装 |
| D9 判卷独立性 | ⚠️ 部分 | `REVIEW.md` 列七条判卷条目与五条独立性机制（S12）；无服务端从 base 分支取规则、评审绑 commit 作废的实装，清单未列入 `protected_paths` 强制 |
| D10 升级策略 | ⚠️ 部分 | `governance/redlines.yaml` 有 `max_consecutive_gate_failures: 3` 阈值（S12）；无 harness 连续失败计数与转人实装 |
| D11 flaky 治理 | ✅ 基本达标 | `static_risk_check.py` 对 8 个测试路径全量实跑 PASS（S10）：0 处 sleep/rerun/skip/flaky 信号；S5 粗扫无 skip/空断言 |
| D12 漏检回流 | ❌ 缺失 | 无漏检→规则准入门槛的执行记录、无判卷清单修剪与持续度量；`governance/golden-set.md` 存在但无分阶段 recall / 发现分级实装 |

---

## 三、关键证据（可复查）

**S1 — 工作区与身份**：`git status --short --branch` = `## main...origin/main`；HEAD `cc144ef`。工作区有未提交改动：`M .github/workflows/ci.yml`、`M package.json`、`?? verify.yaml`、`?? REVIEW.md`、`?? governance/`、`?? scripts/lint.mjs`、`?? scripts/property-test.mjs`（仓库现状，本报告未改动）。

**S2 — CI 与依赖门禁**：`.github/workflows/ci.yml` = checkout → pnpm/action-setup → setup-node@22 → `pnpm install --frozen-lockfile` → `pnpm lint` → `pnpm typecheck` → `pnpm test` → `pnpm build`；`release.yml` 为 L1 发布层（release published / workflow_dispatch dry-run）。survey `ci.step_keywords={".github/workflows":["test","build","lint"]}`。`package.json` 有 `lint: node scripts/lint.mjs`（仓库内脚本，devDeps 无 eslint/oxlint/biome），`test` 脚本串联 8 个 smoke 套件 + `test:property`。CI 未定义任何"会话内验证动作"的拦截谓词（S2 全扫），提交不被"是否已跑验证"拦。

**S3 — survey 摘要**：`verify_asset=['verify.yaml']`；`ci.step_keywords` 见 S2；`test_types.e2e/differential` 全空、`test_types.property.dep=[]`（`dep_manifests_read=package.json`）；`verification_stamp={lookback:50, stamped:0, total:31, ratio=0.0}`。git 全历史 `Verified:` 计数=0。

**S4 — 四道 gate 本地实测**：`pnpm install --frozen-lockfile` rc=0（依赖 116 resolved）；`pnpm lint` rc=0（`lint: PASS (103 files)`）；`pnpm typecheck` rc=0；`pnpm test` rc=0；`pnpm build` rc=0（output/dist 产物，2.08s）。node v22.22.2 / pnpm 11.10.0。构建产物与 node_modules 均被 `.gitignore` 忽略，工作区改动仅限 S1 所列资产。

**S5 — 8 套件断言分布**：`22/22 passed`（runcenter-url）、`26/26`（theme-search）、`71/71`（pipeline-editor）、`22/22`（service-tree）、`平台权限 UI 纯逻辑冒烟 21/21`、`接入目标操作台账 14/14`、`运行控制相位策略 5/5`、`target-smoke 6/6`。合计 187 条断言。`.skip(`/`assert.true(true)` 粗扫命中 0。

**S6 — smoke 性质判定**：脚本典型断言形态 `assert.equal(c.envFile.includes('SDP_HUB_BASE_URL=https://www.sdpworkflow.com:8443'), true)`（`scripts/target-smoke.mjs:38`）、`assert.equal(c.caScript.includes(...)...)`——校验源码/配置**文本**而非启动系统。依赖列表无 playwright/puppeteer/chromium。→ 属轻量契约冒烟，非真 E2E。

**S7 — 差分测试适用前提核查**：`git ls-files | grep -iE 'migrat|legacy|old|v1|rewrite|compat|dual'` 空；`src/api/approval.ts` 是业务审批 API（非 approval testing）；auth 演进（BFF model / force password-change）为替换式、无旧实现双跑；无 golden/snapshot/approval 测试特征。→ **无可并行旧实现**，§4.9 当前不适用。

**S8 — 前端视觉验证资产核查**：`package.json` + `pnpm-lock.yaml` grep `playwright|puppeteer|vitest|screenshot|pixel|sharp|image-diff|chromatic` 无命中；`git ls-files` grep `baseline|screenshot|visual|golden|\.spec\.|cypress|e2e` 无命中。异常态关键词在 4 个 smoke 脚本有命中，但为业务状态文本（如 isTerminalStatus/权限位），非 UI 异常流程驱动清单。→ **console 有前端交互，§4.10 适用且缺失**，非"当前不适用"。

**S9 — 注释与文档一致性**：`ci.yml` 顶部注释声明"全量契约冒烟 8 套件"，与 `package.json` `test` 脚本链接的 8 个 `smoke.mjs` 一致；注释不再引用不存在的文档路径。`doc_consistency_check.py --root .` = PASS（工具扫 markdown 链接，不扫代码注释内的路径引用与数量声明——这类声明目前靠人核）。

**S10 — flaky 信号实跑（`static_risk_check.py`）**：以 8 个测试路径的全量行作为新增行构造 diff 实跑，结果 `static_risk_check: PASS (no skip marks / empty catches / empty asserts in added lines; all listed changes attributed)`，rc=0，0 处 sleep/rerun/skip/flaky 信号。D11 判定据此次实跑，非相邻粗扫顶替。

**S11 — 属性测试实跑**：`node scripts/property-test.mjs` → `property-test: PASS (600 rounds × 5 groups + phase invariants, 12018 checks)`，rc=0。脚本覆盖 §4.4 四模式：不变量（computeWindow 窗口 / 相位互斥）、幂等（parseActions / knownSubjects 二次归一）、round-trip（ensureVisible / formatExpiryISO）、等价（flattenVisible 索引连续 / shouldVirtualize 阈值边界）。`pnpm test:property` 与 `pnpm test` 均串联该脚本，CI test step 覆盖。

**S12 — 治理骨架现状**：`verify.yaml`：`build: pnpm build`、`start: pnpm dev --host 127.0.0.1`、`done` 三条命令（typecheck/test/build）各带 `evidence/*.log` 落点；`hands.driver` 声明界面态浏览器驱动待接、`feature_map` 指向 8 套件。`governance/redlines.yaml`：`thresholds.verification_stamp`（lookback 50 / min_ratio 0.8）、`max_consecutive_gate_failures: 3`、`protected_paths`（governance/**、.github/workflows/**）、`review_required_paths`（permission.ts / credential.ts）。`REVIEW.md`：七条判卷条目 + 五条独立性机制。`governance/golden-set.md` 存在。以上为骨架，无提交期盖章/hook/转人实装。

---

## 四、修改建议（按 §3 阶段归属排序）

> 每条建议标题的阶段与其【缺口】行 D 维度的权威阶段一致（P0：D1/D7/D10；P1：D4/D8/D9；P2：D3/D5/D11/D12）。跨阶段维度拆为独立建议——D7 证据协议属 P0，单列为建议 3；建议 6 验证戳只覆盖 D8（P1）。机器推算仅供参考。

### 建议 1（P0）守住 lint 门并接服务端 required check
- 【缺口】D1 有 lint/typecheck/test/build 四步（S2/S4），但 lint 为仓库内 `scripts/lint.mjs`，且无服务端 required check 钉死来源。
- 【证据】S2、S4。
- 【建议改动】保留 `lint` script 与 CI 必需 step；从组织级 required check 钉死来源，防 PR 内删 step；lint 规则深度由工程按需扩展。
- 【对抗推演】AI 同 PR 改 workflow 删 step（RT-02/RT-17）→ `.github/` 列入 `review_required_paths` + CODEOWNERS，从目标分支取门禁。
- 【建议可信度】已验证模式（RT-02、D1 判据）。
- 【由谁决策】工程（CI 负责人）；workflow 改动须人审批。
- 【严重度】中。

### 建议 2（P0）落实连续失败转人阈值（E-05）
- 【缺口】D10 部分：`governance/redlines.yaml` 有 `max_consecutive_gate_failures: 3`（S12），但无 harness 连续失败计数与转人实装。
- 【证据】S12；D 表 D10 行。
- 【建议改动】以 redlines 的阈值 3 为准，由 harness 记录同一门禁连续失败次数，≤3 轮修不好即停止重试、转人；与 flaky 治理（建议 10）联动，超时/失败不靠重跑碰运气。
- 【对抗推演】AI 反复重跑门直到偶发绿（RT-16）→ 连续失败计数由 harness 记录、达阈值强制转人，不给 agent 自行清零的入口。
- 【建议可信度】已验证模式（D10/E-05）。
- 【由谁决策】契约负责人（阈值）+ 工程。
- 【严重度】中。

### 建议 3（P0）建立证据协议（结论附退出码/日志）
- 【缺口】D7 缺失：无证据落点规范，验证结论可自述、无外部可复查证据。
- 【证据】S3（git 全历史 `Verified:` 计数=0）；D 表 D7 行。
- 【建议改动】定义证据协议：每条验证结论附退出码 / 日志路径 / 截图路径，由 harness 收集、**agent 只能引用不能转述**（§0 核心措辞）；"本地先跑"是 **agent 无关的能力**——改动交给下游前自动跑便宜门（test/build/lint）并留痕，与 agent 种类无关；通用落点是 git `pre-commit` hook；各 agent 生态的完成时事件（如 Claude 的 Stop hook / `/goal` 绑定 passing test suite）只是**可选加速器示例，不作能力判据**。证据包格式对齐 `schemas.md` 的证据类型。验证戳落地见建议 6。此建议的价值有 §0 实证支撑：独立 grader 按 rubric 判卷使任务成功率最高 **+10 分、最难任务收益最大**——判卷人与做题人分离是最便宜的提分手段，而该收益的前提正是结论有外部可复查证据、不靠自述。
- 【对抗推演】AI 转述"测试通过"而无日志（RT-05）→ 结论必须指向可复查的证据路径，缺证据按未通过处理。
- 【建议可信度】已验证模式（D7/§0 证据协议与 +10 分实证）。
- 【由谁决策】契约负责人 + 工程。
- 【严重度】中。

### 建议 4（P1）把 verify 的 done 推进到真跑用户流
- 【缺口】D4 部分：`verify.yaml` 三字段齐、done 指向 typecheck/test/build 日志（S12），但无真跑完整用户流的 done 判据。
- 【证据】S3 `verify_asset=['verify.yaml']` + S6 + S12。
- 【建议改动】按蓝图 §4.1 把 `verify.yaml` 的 done 从静态门日志推进到真实可观测状态（真实登录流 / API 健康检查 + 证据落点）；`hands.driver` 现声明 `scripts/*.mjs` 契约冒烟、界面态浏览器驱动待接，按建议 5 接入；done 判据可用验收场景清单当 rubric（feature map）。**harness 自身须压测到稳定**（VP-01）。
- 【对抗推演】AI 写永远 exit 0 的 done 凑绿（RT-05）→ done 指向真实系统可观测状态（HTTP 200 + 关键字段），超时 = fail 不重试。
- 【建议可信度】已验证模式（D4/VP-01/§4.1）。
- 【由谁决策】工程 + 契约负责人（done 判据须人确认）。
- 【严重度】中。

### 建议 5（P1）建立前端视觉验证与异常态驱动清单（§4.10 四子项）
- 【缺口】D4b 缺失：console 有前端交互，但无截图基线、无视觉比对、无异常流程的可判卷覆盖——界面回归目前只靠静态文本断言。
- 【证据】S8 无视觉依赖与基线资产；S6 smoke 为文本断言；S12 `hands.driver` 界面态驱动待接。
- 【建议改动】按蓝图 §4.10 落四子项：①**基线管理**——引入 playwright 等生成关键页面截图基线，列 `protected_paths`，记录场景 id / 视口 / 浏览器版本 / 稳定时刻定义 / 基线 sha256，首版由人确认、不由 agent 当次截图转正；②**比对协议**——done 判据为机器可判定的 `baseline_sha256` / `actual_sha256` / `diff_metric`（像素差比例/感知阈值）+ 容差阈值（抗锯齿/字体/动效），字段名对齐 `schemas.md` §3 的 `screenshot` 类型，超阈值 = fail 不重试；漂移处置写明"代码回归→修代码 / 有意 UI 变更→人审后更新基线 + 新旧对比与理由"；③**异常态驱动清单**——feature map 显式覆盖网络失败、空数据、超时、权限不足、表单校验错误、弹窗/抽屉 open→confirm→close 各态、加载/错误/空状态切换，每场景写清怎么触发、截哪个状态点、断言什么、对应哪个基线 id（截图↔用例一一映射）；异常态的"预期报错"是 done 不是失败。④**截图一等证据**——截图按 `screenshot` 类型写入证据包（带 sha256、基线引用、场景 id、比对指标），由 harness 收集。
- 【对抗推演】AI 截图比对失败后把基线改成"当前实际渲染"或调大容差让差异合法消失（RT-18）→ 基线与容差列入 `protected_paths`（变更人审）+ 基线首版人确认 + 证据包 `screenshot` item 带 `baseline_sha256`/`diff_metric`，基线改动触发复核；漂移处置须写明修代码还是人审更新基线，禁把更新基线当修测试捷径。
- 【建议可信度】已验证模式（§4.10/RT-18/schemas §3 screenshot 类型）。
- 【由谁决策】工程 + UI owner（基线首版与容差须人确认）。
- 【严重度】中。

### 建议 6（P1）补齐验证戳（含 none）与拦截谓词，先 observe
- 【缺口】D8 部分：`governance/redlines.yaml` 有验证戳阈值骨架（S12），但 31 commit 中 0 戳（S3），无提交期盖章与门禁谓词。
- 【证据】S3 ratio=0；git 全历史 `Verified:` 计数=0；S2 全仓无会话内验证动作的拦截配置；S12。
- 【建议改动】分两套机制并用（§4.2 + §4.5）：
  - **验证戳（结果标记）**：由提交工具链按实际跑过的门自动盖 `Verified: <e2e|unit|property|differential|manual|none>`，`none` 是合法值，使未验证提交可查询；`governance/redlines.yaml` 已有 `thresholds.verification_stamp`（lookback 50 / min_ratio 0.8）；白名单外 method 按无效戳计。
  - **门禁灰度（off→observe→enforce 三档）**：按 VP-05 从 off（先确认开关无害）→ observe（只记录本会被拦的提交、不拦）→ enforce（拦截；commit 可附豁免理由；**同一会话内被拦两次后下一次放行**作逃生门）。当前档位 off（无门）。
  - **拦截谓词（门拦什么，须与三档一起定义）**：谓词拦的是**该次提交所在会话内没有执行过约定验证动作的提交**（落地时由项目定义具体命令，如把 `pnpm typecheck && pnpm test` 绑到提交完成钩子，不写死某个 slash command）；判定依据是**会话内事实**（有没有跑过该动作），不是 commit message 上的戳——戳是结果标记（含 `none`），谓词是门禁判定拦不拦的依据，两套并用。只盖戳不定义谓词，等于给了开关没接电线。
- 【对抗推演】AI 滥盖 `Verified: e2e`（RT-11）→ 戳由工具链按实际跑过的门生成、白名单外 method 按无效戳计；AI 靠改 commit message 伪造"已验证"绕过门（RT-17 同型：变更不能修改审判自己的标准）→ 谓词只看会话内是否真跑过验证动作、不受 message 戳影响，且 hook 从目标分支取。
- 【建议可信度】已验证模式（D8/R-VER-008/§4.2/§4.5 含拦截谓词）。
- 【由谁决策】工程（提交链 + hook）+ 契约负责人（阈值与谓词动作）。
- 【严重度】中。

### 建议 7（P1）补覆盖率与 mutation 门禁
- 【缺口】D2/D6 深度不足：CI 跑 test 但不度量覆盖率，无 mutation。
- 【证据】S2 无 coverage/mutation step。
- 【建议改动】用 vitest 接管现有 smoke 断言并接 `vitest run --coverage` 阈值门（cheap-first）；成熟后引入 mutation（如 StrykerJS）在提交边界跑；阈值写 redlines。现有 8 套件断言可直接迁入，成本可控。
- 【对抗推演】AI 删测试凑绿（RT-08）→ 覆盖率 + mutation 双门配合 R-IMP-003。
- 【建议可信度】已验证模式（RT-08、R-VER-001/002）。
- 【由谁决策】工程；阈值由契约负责人定。
- 【严重度】中。

### 建议 8（P1）落实 REVIEW 判卷清单的五条独立性机制
- 【缺口】D9 部分：`REVIEW.md` 列七条判卷条目与五条独立性机制（S12），但无服务端从 base 分支取规则、评审绑 commit 作废的实装。
- 【证据】S12（`REVIEW.md` 存在）；无 commit 绑定评审记录；`redlines.yaml` 的 `protected_paths` 仅含 `governance/**` 与 `.github/workflows/**`，清单未入强制。
- 【建议改动】按 §4.3 以现有 `REVIEW.md` 为清单（三要素：触发器×检查内容×事故链接），落实五子机制：①规则列入 `protected_paths`、CI 从 base 分支读；②评审绑定 commit、推新提交作废；③code owner 写检查并迭代；④拉人须说 why（触发哪条规则、什么证据）；⑤单一 reviewer、多轮累积——不堆叠第二个更贵的 reviewer，调优 REVIEW.md 本身，每轮喂前轮上下文与历史失败而非从头重查。§4.10 的基线/容差保护（建议 5）与①同型，一并纳入受保护路径。这条建议的收益同样对应 §0 的判卷独立性实证（独立 grader +10 分、最难任务收益最大）。
- 【对抗推演】AI 同 PR 改判卷规则自审自过 / 用陈旧评审给新代码背书（RT-17 覆盖①②）→ ①②服务端钉死来源 + commit 绑定；③④⑤防社会工程与"堆 reviewer 反而更贵却漏检"。
- 【建议可信度】已验证模式（VP-03/§4.3/RT-17）。
- 【由谁决策】工程 + code owner；清单入保护路径须人审批。
- 【严重度】中。

### 建议 9（P2）扩充属性测试覆盖（四模式 + spec 漂移）
- 【缺口】D3 部分：`scripts/property-test.mjs` 已实跑 12018 checks PASS（S11），但属性陈述未经人审固化、survey 无属性库依赖（自研生成器）。
- 【证据】S3 `test_types.property.dep=[]`；S11 实跑 PASS。
- 【建议改动】现有属性测试已按 §4.4 四类模式择用：①**round-trip**（URL 构造与解析 `decode(encode(x)) == x`、`formatExpiryISO` 合法输入可还原同一时刻）；②**不变量**（相位状态机"取消/重跑"操作下终态不可取消、isRunTerminal 与 isRunCancellable 恒互补）；③**幂等**（重试类操作 `f(f(x)) == f(x)`，如 `parseActions` / `knownSubjects` 二次归一不变）；④**等价**（优化实现与朴素正确实现对任意输入产出一致，如 `flattenVisible` 索引连续、`shouldVirtualize` 阈值边界）。继续对未覆盖纯逻辑补属性，输入由属性库生成器产生、与被测代码作者 bias 解耦，属性陈述人审一次后固化。spec 与实现漂移时约束比 spec 稳、属性测试仍可用（重写/迁移场景尤其有效）。
- 【对抗推演】AI 用同源 bias 输入生成（VP-02）→ 输入必须由属性库生成器独立产生，属性陈述人审固化。
- 【建议可信度】已验证模式（D3/VP-02/§4.4）。
- 【由谁决策】工程；属性陈述人审。
- 【严重度】低。

### 建议 10（P2）漏检回流双法 + 元验证 + flaky 治理
- 【缺口】D12 缺失，元验证（VP-07）与 flaky 治理（D11）机制未固化：无漏检→规则准入门槛的执行记录；`governance/golden-set.md` 存在但无持续度量与分阶段 recall 实装。
- 【证据】S12（`REVIEW.md` / `golden-set.md` 存在）；S10 实跑当前 0 flaky 信号，但禁止 sleep/rerun 的静态门未接 CI 常驻。
- 【建议改动】漏检→规则按 §4.7 双法并行：第一法三门槛（≥2 PR + ≥3 独立 agent 证伪 + 人审合入）；第二法用 3 个 bug finder 回放已知事故（≥2 命中才算可检测，**小 diff 上也被漏掉**即重点信号）。flaky 治理按 §4.6：禁 sleep/rerun-to-green，**根因修不好则删除该测试并写下删除理由**；把 S10 的实跑接入 CI 作为常驻门。元验证按 §4.8：以 `governance/golden-set.md` 为基础（真实事故/revert + 体量相当干净对照），**每例附一句话答案（answer key），只有正确描述该 bug 的 finding 才计分**——否则"随便报一条就算命中"会让 recall 虚高；分阶段 recall（原始发现→验证后→终审分别统计）、发现分级（Important/Nit/Pre-existing）、**数据集隔离（tuning 与 fixed 分离）**、**调参到过拟合边缘即停**、例行修剪；持续度量 merged 后 revert 数 / maintainer 合入前拒绝数作为长期体温计。
- 【对抗推演】AI 对 flaky 测试加 sleep/rerun 反复重跑（RT-16）→ 测试路径静态禁 sleep/rerun（R-VER-009）+ 连续失败阈值（建议 2）；第二法防"规则从人已发现的模式归纳，却测不出机器能否复现发现"；数据集隔离防"调参即过拟合"无法察觉；一句话答案 + 只给正确描述计分防验证器靠宽口径虚报 recall。
- 【建议可信度】已验证模式（D12/VP-07/§4.7 双法、§4.8 含一句话答案评分口径、D11/R-VER-009）。
- 【由谁决策】工程 + 契约负责人。
- 【严重度】低。

### 建议 11（P2，工具改进）把代码注释内声明纳入文档一致性扫描
- 【缺口】doc_consistency 扫 markdown 链接，不扫代码注释内的路径引用与"N 套件"类数量声明（S9），这类声明目前靠人核。
- 【证据】S9：`ci.yml` 注释 8 套件与 `package.json` 8 个 smoke 套件一致、无失效文档路径；`doc_consistency_check.py --root .` = PASS 但未覆盖代码注释。
- 【建议改动】扩展文档扫描器覆盖代码注释内的路径引用与"N 套件"类数量声明（属工具改进建议，由使用者决定是否回流 skill）。
- 【对抗推演】无（文档精确性改进，非治理规则）。
- 【建议可信度】已验证模式（S9 路径与计数可复查）。
- 【由谁决策】工程 / 审计工具维护者。
- 【严重度】低。

---

## 五、确认为达标的维度（附证据，避免只报缺口）

- **D1 基础静态门**：lint/typecheck/test/build 四步在 CI 与本地均可用且实测全绿（S2+S4）。
- **D2 契约冒烟规模**：8 套件 187 条断言、覆盖 URL 策略/主题搜索/管线编辑/服务树/平台权限/接入目标/运行控制/目标台账，无空断言/凑绿 skip（S5）。
- **D6 CI 边界**：L0 验证 / L1 发布分层，frozen lockfile、concurrency、最小 permissions（S2）。
- **D11 flaky 信号**：`static_risk_check.py` 对 8 个测试路径全量实跑 PASS，0 处 sleep/rerun/skip/flaky（S10）。

---

## 六、工程化建议：人工核对 → 机器检查

| 人工核对项 | 升级条件 |
| --- | --- |
| lint 一致性（建议1） | CI 与本地 lint step 均在（S2/S4）；规则深度与服务端 required check 由工程配置后机检 |
| 升级阈值（建议2） | 阈值已在 `governance/redlines.yaml`（S12）；harness 计数与转人实装后由 E-05 机检 |
| 证据协议（建议3） | 证据包格式对齐 schemas.md 后由 harness 校验落点存在性 |
| 验证戳覆盖（建议6） | `thresholds.verification_stamp` 已在 redlines（S12）；`verification_gate_check.py --repo` 机检 stamped/total 比率 |
| 拦截谓词（建议6） | 谓词动作绑 hook 后，查会话内事实（非 commit message 戳）属人工核；机检管不到 |
| verify 资产存在性（建议4） | survey `verify_asset=['verify.yaml']`（S3）；done 是否真跑用户流仍需人核 |
| 前端视觉判据（建议5） | 基线/容差入 `protected_paths` + 证据包 `screenshot` 带 sha256 后可机检比对；基线首版与漂移处置须人审 |
| 覆盖率/mutation（建议7） | vitest coverage + CI 报告后 `ci_gate_check.py` 机检 |
| 判卷独立性① ②（建议8） | 查受保护路径 + CI 从目标分支取（RT-01 同机制） |
| 判卷独立性③ ④ ⑤（建议8） | owner 写检查 / say-why / 多轮累积运行形态属人工核对与社会工程 |
| flaky 信号（建议10） | `static_risk_check.py` 已可机检（S10 实跑）；接入 CI 常驻门 |
| 漏检双法（建议10） | 第二法"≥2 命中 + 小 diff 漏检"可做成 bug finder 回放作业 |
| 元验证评分口径（建议10） | golden set 一句话答案 + 只给正确描述 bug 的 finding 计分属人工核口径，机检不做语义评分 |
| 注释/文档漂移（建议11） | 扩展 doc_consistency 覆盖代码注释内路径与数量声明后机检 |

---

## 七、蓝图覆盖表（§6 强制，防"漏带蓝图"）

> 处置三选一：`已建议`（去向指向建议编号，或显式标注「详见蓝图 §4.x（正文要点化，细节不重复）」）/ `当前不适用`（附理由）/ `待建设`（标 P0/P1/P2）。D 表（第二节）答"项目缺什么"，本表答"蓝图每项去了哪"，两表齐才闭环。覆盖范围含 §0/§1/§3/§4 全节（含 §4.10）+ VP。§4.3 五子、§4.4 四模式+spec 漂移、§4.7 双法、§4.10 四子项逐项拆行。§0 证据措辞与 +10 分实证数字、§3 能力+平台适配器分离口径、§4.5 拦截谓词、§4.8 golden set 评分口径属机检管不到的语义项，人工对照原文核。

| 蓝图条目 | 处置 | 去向（可核） |
| --- | --- | --- |
| §0 三个事实与证据协议（独立 grader 按 rubric 判卷 **+10 分、最难任务收益最大** / 验证即固定资产 / 39 项命中 3~10；agent 自述不算证据、评审绑 commit；**证据由外部 harness 收集、agent 只能引用不能转述**；要点化保留 +10 分数字与此措辞） | 已建议 | 建议 3/6/8；详见蓝图 §0（正文要点化，细节不重复） |
| §1 三种测试选择依据（E2E 难欺骗 / 属性独立生成器 / 差分旧系统 oracle） | 已建议 | 建议 4/5/9；差分见 §4.9 行当前不适用；详见蓝图 §1（正文要点化，细节不重复） |
| §1 警告① flaky 训练重跑 | 已建议 | 建议 10（R-VER-009 + E-05，VP-06） |
| §1 警告② 慢测试降低验证频次 | 待建设（P2） | 当前 smoke 轻量、门跑得勤；后续加视觉/E2E 重门按 cheap-first 评估，重门放提交边界 |
| §1 警告③ 重测试放提交边界 | 已建议 | 建议 7（mutation 在提交边界）、建议 6（off→observe→enforce） |
| §3 建设顺序 P0→P1→P2（cheap-first：开 PR 前本地 test/build/lint 全绿，重门在提交边界；**"本地先跑"的可执行形态：agent 无关的本地强制点〔通用做法 git pre-commit hook〕+ 各 agent 生态完成时事件作可选加速器，专有命令只作示例不作判据**） | 已建议 | 建议 1/3/4/6；本报告建议标题阶段按 §3 权威表标注；详见蓝图 §3（正文要点化，细节不重复） |
| §4.1 verify 资产（含 hands 手和眼、feature map 当 rubric、harness 压测稳定） | 已建议 | 建议 4（feature map 落到建议 5 异常态清单）；详见蓝图 §4.1（正文要点化，细节不重复） |
| §4.2 验证戳（含 none、白名单外无效） | 已建议 | 建议 6（P1） |
| §4.3 ① 规则从 base 分支读 | 已建议 | 建议 8（P1） |
| §4.3 ② 评审绑定 commit、推新作废 | 已建议 | 建议 8（P1） |
| §4.3 ③ code owner 写检查 | 已建议 | 建议 8（P1） |
| §4.3 ④ 拉人须说 why | 已建议 | 建议 8（P1） |
| §4.3 ⑤ 单一 reviewer 多轮累积、不堆叠 | 已建议 | 建议 8（P1） |
| §4.4 ① round-trip | 已建议 | 建议 9（P2） |
| §4.4 ② 不变量 | 已建议 | 建议 9（P2） |
| §4.4 ③ 幂等 | 已建议 | 建议 9（P2） |
| §4.4 ④ 等价 | 已建议 | 建议 9（P2） |
| §4.4 spec 漂移时仍可靠（约束比 spec 稳，重写场景尤其有效） | 已建议 | 建议 9（P2） |
| §4.5 门禁灰度 off→observe→enforce 三档（含 off 档、误拦日志、被拦两次后放行）**+ 拦截谓词**（门拦"会话内未执行约定验证动作的提交"，与验证戳互补；要点化保留"拦什么"） | 已建议 | 建议 6（P1，三档 + 谓词均在正文定义） |
| §4.6 flaky 治理（禁 sleep/rerun、删测试写理由） | 已建议 | 建议 10（P2）；详见蓝图 §4.6（正文要点化，细节不重复） |
| §4.7 第一法：三门槛（≥2 PR + ≥3 agent 证伪 + 人审合入） | 已建议 | 建议 10（P2） |
| §4.7 第二法：3 bug finder 回放已知事故 ≥2 命中、小 diff 漏检重点 | 已建议 | 建议 10（P2） |
| §4.8 元验证（持续度量 merged 后 revert 数 / maintainer 合入前拒绝数 / 干净变更对照、golden set **一句话答案 + 只有正确描述该 bug 的发现才得分**、分阶段 recall、Important/Nit/Pre-existing、数据集隔离 tuning vs fixed、调参到过拟合边缘即停、修剪；要点化保留评分口径） | 已建议 | 建议 10（P2，一句话答案与计分口径在正文定义） |
| §4.9 差分测试（oracle/采样、归一化、允许变更白名单、收敛判据） | **当前不适用**：无"可并行运行的旧实现"——仓库无 migrat/legacy/rewrite 特征；`src/api/approval.ts` 是业务审批 API 非 approval testing；auth BFF 演进为替换式、无旧实现双跑；无 golden/snapshot 特征（S7）。将来若引入前后端双跑/重写迁移再启用 | — |
| §4.10 ① 基线管理（protected_paths / 人确认首版 / 稳定时刻 / sha256） | 已建议 | 建议 5（P1） |
| §4.10 ② 比对协议（baseline/actual sha256 + diff 指标 + 容差 + 漂移处置分岔） | 已建议 | 建议 5（P1） |
| §4.10 ③ 异常态驱动清单（网络失败/空数据/超时/权限/弹窗抽屉各态 + 截图↔用例映射） | 已建议 | 建议 5（P1） |
| §4.10 ④ 截图一等证据（schemas screenshot 类型 + sha256 + 场景 id） | 已建议 | 建议 5（P1） |
| VP-01 verify harness 是地基 | 已覆盖 | §4.1 行 / 建议 4 |
| VP-02 三种测试选择依据 | 已覆盖 | §4.4 行 / 建议 9；E2E 见建议 4/5 |
| VP-03 判卷独立性 | 已覆盖 | §4.3 五子机制 / 建议 8 |
| VP-04 cheap-first | 已覆盖 | §3 行 / 建议 1/4/7 |
| VP-05 observe→enforce | 已覆盖 | §4.5 行 / 建议 6 |
| VP-06 flaky 铁腕治理 | 已覆盖 | §4.6 行 / 建议 10 |
| VP-07 漏检回流+元验证+修剪 | 已覆盖 | §4.7 双法 / §4.8 行 / 建议 10 |

**覆盖自检**：§0/§1/§3/§4 全节均有处置；§4.1~4.10 十项全处置（§4.1~4.8 八项已建议 + §4.9 当前不适用附理由 + §4.10 四子项已建议）；§4.4 四模式 + spec 漂移拆五行、§4.3 五子、§4.7 双法、§4.10 四子项逐项拆行；VP-01~07 全部映射；机检管不到的语义项按蓝图原文人工核并写入对应建议正文与覆盖行——§0"agent 只能引用不能转述"与 +10 分/最难任务收益最大（建议 3/8）、§3 能力+平台适配器分离口径（建议 3）、§4.5 拦截谓词（建议 6）、§4.8 golden set 一句话答案 + 只有正确描述该 bug 的发现才得分（建议 10）；所有去向仅用建议编号或「详见蓝图 §4.x」，无不可核自证断言；建议标题阶段与 D 表判定按 §3 权威表对齐，跨阶段 D7 已拆为独立 P0 建议。已由 `report_gate.sh` 单一入口机检确认。

---

## 八、归档与回流

- 本报告归档于 console 仓库 `audits/`，为审计自有产物；仓库工作区现有 S1 所列未提交资产与改动，本报告未修改任何被审源码/配置/CI。
- 未发现 `attack-cases.md` 案例库未收录的新型绕过手法，**无晋升建议**。
- 全部结论为建议模式输出，**非合规判定**；采纳与否由人决策。
