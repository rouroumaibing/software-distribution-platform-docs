# 审计报告：runner 仓库验证体系体检

- 审计对象：`software-distribution-platform-runner`（main@0e72a49；工作区有本地改动：`.github/workflows/ci.yml` 已改，`REVIEW.md`、`governance/`、`verify.yaml`、`pkg/canary/properties_test.go`、`internal/dispatch/snapshot_properties_test.go` 未入库）
- 审计日期：2026-11-18
- 审计模式：**建议模式**——仓库有 `governance/redlines.yaml`（阈值与保护路径），但无契约、`required_rules` 未设。按采纳边界，本报告为**建议清单，非合规判定**；"无契约/required_rules 未设"是建议素材，不构成违规。
- 审计类型：验证体系 survey（`verification_gate_check.py --survey`）+ 静态门实测 + 文档一致性 + flaky 实跑（`static_risk_check.py`）+ 人工核对
- 独立性声明：**非独立验证**——同一会话内由执行审查的 Agent 兼任，未经干净会话独立复核；高风险结论须人精读原始证据。
- 证据口径：结论均附命令输出 / 文件路径 / 字段值。survey 为形态探测，miss 不构成违规。机器推算仅供参考，关键断言须人核原文。
- 覆盖规范：按 harness-workflow `verification-program.md` §6，覆盖表逐条处置 §0/§1/§3/§4 全节与 VP-01~07，每条「已建议」去向可核，并列子项拆行；§0 证据措辞与实证数字（+10 分/最难任务收益最大）、§3"改动交给下游前自动跑 test/build/lint 并留痕"的能力与平台适配器分离口径（git `pre-commit` hook 为通用落点，各 agent 生态完成时事件只作可选加速器、不作能力判据）、§4.5 拦截谓词、§4.8 实证评分口径（golden set 一句话答案/只有正确描述该 bug 才得分）等"机检管不到"的语义项按蓝图原文人工核；报告落盘前经 `report_gate.sh` 单一入口机检（一次跑完 `coverage_table_check.py` + `stage_consistency_check.py` 并聚合退出码）。

---

## 一、结论摘要

runner 仓库已有**可运行的基础静态门**（CI 上 gofmt/vet/build/test 四条、本地实测全绿），14 个受版本控制的测试文件全部带真实断言（单文件 2~19 处）、零 `t.Skip`，`static_risk_check.py` 实跑 0 命中——在 flaky 纪律与格式一致性上明显比同平台的 hub 干净（hub 有 5 文件未 gofmt、6 处 sleep/skip 信号）。这是真实且可复查的优点。按 D1~D12 诊断，体系整体处于**建设早中期**：D2/D11 达标；D1/D3/D4/D6/D8/D9/D10 为部分；D7/D12 缺失；D5 当前不适用。工作区已有可复查的骨架资产——`verify.yaml`、`REVIEW.md`、`governance/redlines.yaml`（含 `verification_stamp` 与 `max_consecutive_gate_failures` 阈值）、`governance/golden-set.md`，以及 `pkg/canary/properties_test.go` 与 `internal/dispatch/snapshot_properties_test.go` 两个属性测试文件（经 `go test ./...` 实跑通过）；但验证戳覆盖仍为 0、无真实任务下发流的外部证据、REVIEW 清单与阈值尚无钩子实装、属性测试未用外部属性库。按 §3 阶段归属表：P0（D1/D7/D10）中 D1/D10 有基础、D7 仍缺；P1（D4/D8/D9）三项均有骨架但闭环不足；P2（D3/D5/D11/D12）中 D3 部分、D11 达标、D5 不适用、D12 缺失。

CI 注释与实现的漂移已有处理：`ci.yml` 注释现与实现一致（命令行为 gofmt 格式检查 -> go vet -> go build -> go test），不再声称"无 `*_test.go`、保留骨架"，也不再引用不存在的 `docs/ci-build-pipeline.md`；Format step 已列入 CI。文档一致性检查器仍只扫 markdown 链接、不扫代码注释里的路径与数量声明，这类工具盲区本身仍在（工具改进见建议 10）。

**没有发现任何阻断级违规或升级触发**（无 diff、无契约、无高风险变更在放行），不出具合规失败判定；以下全部为修改建议。蓝图覆盖处置见第七节。

---

## 二、证据总表（D1~D12 逐维核对）

| 维度 | 判定 | 证据 |
| --- | --- | --- |
| D1 静态门 | ⚠️ 部分 | CI `.github/workflows/ci.yml` 有 Format/Vet/Build/Test 四步；本地实测 `go vet/build/test ./...` 均 rc=0、8 包 ok，`gofmt -l` 命中 0（S4）。缺 golangci-lint 类风格门 |
| D2 单元测试 | ✅ 达标 | 14 个受版本控制的 `*_test.go`，单文件 2~19 处真实断言、零 `t.Skip`；`static_risk_check.py` 实跑 0 空断言 / 0 跳过（S4/S7） |
| D3 属性测试 | ⚠️ 部分 | `pkg/canary/properties_test.go`、`internal/dispatch/snapshot_properties_test.go` 已落并经 `go test ./...` 实跑 PASS（round-trip / 不变量 / 幂等 / 等价，各 600/300 次迭代）；生成器为自写 `math/rand` 确定性序列，survey `test_types.property.dep=[]`——无 gopter/rapid 属性库依赖，未与被测代码作者 bias 完全解耦（§4.4） |
| D4 E2E / verify 资产 | ⚠️ 部分 | survey `verify_asset=['verify.yaml']`；manifest 有 `build: make build`、`start: make start-dev`、`done:`（`go test ./...` + healthz + 证据落点），但 done 仅到 build/health，无真实任务下发流的外部证据；`test_types.e2e` 的 dep/dir 全空（无 playwright/cypress） |
| D5 差分测试 | ⛔ 当前不适用 | 无"可并行运行的旧实现"（见 S6），非缺口 |
| D6 CI 边界 | ⚠️ 部分 | 单一 verify job 顺序跑 Format→Vet→Build→Test；有 L0 验证 / L1 发布分层（`ci.yml`/`release.yml`），但无 cheap-first 分层、无提交边界重门 |
| D7 证据协议 | ❌ 缺失 | 无 `Verified:`/`Evidence:` trailer 约定（`git log --grep` 的 13 条命中均为正文提及，合规 trailer 0 条，S8）；无证据落点规范 |
| D8 验证戳 | ⚠️ 部分 | `governance/redlines.yaml` 已配 `thresholds.verification_stamp`（lookback 50 / min_ratio 0.8），但 survey `stamped=0, total=20, ratio=0.0`（S3/S8），无钩子实装生成戳；证据由 `verification_gate_check.py` 机检 |
| D9 判卷独立性 | ⚠️ 部分 | `REVIEW.md` 已存在（6 条判卷条目 + 五条独立性机制逐项标注）并列 `protected_paths`，但无 commit 绑定评审记录、无 base 分支取规则的自动化实装 |
| D10 升级策略 | ⚠️ 部分 | `governance/redlines.yaml` 已配 `max_consecutive_gate_failures: 3`，但无钩子实装连续失败计数与转人执行 |
| D11 flaky 治理 | ✅ 达标 | `static_risk_check.py` 对 14 个测试路径全量实跑 rc=0、0 命中（S7）：无 sleep/rerun/skip 信号。未接入 CI 常驻门 |
| D12 漏检回流 | ❌ 缺失 | 无漏检→规则转化流程、无判卷清单修剪机制（`governance/golden-set.md` 已存在但无持续度量实装） |

---

## 三、关键证据（可复查）

**S1 — CI 注释与实现的一致性（runner 特有）**
`ci.yml` 顶部注释现状：
```
# 命令: gofmt 格式检查 -> go vet ./... -> go build ./... -> go test ./...
# runner 不依赖其他同仓，单 checkout。
```
实测：`git ls-files '*_test.go'` = **14 个**，`go test ./...` = rc=0、8 包 ok（S4）。注释所列命令序列与 CI 的 Format/Vet/Build/Test 四步一致，原失实数量声明与死链引用已不在注释中。

**S2 — CI 门禁清单**：`.github/workflows/ci.yml` 有 Format / Vet / Build / Test 四步；`release.yml` 为 L1 发布层（release 事件 / workflow_dispatch dry-run，build.sh 打包）。全仓 `.github/` grep `golangci|coverage|mutation|gosec|trivy|secret|dependabot|type-check` 无命中。CI 未定义任何"会话内验证动作"的拦截谓词，提交不被"是否已跑验证"拦。

**S3 — survey 摘要**：`verify_asset=['verify.yaml']`；`ci.step_keywords={".github/workflows":["test","build"]}`；`test_types.e2e/property/differential` 全空（仅读 go.mod，无属性测试库/e2e 框架依赖）；`verification_stamp={lookback:50, stamped:0, total:20, ratio=0.0}`。

**S4 — 静态门实测**：`gofmt -l $(git ls-files '*.go')` 命中 **0**；`go vet ./...` rc=0；`go build ./...` rc=0；`go test ./...` rc=0。14 个受版本控制测试文件断言数：pipelinerun_types=3、handler=11、upgrade_job=10、pipelinerun_cancel=13、pipelinerun_controller=7、rollout_controller=2、cancel_handler=10、rerun_handler=16、snapshot=5、engine=19、client=11、credential=9、health=7、logstream=9；零 `t.Skip`。另有 2 个未入库属性测试文件（canary 600 次 / snapshot 300 次迭代）随 `go test ./...` 实跑通过。

**S5 — 文档一致性 + 工具盲区**：`doc_consistency_check.py --root .` = PASS（no dead links / conflict markers / orphans）。`docs/ci-build-pipeline.md` 在仓库中仍不存在（`docs/` 下仅 `design/README.md`），但已不在 CI 注释引用中。扫描器只扫 markdown 链接、不扫代码注释里的路径与数量声明——盲区仍在，不计检查器误报，但属工具改进点（建议 10）。

**S6 — 差分测试适用前提核查**：`api/v1alpha1/` 的 `v1alpha1` 是 CRD API 版本标识（gateway_payloads.go / protocol.go / pipelinerun_types.go 等），非"旧系统实现"；`internal/dispatch/snapshot.go` 是业务状态快照对象，非 golden/snapshot 差分测试资产；无 legacy/rewrite/migration 双跑特征。→ **无可并行旧实现**，§4.9 当前不适用。

**S7 — flaky 信号实跑（`static_risk_check.py`）**：以 14 个测试路径的全量行作为新增行构造 diff 实跑，rc=0，输出 `PASS (no skip marks / empty catches / empty asserts in added lines)`。口径说明：这是把存量测试全量行当新增行扫描的结果，反映**存量**质量——0 命中说明测试路径没有 sleep 等待、重跑或跳过反模式。此结论由检查器实跑给出，非相邻粗扫顶替。

**S8 — 验证戳真相**：`git log --all --grep='Verified:'` 计 13 条，但 `git log --pretty='%(trailers:key=Verified,valueonly)'` 全空——13 条均为 commit 正文提及字样，非合规 trailer。survey 按 trailer 口径计 `stamped=0, total=20, ratio=0.0`（S3）。结论：合规验证戳覆盖率 0。

---

## 四、修改建议（按 §3 阶段归属排序）

> 每条建议标题的阶段与其【缺口】行 D 维度的权威阶段一致（P0：D1/D7/D10；P1：D4/D8/D9；P2：D3/D5/D11/D12）。跨阶段维度拆为独立建议。机器推算仅供参考。

### 建议 1（P0）CI 补风格门并纳管注释防回退
- 【缺口】D1 静态门不完整：CI 已有 Format/Vet/Build/Test 四步、`gofmt -l` 命中 0，但无 golangci-lint 类风格门；注释已与实现一致，需防回退。
- 【证据】S1 + S2 + S5；`gofmt -l` 命中 0 说明存量干净，开门禁无需返工。
- 【建议改动】在 `ci.yml` 现有 Format step 之上补 `golangci-lint` 必需 step（风格门）；把 `ci.yml` 注释与 `.github/` 列入 `review_required_paths`，防注释被改回失实状态、门禁 step 被删。CI 门来源用组织级 required check 钉死目标分支。
- 【对抗推演】AI 同 PR 改 workflow 删 step 或改注释掩盖漂移（RT-02/RT-17）→ `.github/` 列入 `review_required_paths` + CODEOWNERS，从目标分支取门禁。
- 【建议可信度】已验证模式（RT-02、D1 判据、S1/S4 实测）。
- 【由谁决策】工程（CI 负责人）；workflow 改动须人审批。
- 【严重度】中。

### 建议 2（P0）建立证据协议（结论附退出码/日志）
- 【缺口】D7 缺失：无 `Verified:`/`Evidence:` trailer 约定，结论可自述、无外部证据落点。
- 【证据】S8（合规 trailer 0 条）；S3。
- 【建议改动】定义证据协议：每条验证结论附退出码 / 日志路径 / 截图路径，由 harness 收集、**agent 只能引用不能转述**（§0 核心措辞）；"本地先跑"是**与 agent 无关的能力**：改动交给下游前自动跑 test/build/lint 并留痕，通用落点是 git `pre-commit` hook，各 agent 生态的完成时事件（如 Claude 的 Stop hook / `/goal`）只作**可选加速器示例、不作能力判据**；证据包格式对齐 `schemas.md` 的证据类型。验证戳落地见建议 5。此建议的价值有 §0 实证支撑：独立 grader 按 rubric 判卷使任务成功率最高 **+10 分、最难任务收益最大**——判卷人与做题人分离是最便宜的提分手段，而该收益的前提正是结论有外部可复查证据、不靠自述。
- 【对抗推演】AI 转述"测试通过"而无日志（RT-05）→ 结论必须指向可复查的证据路径，缺证据按未通过处理。
- 【建议可信度】已验证模式（D7/§0 证据协议与 +10 分实证）。
- 【由谁决策】契约负责人 + 工程。
- 【严重度】中。

### 建议 3（P0）把连续失败转人阈值接到钩子（E-05）
- 【缺口】D10 部分：`max_consecutive_gate_failures=3` 已配在 `governance/redlines.yaml`，但无钩子实装连续失败计数与转人；agent 在门失败时可无限空转重跑。
- 【证据】redlines 阈值已配（3）；无计数/转人实装（第二节 D10 行）。
- 【建议改动】把 `max_consecutive_gate_failures=3` 接到提交钩子：同一门禁连续失败 ≤3 轮修不好即停止重试、转人；与 flaky 治理（建议 9）联动，超时/失败不靠重跑碰运气。
- 【对抗推演】AI 反复重跑门直到偶发绿（RT-16）→ 连续失败计数由 harness 记录、达阈值强制转人，不给 agent 自行清零的入口。
- 【建议可信度】已验证模式（D10/E-05）。
- 【由谁决策】契约负责人（阈值）+ 工程。
- 【严重度】中。

### 建议 4（P1）把 verify 资产的 done 延伸到真实任务下发流
- 【缺口】D4 部分：`verify.yaml` 已有 build/start/done 三字段声明，但 done 仅到 `go test` 与 healthz，无真实任务下发流的外部证据；e2e 依赖/目录为空。
- 【证据】S3 `verify_asset=['verify.yaml']`；done 仅到 build/health（S3）。
- 【建议改动】把 `verify.yaml` 的 done 延伸到真实系统：API/WS harness 驱动 WS 回连→任务下发→执行→结果回流，落响应体与带时间戳日志到 `evidence/`；`hands.driver` 给 agent"手和眼"，done 判据用验收/契约场景清单当 rubric（feature map）。runner 已有 `make build/start-dev/stop-dev`，填入成本低。**harness 自身须压测到稳定**（VP-01，它是全部下游验证的地基）。
- 【对抗推演】AI 写永远 exit 0 的 done 凑绿（RT-05）→ done 指向真实系统可观测状态（真实 WS 回连 + 任务状态），超时 = fail 不重试。
- 【建议可信度】已验证模式（D4/VP-01/§4.1）。
- 【由谁决策】工程 + 契约负责人（done 判据须人确认）。
- 【严重度】中。

### 建议 5（P1）把验证戳实装并先 observe，配套拦截谓词
- 【缺口】D8 部分：`governance/redlines.yaml` 已配 `verification_stamp` 阈值，但 20 commit 0 验证戳；且无门禁谓词，"是否跑过验证"不影响提交放行。
- 【证据】S3 ratio=0；S8（合规 trailer 0 条）；S2 全仓无会话内验证动作的拦截配置。
- 【建议改动】分两套机制并用（§4.2 + §4.5）：
  - **验证戳（结果标记）**：提交工具链自动盖 `Verified: <e2e|unit|property|differential|manual|none>`，`none` 是合法值，使未验证提交可查询；`redlines.yaml` 的 `thresholds.verification_stamp` 已配，白名单外 method 按无效戳计。
  - **门禁灰度（off→observe→enforce 三档）**：按 VP-05 从 off（先确认开关无害）→ observe（只记录本会被拦的提交、不拦）→ enforce（拦截；commit 可附豁免理由；**同一会话内被拦两次后下一次放行**作逃生门，防 agent 死循环）。当前档位=off（无门）。
  - **拦截谓词（门拦什么，须与三档一起定义）**：谓词拦的是**该次提交所在会话内没有执行过约定验证动作的提交**（落地时由项目定义具体命令，如把 `go vet && go test` 绑到提交完成钩子，不写死某个 slash command）；判定依据是**会话内事实**（有没有跑过该动作），不是 commit message 上的戳——戳是结果标记（含 `none`），谓词是门禁判定拦不拦的依据，两套并用。只盖戳不定义谓词，等于给了开关没接电线。
- 【对抗推演】AI 滥盖 `Verified: e2e`（RT-11）→ 戳由工具链按实际跑过的门生成、白名单外 method 按无效戳计；AI 靠改 commit message 伪造"已验证"绕过门（RT-17 同型：变更不能修改审判自己的标准）→ 谓词只看会话内是否真跑过验证动作、不受 message 戳影响，且 hook 从目标分支取。
- 【建议可信度】已验证模式（D8/R-VER-008/§4.2/§4.5 含拦截谓词）。
- 【由谁决策】工程（提交链 + hook）+ 契约负责人（阈值与谓词动作）。
- 【严重度】中。

### 建议 6（P1）补覆盖率与变异门禁
- 【缺口】D2/D6 深度不足：CI 只跑 test 不度量覆盖率，无变异测试。
- 【证据】S2 无 coverage/mutation step；S4 显示 14 测试文件有断言但无覆盖率数据。
- 【建议改动】先接 `go test -coverprofile` 阈值门（cheap-first），成熟后引入 go 变异测试（如 go-mutesting）在提交边界跑；阈值写 redlines。
- 【对抗推演】AI 删测试凑绿（RT-08）→ 覆盖率 + 变异分数双门配合 R-IMP-003。
- 【建议可信度】已验证模式（RT-08、R-VER-001/002）。
- 【由谁决策】工程；阈值由契约负责人定。
- 【严重度】中。

### 建议 7（P1）把 REVIEW 判卷清单接到五条独立性机制
- 【缺口】D9 部分：`REVIEW.md` 已存在（6 条判卷条目 + 五条独立性机制逐项标注），属文档形态；清单标注的机制尚未在流程中实装——无 base 分支取规则的自动化、无评审绑定 commit、无多轮累积记录。
- 【证据】`REVIEW.md` 已存在（事实更新）；无 commit 绑定评审记录。
- 【建议改动】按 §4.3 把 `REVIEW.md` 接到**五子机制**：①规则列入 `protected_paths`、CI 从 base 分支读；②评审绑定 commit、推新提交作废；③code owner 写检查并迭代；④拉人须说 why（触发哪条规则、什么证据）；⑤**单一 reviewer、多轮累积**——不堆叠第二个更贵的 reviewer，调优 REVIEW.md 本身，每轮喂前轮上下文与历史失败而非从头重查。这条建议的收益对应 §0 判卷独立性实证（独立 grader +10 分、最难任务收益最大）。
- 【对抗推演】AI 同 PR 改判卷规则自审自过 / 用陈旧评审给新代码背书（RT-17 覆盖①②）→ ①②服务端钉死来源 + commit 绑定；③④⑤防社会工程与"堆 reviewer 反而更贵却漏检"。
- 【建议可信度】已验证模式（VP-03/§4.3/RT-17）。
- 【由谁决策】工程 + code owner；清单入保护路径须人审批。
- 【严重度】中。

### 建议 8（P2）用独立属性库扩展已有属性测试
- 【缺口】D3 部分：`pkg/canary/properties_test.go`、`internal/dispatch/snapshot_properties_test.go` 已落并实跑 PASS，但用自写 `math/rand` 确定性生成器、无属性库依赖（survey `property.dep=[]`）；cancel/rerun 状态流转尚无属性约束。
- 【证据】S3 property.dep=[]（无 gopter/rapid）；两个 properties_test.go 已落并经 `go test ./...` 实跑。
- 【建议改动】在已有属性测试基础上按 §4.4 引入 rapid/gopter 类库与独立生成器：对 `pkg/canary` 权重计算（不变量：权重非负且和为 1）、`internal/dispatch/snapshot` 序列化（round-trip）、状态流转（幂等）等补齐约束；四类模式按被测对象择用：①round-trip ②不变量 ③幂等 ④等价。**spec 与实现漂移时约束比 spec 稳，属性测试仍可用**——重写/迁移场景尤其有效。
- 【对抗推演】AI 用同源 bias 输入生成（VP-02）→ 输入必须由属性库生成器独立产生，属性陈述人审固化。
- 【建议可信度】已验证模式（D3/VP-02/§4.4）。
- 【由谁决策】工程；属性陈述人审。
- 【严重度】低。

### 建议 9（P2）漏检回流双法 + 元验证 + flaky 常驻门
- 【缺口】D12 缺失，元验证（VP-07）机制未固化；D11 当前实跑达标但 `static_risk_check.py` 未接 CI 常驻门。
- 【证据】S7（实跑 0 命中）；`REVIEW.md` 与 `governance/golden-set.md` 已存在，但无 bug finder 回放记录、无持续度量实装。
- 【建议改动】把 S7 的 `static_risk_check.py` 接入 CI 常驻门（测试路径禁 sleep/rerun/skip），保持当前 0 命中状态不被回退。漏检→规则按 §4.7 **双法**并行：第一法三门槛（≥2 PR + ≥3 独立 agent 证伪 + 人审合入）；第二法用 3 个 bug finder 回放已知事故（≥2 命中才算可检测，**小 diff 上也被漏掉**即重点信号）。flaky 治理按 §4.6：根因修不好则删除该测试并写下删除理由。元验证按 §4.8：以 `governance/golden-set.md` 为底建 golden set（真实事故/revert + 体量相当干净对照），**每例附一句话答案（answer key），只有正确描述该 bug 的 finding 才计分**——否则"随便报一条就算命中"会让 recall 虚高；分阶段 recall（原始发现→验证后→终审分别统计）、发现分级（Important/Nit/Pre-existing）、**数据集隔离（tuning 与 fixed 分离）**、**调参到过拟合边缘即停**、例行修剪；持续度量 merged 后 revert 数 / maintainer 合入前拒绝数作为长期体温计。
- 【对抗推演】AI 对后续 flaky 测试加更多 sleep 反复重跑（RT-16）→ 测试路径静态禁 sleep/rerun（R-VER-009）+ 连续失败阈值（建议 3）；第二法防"规则从人已发现的模式归纳，却测不出机器能否复现发现"；数据集隔离防"调参即过拟合"无法察觉；一句话答案 + 只给正确描述计分防验证器靠宽口径虚报 recall。
- 【建议可信度】已验证模式（D12/VP-07/§4.7 双法、§4.8 含一句话答案评分口径、D11/R-VER-009 + S7 实跑）。
- 【由谁决策】工程 + 契约负责人。
- 【严重度】低。

### 建议 10（P2，工具改进）文档扫描覆盖代码注释 + CI 注释纳管
- 【缺口】文档一致性检查器判 PASS，但工具盲区仍在：它扫 markdown 链接，不扫代码注释里的路径引用与数量声明（S1/S5）；CI 注释虽已与实现一致，仍须纳管防回退。
- 【证据】S5（doc_consistency PASS）；S1（注释与 14 测试文件现状一致，盲区仍在）。
- 【建议改动】扩展文档扫描器覆盖源码/CI 配置注释中的路径引用与数量声明（或加一条专用断言核对 CI 注释与实际测试文件数）；把 `.github/workflows/*.yml` 列入 `review_required_paths`，注释改动须人审。属工具改进建议，由使用者决定是否回流 skill。
- 【对抗推演】无（工具精确性改进，非治理规则）。
- 【建议可信度】已验证模式（S1/S5 路径与数量可复查）。
- 【由谁决策】审计工具维护者 / skill 使用者 + 工程（注释纳管）。
- 【严重度】低。

---

## 五、确认为达标的维度（附证据，避免只报缺口）

- **D2 单元测试规模与质量**：14 个受版本控制测试文件、单文件 2~19 处真实断言、零 `t.Skip`，`static_risk_check.py` 实跑 0 空断言（S4/S7）。
- **D11 flaky 纪律**：`static_risk_check.py` 全量实跑 0 命中，无 sleep/rerun/skip 反模式（S7）——优于同平台 hub 的 6 处命中。
- **D1 格式一致性**：`gofmt -l` 命中 0，CI 已有 Format step（S4）。
- **D5 当前不适用**：无可并行旧实现（S6），非缺口。

---

## 六、工程化建议：人工核对 → 机器检查

| 人工核对项 | 升级条件 |
| --- | --- |
| 格式/风格一致性（建议1） | `gofmt -l` 已做成 CI 必需 step；golangci-lint 可立即升级为必需 step |
| CI 注释真实性（建议1/10） | 注释列入 review_required_paths；路径存在性/测试数一致性做成专用断言 |
| 证据协议（建议2） | 证据包格式对齐 schemas.md 后由 harness 校验落点存在性 |
| 升级阈值（建议3） | `max_consecutive_gate_failures` 已在 redlines 配值，接到钩子后由 harness 计数强制转人 |
| 验证戳覆盖（建议5） | `thresholds.verification_stamp` 已配，`verification_gate_check.py --repo` 可机检 |
| 拦截谓词（建议5） | 谓词动作绑 hook 后，查会话内事实（非 commit message 戳）属人工核；机检管不到 |
| verify 资产存在性（建议4） | survey `verify_asset=['verify.yaml']` 已可机检；done 内容正确性仍需人核 |
| 覆盖率/变异（建议6） | CI 接报告后 `ci_gate_check.py` 机检 |
| 判卷独立性① ②（建议7） | 查受保护路径 + CI 从目标分支取（RT-01 同机制） |
| 判卷独立性③ ④ ⑤（建议7） | owner 写检查 / say-why / 多轮累积运行形态属人工核对与社会工程 |
| flaky 信号（建议9） | `static_risk_check.py` 已可机检（S7 实跑 0 命中）；接入 CI 常驻门防回退 |
| 漏检双法（建议9） | 第二法"≥2 命中 + 小 diff 漏检"可做成 bug finder 回放作业 |
| 元验证评分口径（建议9） | golden set 一句话答案 + 只给正确描述 bug 的 finding 计分属人工核口径，机检不做语义评分 |

---

## 七、蓝图覆盖表（§6 强制，防"漏带蓝图"）

> 处置三选一：`已建议`（去向指向建议编号，或显式标注「详见蓝图 §4.x（正文要点化，细节不重复）」）/ `当前不适用`（附理由）/ `待建设`（标 P0/P1/P2）。D 表（第二节）答"项目缺什么"，本表答"蓝图每项去了哪"，两表齐才闭环。覆盖范围含 §0/§1/§3/§4 全节 + VP。§4.3 五子机制、§4.4 四模式+spec 漂移、§4.7 双法、§4.10 四子项逐项拆行。§0 证据措辞与 +10 分实证数字、§3"能力与平台适配器分离"口径、§4.5 拦截谓词、§4.8 golden set 评分口径属机检管不到的语义项，人工对照原文核。

| 蓝图条目 | 处置 | 去向（可核） |
| --- | --- | --- |
| §0 三个事实与证据协议（独立 grader 按 rubric 判卷 **+10 分、最难任务收益最大** / 验证即固定资产 / 39 项命中 3~10；agent 自述不算证据、评审绑 commit；**证据由外部 harness 收集、agent 只能引用不能转述**；要点化保留 +10 分数字与此措辞） | 已建议 | 建议 2/5/7；详见蓝图 §0（正文要点化，细节不重复） |
| §1 三种测试选择依据（E2E 难欺骗 / 属性独立生成器 / 差分旧系统 oracle） | 已建议 | 建议 4/8（E2E verify 资产、属性测试）；差分见 §4.9 行当前不适用；详见蓝图 §1（正文要点化，细节不重复） |
| §1 警告① flaky 训练重跑 | 已建议 | 建议 9（R-VER-009 + E-05，VP-06；S7 实跑 0 命中，接常驻门防回退） |
| §1 警告② 慢测试降低验证频次 | 待建设（P2） | 当前无慢测试；后续新增门按 cheap-first 评估，重门放提交边界 |
| §1 警告③ 重测试放提交边界 | 已建议 | 建议 6（变异在提交边界）、建议 5（off→observe→enforce） |
| §3 建设顺序 P0→P1→P2（cheap-first：开 PR 前本地 test/build/lint 全绿，重门在提交边界；**"本地先跑"是 agent 无关的能力——改动交给下游前自动跑 test/build/lint 并留痕，通用落点是 git `pre-commit` hook；各 agent 生态完成时事件如 Claude Stop hook / `/goal` 只作可选加速器示例、不作能力判据**） | 已建议 | 建议 1/2/4/5；本报告建议标题阶段按 §3 权威表标注；详见蓝图 §3（正文要点化，细节不重复） |
| §4.1 verify 资产（含 hands 手和眼、feature map 当 rubric、harness 压测稳定） | 已建议 | 建议 4（含 hands.driver、feature map 当 rubric、harness 压测）；详见蓝图 §4.1（正文要点化，细节不重复） |
| §4.2 验证戳（含 none、白名单外无效） | 已建议 | 建议 5（P1） |
| §4.3 ① 规则从 base 分支读 | 已建议 | 建议 7（P1） |
| §4.3 ② 评审绑定 commit、推新作废 | 已建议 | 建议 7（P1） |
| §4.3 ③ code owner 写检查 | 已建议 | 建议 7（P1） |
| §4.3 ④ 拉人须说 why | 已建议 | 建议 7（P1） |
| §4.3 ⑤ 单一 reviewer 多轮累积、不堆叠 | 已建议 | 建议 7（P1） |
| §4.4 ① round-trip | 已建议 | 建议 8（P2） |
| §4.4 ② 不变量 | 已建议 | 建议 8（P2） |
| §4.4 ③ 幂等 | 已建议 | 建议 8（P2） |
| §4.4 ④ 等价 | 已建议 | 建议 8（P2） |
| §4.4 spec 漂移时仍可靠（约束比 spec 稳，重写场景尤其有效） | 已建议 | 建议 8（P2） |
| §4.5 门禁灰度 off→observe→enforce 三档（含 off 档、误拦日志、被拦两次后放行）**+ 拦截谓词**（门拦"会话内未执行约定验证动作的提交"，与验证戳互补；要点化保留"拦什么"） | 已建议 | 建议 5（P1，三档 + 谓词均在正文定义） |
| §4.6 flaky 治理（禁 sleep/rerun、删测试写理由） | 已建议 | 建议 9（P2）；详见蓝图 §4.6（正文要点化，细节不重复） |
| §4.7 第一法：三门槛（≥2 PR + ≥3 agent 证伪 + 人审合入） | 已建议 | 建议 9（P2） |
| §4.7 第二法：3 bug finder 回放已知事故 ≥2 命中、小 diff 漏检重点 | 已建议 | 建议 9（P2） |
| §4.8 元验证（持续度量 merged 后 revert 数 / maintainer 合入前拒绝数 / 干净变更对照、golden set **一句话答案 + 只有正确描述该 bug 的发现才得分**、分阶段 recall、Important/Nit/Pre-existing、数据集隔离 tuning vs fixed、调参到过拟合边缘即停、修剪；要点化保留评分口径） | 已建议 | 建议 9（P2，一句话答案与计分口径在正文定义） |
| §4.9 差分测试（oracle/采样、归一化、允许变更白名单、收敛判据） | **当前不适用**：无"可并行运行的旧实现"——`v1alpha1` 是 CRD API 版本标识、`internal/dispatch/snapshot.go` 是业务状态快照对象，均非旧系统实现对拍（S6）；将来若引入双写/重写迁移再启用 | — |
| §4.10 ① 基线管理（protected_paths / 人确认首版 / 稳定时刻 / sha256） | **当前不适用**：runner 为 Go agent 执行器（K8s controller + WebSocket + executor），无浏览器/桌面/移动前端交互界面，无截图基线可比（§4.10 适用前提不满足）；将来若引入前端界面再启用 | — |
| §4.10 ② 比对协议（baseline/actual sha256 + diff 指标 + 容差 + 漂移处置分岔） | **当前不适用**：纯后端执行器无前端界面、无视觉比对场景；适用前提不满足 | — |
| §4.10 ③ 异常态驱动清单（网络失败/空数据/超时/权限/弹窗抽屉各态 + 截图↔用例映射） | **当前不适用**：无 UI 交互与截图，异常态由 API/WS 测试覆盖、无界面态映射；适用前提不满足 | — |
| §4.10 ④ 截图一等证据（schemas screenshot 类型 + sha256 + 场景 id） | **当前不适用**：无前端截图产物，证据类型为日志/退出码；适用前提不满足 | — |
| VP-01 verify harness 是地基 | 已覆盖 | §4.1 行 / 建议 4 |
| VP-02 三种测试选择依据 | 已覆盖 | §4.4 行 / 建议 8；E2E 见建议 4 |
| VP-03 判卷独立性 | 已覆盖 | §4.3 五子机制 / 建议 7 |
| VP-04 cheap-first | 已覆盖 | §3 行 / 建议 1/4/6 |
| VP-05 observe→enforce | 已覆盖 | §4.5 行 / 建议 5 |
| VP-06 flaky 铁腕治理 | 已覆盖 | §4.6 行 / 建议 9 |
| VP-07 漏检回流+元验证+修剪 | 已覆盖 | §4.7 双法 / §4.8 行 / 建议 9 |

**覆盖自检**：§0/§1/§3/§4 全节均有处置；§4.1~4.10 十项全处置（§4.1~4.8 八项已建议 + §4.9 当前不适用附理由 + §4.10 四子项均当前不适用附理由）；§4.4 四模式 + spec 漂移拆五行、§4.3 五子、§4.7 双法、§4.10 四子项逐项拆行；VP-01~07 全部映射；机检管不到的语义项按蓝图原文人工核并写入对应建议正文与覆盖行——§0"agent 只能引用不能转述"与 +10 分/最难任务收益最大（建议 2/7）、§3 能力与平台适配器分离（改动交给下游前自动跑并留痕、git `pre-commit` 通用落点、各 agent 完成时事件仅作可选加速器）（建议 2）、§4.5 拦截谓词（建议 5）、§4.8 golden set 一句话答案 + 只有正确描述该 bug 的发现才得分（建议 9）；所有去向仅用建议编号或「详见蓝图 §4.x」，无不可核自证断言；建议标题阶段与 D 表判定按 §3 权威表对齐。已由 `report_gate.sh` 单一入口机检确认。

---

## 八、归档与回流

- 本报告归档于 runner 仓库 `audits/`，为审计自有产物，未修改任何被审源码/配置/CI。
- 未发现 `attack-cases.md` 案例库未收录的新型绕过手法，**无晋升建议**。
- 全部结论为建议模式输出，**非合规判定**；采纳与否由人决策。
