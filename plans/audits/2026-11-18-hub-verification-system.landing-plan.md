# software-distribution-platform-hub 推荐落地计划

> 配套报告：2026-11-18-hub-verification-system.md
> 口径：本计划为建议，按依赖排序；采纳与否由人决策。成熟度阶段（P0/P1/P2）是建议本身的属性，不是批次顺序。

## 一句话结论

地基已有可复用的静态门与 flaky 治理：CI 四条 step、本地全绿、`gofmt -l` 归零、`static_risk_check.py` 正向 rc=0 / 反向 rc=1。第一批先守住格式与 flaky 门防回退（便宜可逆）；第二批做 verify 循环当承重墙——`verify.yaml` 的 done 目前停在 `/health`，须补真实业务端点的请求+响应体并落外部证据，它是后面所有门的消费者前提。

## 批次总览

| 批次 | 目标 | 吸收建议 | 前置 | 验收 gate | 需拍板 |
| --- | --- | --- | --- | --- | --- |
| 第一批：守住格式与 flaky 门 | 让门保持在位、能拦回退 | 建议 1/9/10 | 无 | `gofmt -l $(git ls-files '*.go')` 输出为空；CI Format step 在 Vet 之前；`static_risk_check.py` 正向 rc=0、反向插 sleep rc=1；`go build ./...` rc=0 | 无 |
| 第二批：跑通 verify 循环 | 定义 done、真跑一次完整业务流、落外部证据 | 建议 2/4 | 第一批 | `go build ./...` rc=0、`make start-dev` 服务起；API harness / `curl` 打真实业务端点（列环境/查目标等只读接口，不止 `/health`）跑通完整用户流，把请求与响应体落日志到 `evidence/`（带时间戳），退出码 0 | 见需拍板项③ |
| 第三批：铺证据协议与升级策略 | 结论不再靠自述、失败有转人阈值 | 建议 3 | 第二批 | 抽查 3 条 agent 结论均附退出码与日志路径；`max_consecutive_gate_failures=3` 接入 harness 并经 `report_gate.sh` | 见需拍板项① |
| 第四批：验证戳与判卷独立性 | 未验证可查询、判卷防自欺 | 建议 5/7 | 第三批 | 门以 observe 运行；`REVIEW.md` 存在且五条机制逐项标注 | 见需拍板项② |
| 第五批：补测试与漏检闭环 | 抗偏差、同一个坑不踩两次 | 建议 6/8 | 第四批 | `go test ./...` rc=0；属性测试覆盖核心纯逻辑；golden set 每例附一句话答案与计分口径 | 无 |

## 各批次明细

### 第一批：守住格式与 flaky 门

- **做什么**：保持 CI 的 Format step 在 Vet 之前、workflow 从目标分支取；`.github/workflows/**` 留在 `protected_paths` 并由 CODEOWNERS 钉死来源，`REVIEW.md` H1 条目每次评审核对四步未被删、未改 `continue-on-error`。保持测试路径的显式条件等待（`require.Eventually` / `require.Never` / `runtime.Gosched` / DB 时钟条件轮询）与 `COORDINATION_TEST_DSN` 跳过理由；把 `static_risk_check.py` 接成 CI 常驻门，`static_risk_allowlist` 只认带理由人审项。文档一致性扫描排除 vendored 路径避免噪声。
- **吸收建议**：建议 1（守住格式门并防回退）、建议 9 的 flaky 常驻门部分（漏检回流双法 + 元验证 + flaky 治理）、建议 10（文档一致性扫描排除 vendored 路径）
- **验收 gate**：
  - `gofmt -l $(git ls-files '*.go')` → 输出为空
  - `static_risk_check.py` 对测试路径实跑 → 正向 rc=0、反向插入一处 `time.Sleep` rc=1
  - `go build ./...` → rc=0
- **完成定义**：三条 gate 全过即本批完成，不靠自述"已修好"。

### 第二批：跑通 verify 循环

- **做什么**：落 `verify.yaml`（`build: go build ./...`、`start: make start-dev`、`done:` = vet/test + `/health` + 业务端点真跑），用 API harness / `curl` 给 agent 手和眼；done 在健康检查之外再打真实业务端点（列环境 / 查目标等只读接口），把请求方法、URL、状态码与**响应体**落日志到 `evidence/`，feature map（`internal/` 各 handler 的契约场景）当 rubric。**harness 自身须先压测到稳定**——它是全部下游验证的地基。
- **吸收建议**：建议 2（建立证据协议）、建议 4（建立声明式 verify 资产）
- **验收 gate**：
  - `go build ./...` → rc=0；`make start-dev` → 服务起
  - API harness / `curl` 对业务端点做请求+响应体采集，跑通完整用户流 → 退出码 0，请求与响应体日志落 `evidence/`（带时间戳）
  - 抽查 `evidence/` 日志 → 含状态码 200 与关键字段，不止 `/health`
- **完成定义**：从 build、start 到业务流 done 的整条链能在一次会话内跑通，并留下外部可查的请求与响应体证据。

### 第三批：铺证据协议与升级策略

- **做什么**：让所有 agent 结论附退出码与日志路径（由 harness 收集、agent 只能引用不能转述）；以 `max_consecutive_gate_failures=3` 接入 harness 计数，同一门禁连续失败 ≤3 轮修不好即停止重试、转人。
- **吸收建议**：建议 3（建立连续失败转人阈值 E-05）、建议 2 的协议铺开部分
- **验收 gate**：
  - 抽查 3 条 agent 结论 → 均附退出码与日志路径
  - `max_consecutive_gate_failures=3` 接入 harness → 经 `report_gate.sh` 校验存在
- **完成定义**：协议成为默认动作，失败轮次由 harness 计数而非 agent 自清。

### 第四批：验证戳与判卷独立性

- **做什么**：引入验证戳（含 `none`）+ 拦截谓词（门拦"会话内没执行过约定验证动作的提交"）；门先 observe 不 enforce；把 `REVIEW.md` 的五条判卷独立性机制接成实装（base 分支读规则、评审绑 commit、code owner 写检查、拉人说 why、单一 reviewer 多轮）。
- **吸收建议**：建议 5（验证戳+三档+拦截谓词）、建议 7（REVIEW 判卷清单与五条独立性）
- **验收 gate**：
  - 门以 observe 模式运行 → 记录误拦数为 0
  - `REVIEW.md` 存在 → 五条机制逐项标注且可从 diff 读 trigger
- **完成定义**：门在 observe 下稳定、判卷清单可操作。

### 第五批：补测试与漏检闭环

- **做什么**：补覆盖率与变异门禁；对核心纯逻辑（shard 映射、租约选主、权限判定）补属性测试（round-trip / 不变量 / 幂等 / 等价四模式，独立生成器）并接入 CI 常驻 step；漏检→规则双法（三门槛 + bug finder 回放已知事故）；元验证 golden set 补回放执行与持续度量（每例一句话答案、只有正确描述该 bug 才计分、数据集隔离，见建议 9 的元验证部分）。
- **吸收建议**：建议 6（覆盖率与变异门禁）、建议 8（核心纯逻辑属性测试）、建议 9 的漏检双法与元验证部分
- **验收 gate**：
  - `go test ./...` → rc=0
  - 属性测试覆盖 shard/租约/权限纯逻辑 → 四模式齐且在 CI 常驻
  - golden set 每例 → 附一句话答案与计分口径
- **完成定义**：三层测试投资（静态门 / 属性 / 判卷）各有真实 gate。

## 需拍板项（单列）

| 编号 | 决策点 | 推荐值 | 理由 | 默认动作 |
| --- | --- | --- | --- | --- |
| ① | E-05 连续失败转人阈值取多少 | 3 次 | 报告与蓝图 §3 默认值一致，低于 3 易误转、高于 3 浪费轮次 | 按推荐值 3；要改请指出 |
| ② | 验证戳门何时从 observe 转 enforce | 观察满一周且误拦为零再转 | 直接 enforce 会拦住尚未接钩子的历史提交 | 按推荐值；要提前转请指出 |
| ③ | verify done 打哪个业务端点、断言哪些关键字段 | 用只读 GET（列环境 / 查目标），断言 HTTP 200 + 关键字段存在，请求与响应体落 `evidence/` | 具体端点与字段是参数，定下来即可施工；不作为整批推迟理由，驱动入口、证据落点、比对脚本照常进第二批 | 按推荐值选只读端点；要换端点或加字段请指出 |

## 当前不适用（不进批次）

| 建议 | 不适用理由 |
| --- | --- |
| 无 | 本仓库 10 条建议全部纳入批次；§4.9 差分测试、§4.10 前端视觉在报告里已判当前不适用（hub 为 Go 后端、无可并行旧实现无前端界面），未列为建议 |
