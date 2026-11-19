# 三仓验证体系 × Claude Code verification 文章 · 对齐复核

# 对齐来源：claude.dev《How the Claude Code team thinks about verification》(2026-11-16)。
# 对齐对象：console / hub / runner 三仓当前工作区 + docs/plans/audits 三份审计报告与落地计划。
# 判定口径：`已落地`=仓库内有可执行资产且真跑；`仅声明`=有配置/文档骨架但无执行机制；`遗漏`=文章要求而三仓均无；`不适用`=前提不成立。

## 一、对齐矩阵

| # | 文章机制 | console | hub | runner | 判定 |
| --- | --- | --- | --- | --- | --- |
| T1 | E2E 真跑系统（hands and eyes，难欺骗，done 明确） | 已落地：`scripts/e2e-verify.mjs` 自启 Vite+Chrome 经 CDP 驱动 5 页，落截图/网络/响应证据（带 sha256），真跑 PASS | 已落地：`scripts/e2e-verify.sh` Flow A 登录 + 打 4 个业务端点（ops/health 带 DB ping / targets / runs / notifications），真跑 PASS | 已落地：`scripts/e2e-verify.sh` 查 runner 注册 online + 心跳新鲜（WS 回连外部事实），真跑 PASS | **已落地** |
| T2 | Property 四模式 + 独立生成器 | 已落地：`scripts/property-test.mjs`，12018 checks，四模式 + LCG 独立生成器 | 已落地：`properties_test.go` | 已落地：canary/snapshot 两处属性测试 | 已落地 |
| T3 | Differential（旧系统作 oracle） | 不适用：无可并行旧实现 | 不适用：schema 迁移为破坏式替换 | 不适用：`v1alpha1` 是 API 版本非旧实现 | 不适用（合理） |
| V1 | verify skill 放 `.claude/skills/`，committing 前自动用 | 未接：无 `.claude/` 目录；仓库内入口是 `scripts/e2e-verify.*` + `verify.yaml` | 同左 | 同左 | **未接（agent 侧适配层）** |
| V2 | harness 快且稳，压测到可靠（VP-01） | 部分：harness 真跑 PASS 一轮，无多轮压测记录（cheap 层 `pnpm test` 常驻） | 部分：真跑 PASS 一轮 | 部分：真跑 PASS 一轮 | 部分覆盖 |
| V3 | 失败 3 轮转人 | 部分：`max_consecutive_gate_failures: 3` + `verify-gate.sh` 会话计数逃生门（拦两次放行），未绑提交钩子 | 同左 | 同左 | 部分覆盖 |
| V4 | code owner 写自己的检查、拉人说 why | 已落地：`REVIEW.md` 五条独立性含此两项 | 已落地 | 已落地 | 已落地 |
| V5 | 可靠性清单按 diff 触发，只读命中项 | 已落地：`REVIEW.md` C1~C7 带触发器 | 已落地：H1~H7 | 已落地：R1~R7 | 已落地 |
| V6 | 单一 reviewer 多轮累积，不堆 reviewer | 已落地：`REVIEW.md` 第 5 条 | 已落地 | 已落地 | 已落地 |
| V7 | 检查不可被改动（从 base 读规则、绑 commit） | 仅声明：`protected_paths` 配了，从 base 取规则的脚本未落 | 同左 | 同左 | 仅声明 |
| V8 | cheap checks first（本地先跑 test/build/lint） | 部分：CI 有 Lint/Typecheck/Test/Build；`verify-gate.sh` 提供 mark-verified 入口，本地 hook 未绑（`core.hooksPath=none`） | 部分：CI 有 Format/Vet/Build/Test + gate 入口 | 部分：同左 | 部分覆盖 |
| V9 | commit 戳（含 none）+ off/observe/enforce 三档门 | 已落地（仓库内）：`verify-stamp.sh` 盖戳/校验/覆盖率 + `verify-gate.sh` 三档；平台强制（branch protection）未配 | 同左 | 同左 | **仓库内已落地，平台强制 pending** |
| V10 | 门误拦日志 + 被拦两次放行逃生门 | 已落地：`verify-gate.sh` 误拦日志 + 同会话拦两次后放行（已实跑验证） | 同左 | 同左 | 已落地 |
| V11 | review the reviewers：revert/reject/干净对照实测 | 仅声明：`continuous_metrics` 三项，无数据 | 同左 | 同左 | 仅声明 |
| V12 | golden set 一句话答案 + 只有正确描述才得分 + 固定/调参隔离 + 分段 recall + 三级严重度 | 骨架已落地：`golden-set.md` scoring/sets 齐全，回放 pending | 同左 | 同左 | 骨架已落地，执行 pending |
| V13 | miss 转规则双法（≥2 PR 模式 + 3 agent 反驳 + 人审；3 bug finder 回放 ≥2 命中） | 部分：`governance/miss-log.md` 固化阈值与记录位（entries 空），回放/PR 提取未执行 | 同左 | 同左 | 部分覆盖（记录位已落，执行 pending） |
| V14 | flaky 不许 skip/sleep/重跑，找不到根因删测试写原因 | 已落地：5 处 sleep 真改条件等待、t.Skip 带理由豁免、反向验证新增 sleep 被拦 | 已落地（最强） | 无 flaky 命中，规则在 `REVIEW.md` | 已落地 |
| V15 | 规则定期清理 prune | 已落地（仓库内）：`REVIEW.md` 季度清理四触发 + `miss-log.md` prune 记录位；定期执行属组织侧 | 同左 | 同左 | **仓库内已落地，执行 pending** |
| E1 | 证据留存边界：运行时证据不入库、凭据采集端不落盘、判卷基线入库受保护（v28 §4.12 / VP-09 / RT-19） | 遗漏：`evidence/` 未进忽略规则，`cookies.txt` 含真实 `sdp_sess`，无 `!evidence/baseline/` 例外 | 同左 | 同左 | **遗漏（skill 已根治判据，三仓治理待做）** |

## 二、剩余遗漏项分级（按文章优先级）

本轮按 v26 落地计划执行后，原 P0 的 T1 真 E2E、V9/V10 戳门已实装并真跑；原 P1 的 V13/V15 已落仓库内记录位。剩余项按"能否仓库内闭环"重新分级。

### P0 — 文章最强调、仍需适配层
1. **V1 仓库内 verify skill**：文章要求 `.claude/skills/verify/` 且 agent committing 前自动用。三仓已有 `scripts/e2e-verify.*` + `verify.yaml` 作为仓库内入口，但没有 agent 可调用的 skill 封装、也未绑提交动作。Claude 生态用 skill/Stop hook，通用 agent 需等价适配层（用户已明确 /goal 是 Claude 专有，能力须平台无关）。这是"能力已备、适配器未接"，不是能力缺失。

### P1 — 平台/组织配合，仓库内已尽力
2. **V9 平台强制**：戳门三档与逃生门仓库内已实跑，但 branch protection required check、提交链接入在平台侧，当前门只在 observe 档（推荐值：观察满一周误拦为零再转 enforce）。
3. **V8 本地 hook**：`verify-gate.sh` 提供 start-session/mark-verified/check 入口，`core.hooksPath` 绑定在开发者侧，未强加。
4. **V7 从 base 读规则**：`REVIEW.md` 声明了独立性，取 base 版脚本未落（需 git worktree/base ref，属流程实装）。
5. **V13/V15 执行**：miss-log 与 prune 记录位已建且阈值/触发齐，但 ≥2 PR 样本提取、3 agent 回放、季度清理执行需真实事故与责任人。
6. **V11/V12 元验证实测**：golden set 骨架齐（命中口径/分级/隔离/分段 recall），回放执行与 continuous_metrics 统计需历史 revert/reject 样本。
7. **V2 harness 压测**：三仓 E2E 真跑各一轮 PASS，多轮稳定性压测未做。
8. **feature map 粒度**：`verify.yaml` 的 feature_map 已列 FLOW 端点/页面，但未细化到选择器/快捷键级；文章要求按用户视角列路径/预期结果，当前粒度到"页面/端点 + 关键字段"为止。
9. **E1 证据留存（v28 新增判据）**：三仓 `evidence/` 未被忽略规则覆盖（survey `ignored=false`），hub/runner 的 `cookies.txt` 含真实 session cookie（`enc:v1:...`），无 baseline 忽略例外。skill 已加 §4.12 + `evidence_retention` 机检段可从产物检出；三仓代码级修复（采集端脱敏 + `.gitignore`）未做，待授权。

### 合理不适用
10. **T3 差分测试**：三仓均无并行旧实现，判"不适用"正确；将来做前后端双跑或重写迁移时启用。

## 三、本轮执行与上一轮的关系（如实标注）

上一轮"全部批次都做"落的是仓库内可静态落地的部分：治理四件套、`REVIEW.md`、属性测试、CI 门、hub flaky 真整改，E2E/戳门停在声明层。

本轮按 v26 落地计划（第二批承重墙 gate 强制"真跑 + 外部证据"）执行，补齐三仓的：E2E harness（console CDP 真驱动 5 页、hub 业务端点、runner agent 回连事实）并各落一份带 sha256 的证据；戳门工具链（盖戳/校验/覆盖率 + off/observe/enforce 三档 + 误拦日志 + 逃生门，已实跑验证）；miss-log 记录位与 REVIEW 季度清理触发。三仓全 gate 绿（console lint/typecheck/test/build，hub/runner gofmt/vet/build/test），三份报告机检三道 PASS。

仍属组织/平台配合的项目（平台强制、observer 转 enforce、本地 hook 绑定、回放与清理执行、元验证实测）已在上文分级标注，未计入"已落地"。

## 四、补法与责任边界

| 项 | 仓库内状态 | 需组织/平台配合 |
| --- | --- | --- |
| T1 真 E2E | 已落 harness 并真跑：console CDP 5 页截图、hub 4 业务端点、runner 回连事实 | 视觉基线首版人审、稳定时刻定义；E2E 入 CI 提交边界 |
| V1 verify skill | 入口已备（`scripts/e2e-verify.*` + `verify.yaml`） | 各 agent 生态的 skill 封装与 committing 前调用约定（Claude 用 skill/Stop hook，通用 agent 用等价适配层） |
| V9/V10 戳门 | 已落并实跑三档 + 逃生门 + 误拦日志 | 提交链接入、branch protection required check、observe→enforce 切换 |
| V3/V7/V8 | 阈值/会话计数/mark-verified 入口已落 | 本地 hook 绑定、从 base 取 REVIEW.md 的流程实装 |
| V13 miss 转规则 | 阈值与记录位已落 | ≥2 PR 样本、3 agent 回放、人审批准 |
| V11/V12 元验证 | golden set 骨架齐 | 历史 revert/reject 对照样本、回放与分段 recall 实测 |
| V15 规则清理 | 季度触发与 prune 记录位已落 | 责任人定期执行 |
| E1 证据留存 | v28 survey `evidence_retention` 段已能机检检出缺口 | 三仓 `.gitignore` 覆盖证据目录 + 采集端 cookie 脱敏 / 不落盘 + `!evidence/baseline/` 例外 |

## 五、复核记录

- 2026-11-19：按 v26 落地计划执行三仓第二批承重墙（真跑 + 外部证据）及后续仓库内可落项后复核。真跑证据目录：console `evidence/2026-11-19T02-09-23-071Z/`、hub `evidence/2026-11-19T02-13-49Z/`、runner `evidence/2026-11-19T02-15-52Z/`。
- 2026-11-19：harness-workflow v28 从 skill 根治证据留存边界（§4.12 + VP-09 + RT-19 + `verification_gate_check.py --survey` 的 `evidence_retention` 段），源与副本同步、全套检查器 self-test 绿。用新 survey 重走三仓：三仓 `evidence/` 均 `ignored=false`、无 baseline 例外；hub/runner 检出 `cookies.txt`（真实 session cookie），console 检出截图/响应证据目录。用新三道门重跑三仓报告与落地计划，均 PASS（新判据为"报告若带 §4.12 则校验拆行"，既有报告未失效）。三仓代码级治理待授权。
