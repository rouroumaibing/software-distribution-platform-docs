# software-distribution-platform-console 推荐落地计划

> 配套报告：2026-11-18-console-verification-system.md
> 口径：本计划为建议，按依赖排序；采纳与否由人决策。成熟度阶段（P0/P1/P2）是建议本身的属性，不是批次顺序。

## 一句话结论

地基停在"静态门可用"层：CI 有 lint/typecheck/test/build、本地四绿，8 套件契约冒烟全过、属性测试 12018 checks PASS，但 smoke 均为静态文本断言、`verify.yaml` 的 done 只到静态门日志，没有真跑完整用户流的 verify 循环，前端交互也无视觉基线（D4b 缺失）。第一批守住 lint 门与注释一致性（便宜可逆），第二批把 verify 循环的 done 推到 playwright 驱动真实页面跑完整用户流并落外部证据——它是后面所有门的消费者前提。

## 批次总览

| 批次 | 目标 | 吸收建议 | 前置 | 验收 gate | 需拍板 |
| --- | --- | --- | --- | --- | --- |
| 第一批：守住 lint 门与注释一致性 | 让 CI 说真话、门能拦住风格漂移 | 建议 1/11 | 无 | `pnpm lint` rc=0；`pnpm typecheck` rc=0；`ci.yml` 注释套件数与 `package.json` test 脚本一致 | 无 |
| 第二批：跑通 verify 循环 | 定义 done、真跑一次完整用户流、落外部证据 | 建议 3/4 | 第一批 | `pnpm build` rc=0、`pnpm dev` 服务起；hands 用 playwright 驱动真实页面跑通关键用户流，落截图 `evidence/*.png` 与接口响应 `evidence/*.json`（带时间戳 + sha256）到 `evidence/`，退出码 0 | 无 |
| 第三批：建前端视觉判据 | 界面回归有截图证据、异常态可判卷 | 建议 5 | 第二批 | `verify visual-diff` rc=0；基线入 `evidence/baseline/` 且附 sha256/稳定时刻；异常态清单覆盖网络失败/空数据/权限/弹窗各态，截图↔用例映射见 `REVIEW.md`；容差阈值标为参数，驱动入口/证据落点/比对脚本照常进批次 | 见需拍板项③ |
| 第四批：铺证据协议与升级策略 | 结论不再靠自述、失败有转人阈值 | 建议 2 | 第二批 | 抽查 3 条 agent 结论均附退出码与日志路径；E-05 阈值（redlines 现为 3）经 `report_gate.sh` 校验存在 | 见需拍板项① |
| 第五批：验证戳与判卷独立性 | 未验证可查询、判卷防自欺 | 建议 6/8 | 第四批 | 门以 observe 运行；`REVIEW.md` 已列五条机制并纳入 `protected_paths`，服务端从 base 分支取规则 | 见需拍板项② |
| 第六批：补测试与漏检闭环 | 抗偏差、同一个坑不踩两次 | 建议 7/9/10 | 第五批 | `pnpm test` rc=0（含属性测试 12018 checks）；golden set 每例附一句话答案与计分口径 | 无 |

## 各批次明细

### 第一批：守住 lint 门与注释一致性

- **做什么**：保持 `ci.yml` 注释与 `package.json` test 脚本的 8 套件一致、无失效文档路径；CI 与本地的 lint（`node scripts/lint.mjs`）和 typecheck 门保持在位；文档一致性扫描器覆盖代码注释内的数量与路径声明。
- **吸收建议**：建议 1（守住 lint 门并接服务端 required check）、建议 11（把代码注释内声明纳入文档一致性扫描）
- **验收 gate**：
  - `pnpm lint` → rc=0（`lint: PASS (103 files)`）
  - `pnpm typecheck` → rc=0
  - `ci.yml` 注释套件数与 `package.json` test 脚本一致；`doc_consistency_check.py --root .` → PASS
- **完成定义**：lint/typecheck 门在 CI 与本地都能跑，注释与实现一致，不靠自述"已修好"。

### 第二批：跑通 verify 循环

- **做什么**：`verify.yaml` 的 `build`/`start`/`done` 三字段齐，done 现指向 typecheck/test/build 日志；用 playwright 驱动真实页面跑关键用户流（登录→主界面→登出），把 done 推进到真实可观测状态；hands 给 agent 手和眼，8 套件 feature map 当 rubric。**harness 自身须先压测到稳定**——它是全部下游验证的地基。
- **吸收建议**：建议 3（证据协议）、建议 4（把 verify 的 done 推进到真跑用户流）
- **验收 gate**：
  - `pnpm build` → rc=0；`pnpm dev --host 127.0.0.1` → 服务就绪（HTTP 200）
  - playwright 驱动真实页面跑通关键用户流 → 落截图 `evidence/*.png`、接口响应 `evidence/*.json`、带时间戳日志 `evidence/*.log`，各附 sha256，退出码 0
- **完成定义**：从 build、起服务到 playwright 跑完用户流并落截图/响应证据的整条链在一次会话内跑通，退出码 0。

### 第三批：建前端视觉判据

- **做什么**：按 §4.10 落三件：①基线截图列入 `protected_paths`、首版人确认、记录视口/驱动版本/稳定时刻/sha256；②比对协议含 baseline_sha256/actual_sha256/diff_metric/容差，漂移分岔写清"代码回归修代码、有意 UI 变更人审后更基线"；③异常态驱动清单覆盖网络失败/空数据/超时/权限/表单校验/弹窗抽屉各态，截图↔用例一一映射；截图按 `schemas.md` 的 `screenshot` 一等证据类型入证据包。容差阈值只作参数，驱动入口、证据落点与比对脚本照常进批次。
- **吸收建议**：建议 5（前端视觉验证与异常态驱动清单）
- **验收 gate**：
  - 每张基线 → 附 `sha256`、稳定时刻定义、人确认记录
  - 异常态清单执行 → 截图与用例一一映射、`diff_metric` 与容差阈值可核（阈值参数化）
- **完成定义**：done 判据是机器可判定的比对结果，不是"看起来正常"。

### 第四批：铺证据协议与升级策略

- **做什么**：让所有 agent 结论附退出码与日志/截图路径（由 harness 收集、agent 只能引用不能转述）；按 redlines 的 `max_consecutive_gate_failures: 3` 由 harness 计数并转人。
- **吸收建议**：建议 2（E-05 连续失败转人阈值）、建议 3 的协议铺开部分（建立证据协议）
- **验收 gate**：
  - 抽查 3 条 agent 结论 → 均附退出码与日志路径
  - E-05 阈值在 `governance/redlines.yaml` 存在 → 经 `report_gate.sh` 校验
- **完成定义**：协议成为默认动作，不是偶尔填写。

### 第五批：验证戳与判卷独立性

- **做什么**：引入验证戳（含 `none`）与拦截谓词（门拦"会话内没执行过约定验证动作的提交"）；门先 observe 不 enforce；以现有 `REVIEW.md` 为清单，落实五条判卷独立性机制（base 分支读规则、评审绑 commit、code owner 写检查、拉人说 why、单一 reviewer 多轮），清单入 `protected_paths`。
- **吸收建议**：建议 6（验证戳+三档+拦截谓词）、建议 8（REVIEW 判卷清单与五条独立性）
- **验收 gate**：
  - 门以 observe 模式运行 → 记录误拦数为 0
  - `REVIEW.md` 五条机制逐项可核、可从 diff 读 trigger，且列入 `protected_paths`
- **完成定义**：门在 observe 下稳定、判卷清单可操作。

### 第六批：补测试与漏检闭环

- **做什么**：补覆盖率与 mutation 门禁；属性测试已有 `scripts/property-test.mjs`（四模式、12018 checks PASS），继续对未覆盖纯逻辑补属性（独立生成器）；漏检→规则双法（三门槛 + bug finder 回放已知事故）；元验证以 `governance/golden-set.md` 为基础（每例一句话答案、只有正确描述该 bug 才计分、数据集隔离）；`static_risk_check.py` 接 CI 常驻门保持 0 命中。
- **吸收建议**：建议 7（覆盖率与 mutation）、建议 9（属性测试）、建议 10（漏检回流双法 + 元验证 + flaky 治理）
- **验收 gate**：
  - `pnpm test` → rc=0（含 `test:property` 12018 checks）
  - 属性测试四模式齐、纯逻辑覆盖可核
  - golden set 每例 → 附一句话答案与计分口径
- **完成定义**：三层测试投资（静态冒烟 / 属性 / 判卷）各有真实 gate。

## 需拍板项（单列）

| 编号 | 决策点 | 推荐值 | 理由 | 默认动作 |
| --- | --- | --- | --- | --- |
| ① | E-05 连续失败转人阈值 | 3 次（redlines 现值） | 蓝图 §3 默认值为 3，低于 3 易误转、高于 3 浪费轮次 | 按推荐值 3；要改请指出 |
| ② | 验证戳门何时从 observe 转 enforce | 观察满一周且误拦为零再转 | 直接 enforce 会拦住尚未接钩子的历史提交 | 按推荐值；要提前转请指出 |
| ③ | 前端视觉基线 diff 容差阈值 | 人审首版截图后固化像素差/感知阈值，阈值在 redlines 标为参数 | 容差过松漏检、过紧误拦，且基线首版须人确认 | 容差作参数按推荐值人审固化；驱动入口/证据落点/比对脚本照常进批次，不因阈值未定整批推迟；要调请指出 |

## 当前不适用（不进批次）

| 建议 | 不适用理由 |
| --- | --- |
| 无 | 本仓库 11 条建议全部纳入批次；§4.9 差分测试在报告里已判当前不适用（无可并行旧实现），未列为建议 |
