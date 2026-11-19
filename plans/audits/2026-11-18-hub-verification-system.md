# 审计报告：hub 仓库验证体系体检

- 审计对象：`software-distribution-platform-hub`（main@d313657，工作区有未提交改动：`verify.yaml` / `REVIEW.md` / `governance/` / `properties_test.go`，以及格式归零、CI Format step、测试路径条件等待）
- 审计日期：2026-11-18
- 审计模式：**建议模式**——仓库有 `governance/redlines.yaml`（含阈值 / 保护路径 / 静态风险 allowlist），但 `required_rules` 未设、无目标契约。按采纳边界，本报告为**建议清单，非合规判定**；"未声明采纳"是边界说明，不构成违规。
- 审计类型：验证体系 survey（`verification_gate_check.py --survey`）+ 静态门实测 + 文档一致性 + flaky 实跑（`static_risk_check.py`，正向 + 反向验证）+ 人工核对
- 独立性声明：**非独立验证**——同一会话内由执行审查的 Agent 兼任，未经干净会话独立复核；高风险结论须人精读原始证据。
- 证据口径：结论均附命令输出 / 文件路径 / 字段值。survey 为形态探测，miss 不构成违规。机器推算仅供参考，关键断言须人核原文。
- 覆盖规范：按 harness-workflow `verification-program.md` §6，覆盖表逐条处置 §0/§1/§3/§4 全节与 VP-01~07，每条「已建议」去向可核，并列子项拆行；§0 证据措辞与实证数字（+10 分/最难任务收益最大）、§3 能力+平台适配器分离口径、§4.5 拦截谓词、§4.8 实证评分口径（golden set 一句话答案/只有正确描述该 bug 才得分）等"机检管不到"的语义项按蓝图原文人工核；报告落盘前经 `report_gate.sh` 单一入口机检（一次跑完 `coverage_table_check.py` + `stage_consistency_check.py` 并聚合退出码）。

---

## 一、结论摘要

hub 仓库已有**可运行的基础静态门**（CI 上 Format / Vet / Build / Test 四步、本地实测全绿），有 81 个测试文件、覆盖主要 service/repository 包；CI 有 Format step 且全仓 `gofmt -l` 输出为空，测试路径无裸 sleep、等待由显式条件承担——这些是真实且可复查的优点。但按 D1~D12 诊断，体系整体仍处于**建设早期到部分实装之间**：D1 静态门、D2 单元测试规模、D11 flaky 治理达标；D3 属性测试、D4 verify 资产、D8 验证戳、D9 判卷独立性、D10 升级策略有骨架或配置但无真跑 / 无实装，判 ⚠️ 部分；D7 证据协议、D12 漏检回流仍缺。按 §3 阶段归属表：P0 维度里 D1 达标、D7 缺失、D10 部分；P1 维度 D4/D8/D9 均为部分；P2 维度里 D3/D11 已具备、D5 当前不适用、D12 缺失。当前最需注意的风险是：**`verify.yaml` 的 done 判据停在 build/vet/test 与 `/health` 健康检查，尚未跑真实业务流并落外部响应证据**——声明齐不等于跑通过，后面的门会拦在空转上。

`static_risk_check.py` 正向实跑 rc=0、反向插入 sleep 实跑 rc=1（S7 / S8），证明测试路径的 flaky 禁用门仍有效：`static_risk_allowlist` 只放行带理由的 DSN 条件跳过，不放行任何 sleep 等待。

**没有发现任何阻断级违规或升级触发**（无待放行 diff、无已采纳必需规则），不出具合规失败判定；以下全部为修改建议。蓝图覆盖处置见第七节。

---

## 二、证据总表（D1~D12 逐维核对）

| 维度 | 判定 | 证据 |
| --- | --- | --- |
| D1 静态门 | ✅ 达标 | CI `.github/workflows/ci.yml` 有 Format / Vet / Build / Test 四步；本地实测 `go vet/build/test ./...` 均 rc=0、33 包 ok；`gofmt -l $(git ls-files '*.go')` 输出为空（S1 / S4） |
| D2 单元测试 | ✅ 达标 | 81 个 `*_test.go`，10+ service 包为主；`static_risk_check.py` 正向实跑 0 空断言、1 处带理由的 DSN 条件跳过走 allowlist（S7） |
| D3 属性测试 | ⚠️ 部分 | `internal/coordination/properties_test.go` 有独立生成器写的不变量 / 幂等属性、`go test` 通过；但 survey `test_types.property.dep=[]`（go.mod 仅 testify，无 quickcheck 家族依赖），属性测试未进 CI 常驻门、survey 不识别 |
| D4 E2E / verify 资产 | ⚠️ 部分 | survey `verify_asset=['verify.yaml']`（S3）；build/start/done 三字段齐、done 含 vet/test 与 `/health` curl；无 e2e 目录 / 依赖特征，done 停在静态门与健康检查、无业务流真跑与外部证据 |
| D5 差分测试 | ⛔ 当前不适用 | 无"可并行运行的旧实现"（见 S6），非缺口 |
| D6 CI 边界 | ⚠️ 部分 | 单一 job 顺序跑 Format→Vet→Build→Test；无 cheap-first 分层、无提交边界重门 |
| D7 证据协议 | ❌ 缺失 | 无 `Verified:`/`Evidence:` trailer 约定（git 全历史 `Verified:` 计数=0）；无证据落点规范 |
| D8 验证戳 | ⚠️ 部分 | survey `stamped=0, total=31, ratio=0.0`；`governance/redlines.yaml` 配了 `thresholds.verification_stamp`（lookback 50 / min_ratio 0.8），但无提交钩子实装、无戳生成（`verification_gate_check.py` 口径，S3） |
| D9 判卷独立性 | ⚠️ 部分 | `REVIEW.md` 有 7 条判卷条目 + 五条独立性机制、`governance/golden-set.md` 有评分骨架；未接 base 分支取规则与 commit 绑定实装，运行形态属人工核对 |
| D10 升级策略 | ⚠️ 部分 | `governance/redlines.yaml` 配 `max_consecutive_gate_failures=3`；无 harness 计数与连续失败转人实装 |
| D11 flaky 治理 | ✅ 达标 | 测试路径无 `time.Sleep` / rerun 装饰器；等待由 `require.Eventually`、`require.Never`、`runtime.Gosched()` 与 DB 时钟条件轮询承担；唯一 `t.Skip` 带 DSN 未设理由并列 `static_risk_allowlist`。`static_risk_check.py` 正向 rc=0（S7）、反向新增 sleep rc=1（S8），门仍有效 |
| D12 漏检回流 | ❌ 缺失 | golden-set 与 REVIEW 清单是骨架；无漏检→规则转化实装、无 bug finder 回放记录与持续度量 |

---

## 三、关键证据（可复查）

**S1 — 格式门现状**：`gofmt -l $(git ls-files '*.go')` 输出为空（全仓 0 命中）；CI `.github/workflows/ci.yml` 的 Format step（`test -z "$(gofmt -l $(git ls-files '*.go'))"`）位于 Vet 之前，构成提交侧格式门。`governance/redlines.yaml` 把 `.github/workflows/**` 与 `governance/**` 列入 `protected_paths`，workflow 改动须人审。

**S2 — CI 门禁清单**：`.github/workflows/ci.yml` 有 Format / Vet / Build / Test 四个 step；全仓 `.github/` grep `golangci|coverage|mutation|gosec|trivy|secret|dependabot|type-check` 无命中（唯一额外命中是 Format step 的 `gofmt`）。CI 未定义任何"会话内验证动作"的拦截谓词，提交不被"是否已跑验证"拦。

**S3 — survey 摘要**：`verify_asset=['verify.yaml']`；`ci.step_keywords={".github/workflows":["test","build"]}`；`test_types.e2e/property/differential` 空（仅读 go.mod 命中 testify）；`verification_stamp={lookback:50, stamped:0, total:31, ratio=0.0}`。

**S4 — 静态门实测**：`go vet ./...` rc=0；`go build ./...` rc=0；`go test ./...` rc=0，33 行 `ok`。

**S5 — 文档一致性**：1 条死链 `keycloak/README.md -> ./examples`，**判定误报**——vendored 第三方 chart（maintainer 为上游、`.helmignore` 本就忽略 `examples/`），不计 hub 缺陷。建议扫描器排除 vendored 路径。

**S6 — 差分测试适用前提核查**：`migrations/` 为破坏性 schema 演进（0015 drop legacy columns、0017 列宽修复），旧 schema 不并行运行；`approval_*` 是业务审批流非 approval testing；`internal/runnerproto/testdata/contract/*.json` 是契约快照样例非旧实现对拍。→ **无可并行旧实现**，§4.9 当前不适用。

**S7 — flaky 信号正向实跑（`static_risk_check.py`）**：以全部测试路径（81 个 `*_test.go`）的行作为新增行构造 diff，`GOVERNANCE_DIR=governance` 带 allowlist 实跑，rc=0（PASS）。测试路径当前无 `time.Sleep`、rerun 装饰器与重试配置：等待由 `require.Eventually`（`internal/coordination/lease_pg_test.go`、`internal/run/service/pipeline_run_dispatch_test.go`）、`require.Never`（`internal/notification/dispatch_test.go` 负向断言）、`runtime.Gosched()`（并发交错）与 DB 时钟条件轮询承担。`internal/coordination/lease_pg_test.go:27` 的 `t.Skip` 是唯一跳过，条件为 `COORDINATION_TEST_DSN` 未设、带理由，且列入 `static_risk_allowlist`，属人审豁免。口径：这是覆盖全部测试路径的构造式扫描，反映测试路径当前形态；allowlist 只豁免该条带理由的 DSN 跳过，不豁免任何 sleep 等待。

**S8 — flaky 门反向验证（`static_risk_check.py`）**：在 `internal/coordination/lease_pg_test.go` 的构造 diff 中插入一处 `time.Sleep(5 * time.Millisecond)`，同样 `GOVERNANCE_DIR=governance` 实跑 → rc=1，输出 `STATIC-RISK[flaky] sleep-based wait in tests (flaky root; use explicit condition waits) at internal/coordination/lease_pg_test.go:181`。与 S7 的 rc=0 对照，证明 `static_risk_allowlist` 只放行带理由的 DSN skip，新增 sleep 仍被门拦下。

---

## 四、修改建议（按 §3 阶段归属排序）

> 每条建议标题的阶段与其【缺口】行 D 维度的权威阶段一致（P0：D1/D7/D10；P1：D4/D8/D9；P2：D3/D5/D11/D12）。跨阶段维度拆为独立建议。机器推算仅供参考。

### 建议 1（P0）守住格式门并防回退
- 【缺口】D1 已达标，风险在回退：workflow 改动删 Format step、或 `protected_paths` 收窄，会让格式门失效而无人察觉。
- 【证据】S1 + S2；`governance/redlines.yaml` 的 `protected_paths` 含 `.github/workflows/**` 与 `governance/**`。
- 【建议改动】保持 CI Format step 在 Vet 之前、runner 从目标分支取 workflow；`.github/workflows/**` 留在 `protected_paths` 且用 CODEOWNERS 钉死来源；`REVIEW.md` H1 条目每次评审核对 Format/Vet/Build/Test 四步未被删、未改 `continue-on-error`；定期 `gofmt -l $(git ls-files '*.go')` 巡检输出为空。
- 【对抗推演】AI 同 PR 改 workflow 删 step（RT-02/RT-17）→ `.github/` 列入 `review_required_paths` + CODEOWNERS，从目标分支取门禁。
- 【建议可信度】已验证模式（RT-02、D1 判据）。
- 【由谁决策】工程（CI 负责人）；workflow 改动须人审批。
- 【严重度】中。

### 建议 2（P0）建立证据协议（结论附退出码/日志）
- 【缺口】D7 缺失：无 `Verified:`/`Evidence:` trailer 约定，结论可自述、无外部证据落点。
- 【证据】git 全历史 `Verified:` 计数=0（第三节摘要）；S3。
- 【建议改动】定义证据协议：每条验证结论附退出码 / 日志路径 / 截图路径，由 harness 收集、**agent 只能引用不能转述**（§0 核心措辞）；"本地先跑"是 **agent 无关的能力**——改动交给下游前自动跑 test/build/lint 并留痕，通用落点是 git `pre-commit` hook；各 agent 生态的完成时事件（如 Claude 的 Stop hook / `/goal` 绑定 passing test suite）只作**可选加速器示例**，不作能力判据，未用某 agent 的某命令不等于缺此能力。证据包格式对齐 `schemas.md` 的证据类型。验证戳落地见建议 5。此建议的价值有 §0 实证支撑：独立 grader 按 rubric 判卷使任务成功率最高 **+10 分、最难任务收益最大**——判卷人与做题人分离是最便宜的提分手段，而该收益的前提正是结论有外部可复查证据、不靠自述。
- 【对抗推演】AI 转述"测试通过"而无日志（RT-05）→ 结论必须指向可复查的证据路径，缺证据按未通过处理。
- 【建议可信度】已验证模式（D7/§0 证据协议与 +10 分实证）。
- 【由谁决策】契约负责人 + 工程。
- 【严重度】中。

### 建议 3（P0）把连续失败转人阈值接成实装（E-05）
- 【缺口】D10 部分：`governance/redlines.yaml` 有 `max_consecutive_gate_failures=3`，但无 harness 计数与转人实装，门失败时 agent 仍可无限空转重跑。
- 【证据】D10 行；`governance/redlines.yaml` 的 `thresholds.max_consecutive_gate_failures=3`。
- 【建议改动】以 `max_consecutive_gate_failures=3` 为准接入 harness 计数：同一门禁连续失败 ≤3 轮修不好即停止重试、转人；与 flaky 治理（建议 9）联动，超时/失败不靠重跑碰运气。
- 【对抗推演】AI 反复重跑门直到偶发绿（RT-16）→ 连续失败计数由 harness 记录、达阈值强制转人，不给 agent 自行清零的入口。
- 【建议可信度】已验证模式（D10/E-05）。
- 【由谁决策】契约负责人（阈值）+ 工程。
- 【严重度】中。

### 建议 4（P1）补齐 verify 资产的业务流真跑判据
- 【缺口】D4 部分：`verify.yaml` 三字段齐，但 done 停在 build/vet/test 与 `/health`，无真实业务流请求 + 响应体与外部可查证据。
- 【证据】S3 `verify_asset=['verify.yaml']`；`verify.yaml` 的 `done` 段。
- 【建议改动】按蓝图 §4.1 扩展 done：在 `/health` 之外用 API harness / `curl` 打真实业务端点（如列环境 / 查目标等只读接口），把**请求与响应体**落日志到 `evidence/`（带时间戳），退出码 0 才算通过；`hands.driver` 给 agent"手和眼"，feature map（`internal/` 各 handler 的契约场景）当 rubric；hub 已有 `make build/start-dev/stop-dev`。**harness 自身须压测到稳定**（VP-01，它是全部下游验证的地基）。
- 【对抗推演】AI 写永远 exit 0 的 done 凑绿（RT-05）→ done 指向真实系统可观测状态（业务端点 200 + 关键字段）与落盘响应体，超时 = fail 不重试。
- 【建议可信度】已验证模式（D4/VP-01/§4.1）。
- 【由谁决策】工程 + 契约负责人（done 判据须人确认）。
- 【严重度】中。

### 建议 5（P1）补齐验证戳生成与拦截谓词
- 【缺口】D8 部分：`redlines.yaml` 配了 `thresholds.verification_stamp`，但 31 commit 0 戳、无提交钩子实装，且无门禁谓词。
- 【证据】S3 ratio=0；git 全历史 `Verified:` 计数=0；S2 全仓无会话内验证动作的拦截配置。
- 【建议改动】分两套机制并用（§4.2 + §4.5）：
  - **验证戳（结果标记）**：提交工具链自动盖 `Verified: <e2e|unit|property|differential|manual|none>`，`none` 是合法值，使未验证提交可查询；`redlines.yaml` 已配 `thresholds.verification_stamp`；白名单外 method 按无效戳计。
  - **门禁灰度（off→observe→enforce 三档）**：按 VP-05 从 off（先确认开关无害）→ observe（只记录本会被拦的提交、不拦）→ enforce（拦截；commit 可附豁免理由；**同一会话内被拦两次后下一次放行**作逃生门，防 agent 死循环）。当前档位=off（无门）。
  - **拦截谓词（门拦什么，须与三档一起定义）**：谓词拦的是**该次提交所在会话内没有执行过约定验证动作的提交**（落地时由项目定义具体命令，如把 `go vet && go test` 绑到提交完成钩子，不写死某个 slash command）；判定依据是**会话内事实**（有没有跑过该动作），不是 commit message 上的戳——戳是结果标记（含 `none`），谓词是门禁判定拦不拦的依据，两套并用。只盖戳不定义谓词，等于给了开关没接电线。
- 【对抗推演】AI 滥盖 `Verified: e2e`（RT-11）→ 戳由工具链按实际跑过的门生成、白名单外 method 按无效戳计；AI 靠改 commit message 伪造"已验证"绕过门（RT-17 同型：变更不能修改审判自己的标准）→ 谓词只看会话内是否真跑过验证动作、不受 message 戳影响，且 hook 从目标分支取。
- 【建议可信度】已验证模式（D8/R-VER-008/§4.2/§4.5 含拦截谓词）。
- 【由谁决策】工程（提交链 + hook）+ 契约负责人（阈值与谓词动作）。
- 【严重度】中。

### 建议 6（P1）补覆盖率与变异门禁
- 【缺口】D2/D6 深度不足：CI 只跑 test 不度量覆盖率，无变异测试。
- 【证据】S2 无 coverage/mutation step。
- 【建议改动】先接 `go test -coverprofile` 阈值门（cheap-first），成熟后引入 go 变异测试（如 go-mutesting）在提交边界跑；阈值写 redlines。
- 【对抗推演】AI 删测试凑绿（RT-08）→ 覆盖率 + 变异分数双门配合 R-IMP-003。
- 【建议可信度】已验证模式（RT-08、R-VER-001/002）。
- 【由谁决策】工程；阈值由契约负责人定。
- 【严重度】中。

### 建议 7（P1）把 REVIEW 判卷清单的独立性机制接成实装
- 【缺口】D9 部分：`REVIEW.md` 与 `governance/golden-set.md` 已有骨架，但 base 分支取规则、评审绑定 commit 仍无实装。
- 【证据】`REVIEW.md` 列七条判卷条目与五条独立性机制；仓库无 commit 绑定评审记录。
- 【建议改动】按 §4.3 建 REVIEW 清单（三要素：触发器×检查内容×事故链接），逐条落地**五子机制**：①规则列入 `protected_paths`、CI 从 base 分支读；②评审绑定 commit、推新提交作废；③code owner 写检查并迭代；④拉人须说 why（触发哪条规则、什么证据）；⑤**单一 reviewer、多轮累积**——不堆叠第二个更贵的 reviewer，调优 REVIEW.md 本身，每轮喂前轮上下文与历史失败而非从头重查。补 commit 绑定与 base 分支读取的实装，使五条机制从文本变成运行形态。这条建议的收益对应 §0 判卷独立性实证（独立 grader +10 分、最难任务收益最大）。
- 【对抗推演】AI 同 PR 改判卷规则自审自过 / 用陈旧评审给新代码背书（RT-17 覆盖①②）→ ①②服务端钉死来源 + commit 绑定；③④⑤防社会工程与"堆 reviewer 反而更贵却漏检"。
- 【建议可信度】已验证模式（VP-03/§4.3/RT-17）。
- 【由谁决策】工程 + code owner；清单入保护路径须人审批。
- 【严重度】中。

### 建议 8（P2）把属性测试纳入 CI 常驻门
- 【缺口】D3 部分：`internal/coordination/properties_test.go` 有独立生成器属性且 `go test` 通过，但无 quickcheck 家族依赖特征、未进 CI 常驻门、survey 不识别。
- 【证据】S3 property 空；`internal/coordination/properties_test.go`。
- 【建议改动】按 §4.4 对 coordination 租约（幂等/互斥不变量）、k8srbac 绑定判定（round-trip）等写 ≥1 条独立生成器属性；四类模式按被测对象择用：①round-trip ②不变量 ③幂等 ④等价，并把属性测试作为 CI 常驻 step（cheap-first），使 survey 与后续审计可探测。**spec 与实现漂移时约束比 spec 稳，属性测试仍可用**——重写/迁移场景尤其有效。
- 【对抗推演】AI 用同源 bias 输入生成（VP-02）→ 输入必须由属性库生成器独立产生，属性陈述人审固化。
- 【建议可信度】已验证模式（D3/VP-02/§4.4）。
- 【由谁决策】工程；属性陈述人审。
- 【严重度】低。

### 建议 9（P2）守住 flaky 治理防回退 + 漏检回流双法 + 元验证
- 【缺口】D12 缺失、D11 达标但禁用门未常驻 CI：测试路径无 sleep/rerun、allowlist 仅豁免带理由的 DSN skip（S7 / S8）；需防新增 sleep 绕过，且漏检→规则与元验证仍停留在骨架。
- 【证据】S7（正向 rc=0）+ S8（反向 rc=1）；`REVIEW.md` H6/H7；`governance/golden-set.md`。
- 【建议改动】把 `static_risk_check.py` 接入 CI 常驻门（测试路径禁 sleep/rerun/skip，allowlist 只认带理由人审项），保持当前等待形态（`require.Eventually` / `require.Never` / `runtime.Gosched` / DB 时钟条件轮询）与 DSN 跳过理由；漏检→规则按 §4.7 **双法**并行：第一法三门槛（≥2 PR + ≥3 独立 agent 证伪 + 人审合入）；第二法用 3 个 bug finder 回放已知事故（≥2 命中才算可检测，**小 diff 上也被漏掉**即重点信号）。flaky 治理按 §4.6：根因修不好则删除该测试并写下删除理由。元验证按 §4.8：golden set（真实事故/revert + 体量相当干净对照）补回放执行与持续度量，**每例附一句话答案（answer key），只有正确描述该 bug 的 finding 才计分**——否则"随便报一条就算命中"会让 recall 虚高；分阶段 recall（原始发现→验证后→终审分别统计）、发现分级（Important/Nit/Pre-existing）、**数据集隔离（tuning 与 fixed 分离）**、**调参到过拟合边缘即停**、例行修剪；持续度量 merged 后 revert 数 / maintainer 合入前拒绝数作为长期体温计。
- 【对抗推演】AI 对 flaky 测试加更多 sleep 反复重跑（RT-16）→ 测试路径静态禁 sleep/rerun（R-VER-009）+ 连续失败阈值（建议 3），S8 证明新增 sleep 仍被拦；第二法防"规则从人已发现的模式归纳，却测不出机器能否复现发现"；数据集隔离防"调参即过拟合"无法察觉；一句话答案 + 只给正确描述计分防验证器靠宽口径虚报 recall。
- 【建议可信度】已验证模式（D12/VP-07/§4.7 双法、§4.8 含一句话答案评分口径、D11/R-VER-009 + S7/S8 实跑）。
- 【由谁决策】工程 + 契约负责人。
- 【严重度】低。

### 建议 10（P2，工具改进）文档一致性扫描排除 vendored 路径
- 【缺口】扫描器把第三方 chart README 死链计入 hub 缺陷（S5），制造噪音。
- 【证据】S5 + 该 chart `.helmignore` 明确忽略 `examples/`。
- 【建议改动】文档扫描排除 `build/**/charts/**/charts/`（vendored 依赖）路径；属工具改进建议，由使用者决定是否回流 skill。
- 【对抗推演】无（工具精确性改进，非治理规则）。
- 【建议可信度】已验证模式（S5 路径归属可复查）。
- 【由谁决策】审计工具维护者 / skill 使用者。
- 【严重度】低。

---

## 五、确认为达标的维度（附证据，避免只报缺口）

- **D1 基础静态门**：Format/Vet/Build/Test 四步在 CI 与本地均可用且实测全绿（S1+S2+S4）。
- **D2 单元测试规模**：81 个测试文件、覆盖 10+ service 包，`static_risk_check.py` 正向实跑 0 空断言（S7）。
- **D11 flaky 治理**：测试路径无 sleep/rerun，等待为显式条件等待；唯一 skip 带 DSN 理由并入 `static_risk_allowlist`；正向 rc=0、反向新增 sleep rc=1（S7+S8）。

---

## 六、工程化建议：人工核对 → 机器检查

| 人工核对项 | 升级条件 |
| --- | --- |
| 格式/风格一致性（建议1） | CI Format step 已承载（`gofmt -l` 归零）；保持 `protected_paths` + REVIEW H1 防删 step |
| 证据协议（建议2） | 证据包格式对齐 schemas.md 后由 harness 校验落点存在性 |
| 升级阈值（建议3） | `redlines.yaml` 已配 `max_consecutive_gate_failures`；接 harness 计数后强制转人 |
| 验证戳覆盖（建议5） | `redlines.yaml` 已配 `thresholds.verification_stamp`；戳生成后 `verification_gate_check.py --repo` 机检 |
| 拦截谓词（建议5） | 谓词动作绑 hook 后，查会话内事实（非 commit message 戳）属人工核；机检管不到 |
| verify 资产存在性（建议4） | survey 已可机检（`verify_asset=['verify.yaml']`）；done 业务流真跑与响应体仍需人核 |
| 覆盖率/变异（建议6） | CI 接报告后 `ci_gate_check.py` 机检 |
| 判卷独立性① ②（建议7） | 查受保护路径 + CI 从目标分支取（RT-01 同机制） |
| 判卷独立性③ ④ ⑤（建议7） | owner 写检查 / say-why / 多轮累积运行形态属人工核对与社会工程 |
| flaky 信号（建议9） | `static_risk_check.py` 正向 rc=0 / 反向 rc=1（S7+S8）；接入 CI 常驻门即可机检 |
| 漏检双法（建议9） | 第二法"≥2 命中 + 小 diff 漏检"可做成 bug finder 回放作业 |
| 元验证评分口径（建议9） | golden set 一句话答案 + 只给正确描述 bug 的 finding 计分属人工核口径，机检不做语义评分 |

---

## 七、蓝图覆盖表（§6 强制，防"漏带蓝图"）

> 处置三选一：`已建议`（去向指向建议编号，或显式标注「详见蓝图 §4.x（正文要点化，细节不重复）」）/ `当前不适用`（附理由）/ `待建设`（标 P0/P1/P2）。D 表（第二节）答"项目缺什么"，本表答"蓝图每项去了哪"，两表齐才闭环。覆盖范围含 §0/§1/§3/§4 全节 + VP。§4.3 五子机制、§4.4 四模式+spec 漂移、§4.7 双法、§4.10 四子项逐项拆行。§0 证据措辞与 +10 分实证数字、§3 能力+平台适配器分离口径、§4.5 拦截谓词、§4.8 golden set 评分口径属机检管不到的语义项，人工对照原文核。

| 蓝图条目 | 处置 | 去向（可核） |
| --- | --- | --- |
| §0 三个事实与证据协议（独立 grader 按 rubric 判卷 **+10 分、最难任务收益最大** / 验证即固定资产 / 39 项命中 3~10；agent 自述不算证据、评审绑 commit；**证据由外部 harness 收集、agent 只能引用不能转述**；要点化保留 +10 分数字与此措辞） | 已建议 | 建议 2/5/7；详见蓝图 §0（正文要点化，细节不重复） |
| §1 三种测试选择依据（E2E 难欺骗 / 属性独立生成器 / 差分旧系统 oracle） | 已建议 | 建议 4/8（E2E verify 资产、属性测试）；差分见 §4.9 行当前不适用；详见蓝图 §1（正文要点化，细节不重复） |
| §1 警告① flaky 训练重跑 | 已建议 | 建议 9（R-VER-009 + E-05，VP-06；S7 正向 rc=0 + S8 反向 rc=1） |
| §1 警告② 慢测试降低验证频次 | 待建设（P2） | 当前无慢测试；后续新增门按 cheap-first 评估，重门放提交边界 |
| §1 警告③ 重测试放提交边界 | 已建议 | 建议 6（变异在提交边界）、建议 5（off→observe→enforce） |
| §3 建设顺序 P0→P1→P2（cheap-first：开 PR 前本地 test/build/lint 全绿，重门在提交边界；**"本地先跑"是 agent 无关的能力——改动交给下游前自动跑便宜门并留痕，通用落点 git `pre-commit` hook；Claude Stop hook / `/goal` 等完成时事件只作可选加速器示例、不作能力判据**） | 已建议 | 建议 1/4/5；本报告建议标题阶段按 §3 权威表标注；详见蓝图 §3（正文要点化，细节不重复） |
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
| §4.6 flaky 治理（禁 sleep/rerun、删测试写理由） | 已建议 | 建议 9（P2）；S7/S8 实跑佐证门有效；详见蓝图 §4.6（正文要点化，细节不重复） |
| §4.7 第一法：三门槛（≥2 PR + ≥3 agent 证伪 + 人审合入） | 已建议 | 建议 9（P2） |
| §4.7 第二法：3 bug finder 回放已知事故 ≥2 命中、小 diff 漏检重点 | 已建议 | 建议 9（P2） |
| §4.8 元验证（持续度量 merged 后 revert 数 / maintainer 合入前拒绝数 / 干净变更对照、golden set **一句话答案 + 只有正确描述该 bug 的发现才得分**、分阶段 recall、Important/Nit/Pre-existing、数据集隔离 tuning vs fixed、调参到过拟合边缘即停、修剪；要点化保留评分口径） | 已建议 | 建议 9（P2，一句话答案与计分口径在正文定义） |
| §4.9 差分测试（oracle/采样、归一化、允许变更白名单、收敛判据） | **当前不适用**：无"可并行运行的旧实现"——migrations 是破坏性 schema 演进、旧 schema 不并行；approval_* 是业务审批流、testdata 是契约快照样例，均非旧实现对拍（S6）。将来若引入双写/重写迁移再启用 | — |
| §4.10 ① 基线管理（protected_paths / 人确认首版 / 稳定时刻 / sha256） | **当前不适用**：hub 为纯后端 HTTP API，无浏览器/桌面/移动前端交互界面，无截图基线可比（§4.10 适用前提不满足）；将来若引入前端界面再启用 | — |
| §4.10 ② 比对协议（baseline/actual sha256 + diff 指标 + 容差 + 漂移处置分岔） | **当前不适用**：纯后端 API 无前端界面、无视觉比对场景；适用前提不满足 | — |
| §4.10 ③ 异常态驱动清单（网络失败/空数据/超时/权限/弹窗抽屉各态 + 截图↔用例映射） | **当前不适用**：无 UI 交互与截图，异常态由 API 测试覆盖、无界面态映射；适用前提不满足 | — |
| §4.10 ④ 截图一等证据（schemas screenshot 类型 + sha256 + 场景 id） | **当前不适用**：无前端截图产物，证据类型为日志/退出码；适用前提不满足 | — |
| VP-01 verify harness 是地基 | 已覆盖 | §4.1 行 / 建议 4 |
| VP-02 三种测试选择依据 | 已覆盖 | §4.4 行 / 建议 8；E2E 见建议 4 |
| VP-03 判卷独立性 | 已覆盖 | §4.3 五子机制 / 建议 7 |
| VP-04 cheap-first | 已覆盖 | §3 行 / 建议 1/4/6 |
| VP-05 observe→enforce | 已覆盖 | §4.5 行 / 建议 5 |
| VP-06 flaky 铁腕治理 | 已覆盖 | §4.6 行 / 建议 9 |
| VP-07 漏检回流+元验证+修剪 | 已覆盖 | §4.7 双法 / §4.8 行 / 建议 9 |

**覆盖自检**：§0/§1/§3/§4 全节均有处置；§4.1~4.10 十项全处置（§4.1~4.8 八项已建议 + §4.9 当前不适用附理由 + §4.10 四子项均当前不适用附理由）；§4.4 四模式 + spec 漂移拆五行、§4.3 五子、§4.7 双法、§4.10 四子项逐项拆行；VP-01~07 全部映射；机检管不到的语义项按蓝图原文人工核并写入对应建议正文与覆盖行——§0"agent 只能引用不能转述"与 +10 分/最难任务收益最大（建议 2/7）、§3 能力+平台适配器分离口径（建议 2）、§4.5 拦截谓词（建议 5）、§4.8 golden set 一句话答案 + 只有正确描述该 bug 的发现才得分（建议 9）；所有去向仅用建议编号或「详见蓝图 §4.x」，无不可核自证断言；建议标题阶段与 D 表判定按 §3 权威表对齐。已由 `report_gate.sh` 单一入口机检确认。

---

## 八、归档与回流

- 本报告归档于 hub 仓库 `audits/`，为审计自有产物，未修改任何被审源码/配置/CI。
- 未发现 `attack-cases.md` 案例库未收录的新型绕过手法，**无晋升建议**。
- 全部结论为建议模式输出，**非合规判定**；采纳与否由人决策。
