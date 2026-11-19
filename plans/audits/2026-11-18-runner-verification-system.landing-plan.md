# software-distribution-platform-runner 推荐落地计划

> 配套报告：2026-11-18-runner-verification-system.md
> 口径：本计划为建议，按依赖排序；采纳与否由人决策。成熟度阶段（P0/P1/P2）是建议本身的属性，不是批次顺序。

## 一句话结论

地基停在"静态门可用"层：CI 有 Format/Vet/Build/Test、本地 gofmt 零命中、14 个受版本控制测试全绿，CI 注释已与实现一致；缺 golangci-lint 风格门，verify 循环与判卷机制只有骨架。第一批先补风格门并纳管注释防回退（便宜可逆），第二批把 verify 的 done 延伸到真实任务下发流并落外部证据当承重墙——它是后面所有门的消费者前提。

## 批次总览

| 批次 | 目标 | 吸收建议 | 前置 | 验收 gate | 需拍板 |
| --- | --- | --- | --- | --- | --- |
| 第一批：补风格门并纳管注释 | 让 CI 门齐、注释防回退 | 建议 1/10 | 无 | `gofmt -l $(git ls-files '*.go')` 输出为空；golangci-lint 必需 step 后 `make build` rc=0 | 无 |
| 第二批：跑通 verify 循环 | 定义 done、真跑任务下发流、落外部证据 | 建议 2/4 | 第一批 | `make build` rc=0；API harness/WS harness 驱动真实任务下发流（WS 回连→下发→执行→结果回流）跑通完整用户流；响应体与带时间戳日志落 `evidence/`（含 sha256），退出码 0 | 无 |
| 第三批：铺证据协议与升级策略 | 结论不再靠自述、失败有转人阈值 | 建议 3 | 第二批 | 抽查 3 条 agent 结论均附退出码与日志路径；`max_consecutive_gate_failures=3` 接到钩子并经 `report_gate.sh` 校验 | 见需拍板项① |
| 第四批：验证戳与判卷独立性 | 未验证可查询、判卷防自欺 | 建议 5/7 | 第三批 | 门以 observe 运行、误拦数 0；REVIEW.md 五条机制从文档接到流程（base 分支读规则、评审绑 commit） | 见需拍板项② |
| 第五批：补测试与漏检闭环 | 抗偏差、同一个坑不踩两次 | 建议 6/8/9 | 第四批 | `go test ./...` rc=0；属性库依赖接入后 canary/快照四模式齐；golden set 每例附一句话答案与计分口径 | 无 |

## 各批次明细

### 第一批：补风格门并纳管注释

- **做什么**：`ci.yml` 已有 Format/Vet/Build/Test 四步、注释与实现一致；补 golangci-lint 必需 step；把 `.github/workflows/*.yml` 列入 `review_required_paths` 防注释回退。文档扫描器把代码注释里的路径与数量声明纳入检查。
- **吸收建议**：建议 1（CI 补风格门并纳管注释防回退）、建议 10（文档扫描覆盖代码注释）
- **验收 gate**：
  - `gofmt -l $(git ls-files '*.go')` → 输出为空（当前已 0 命中，保持不回退）
  - golangci-lint 必需 step 后 `make build` → rc=0
- **完成定义**：上述两条 gate 全过即本批完成，不靠自述"已修好"。

### 第二批：跑通 verify 循环

- **做什么**：`verify.yaml` 已有 build/start/done 三字段（done 到 `go test` 与 healthz）；把 done 延伸到真实任务下发流——API harness/WS harness 驱动 WS 回连→任务下发→执行→结果回流；hands.driver 给 agent 手和眼，done 判据用验收场景清单当 rubric。**harness 自身须先压测到稳定**——它是全部下游验证的地基。
- **吸收建议**：建议 2（证据协议）、建议 4（把 verify 资产的 done 延伸到真实任务下发流）
- **验收 gate**：
  - `make build` → rc=0；`make start-dev` → 服务起
  - API harness/WS harness 驱动真实任务下发流跑通完整用户流 → 响应体与带时间戳日志落 `evidence/`（含 sha256），退出码 0
- **完成定义**：从 build 到真实任务下发流的整条链能在一次会话内跑通并留下外部可查证据。

### 第三批：铺证据协议与升级策略

- **做什么**：让所有 agent 结论附退出码与日志路径（由 harness 收集、agent 只能引用不能转述）；把 `max_consecutive_gate_failures=3`（redlines 已配该值）接到钩子，实现连续失败转人。
- **吸收建议**：建议 3（把连续失败转人阈值接到钩子 E-05）、建议 2 的协议铺开部分
- **验收 gate**：
  - 抽查 3 条 agent 结论 → 均附退出码与日志路径
  - `max_consecutive_gate_failures=3` 接到钩子 → 经 `report_gate.sh` 校验存在
- **完成定义**：协议成为默认动作，失败计数达阈值即转人。

### 第四批：验证戳与判卷独立性

- **做什么**：`governance/redlines.yaml` 已配 `verification_stamp` 阈值；实装提交工具链自动盖戳（含 `none`）+ 拦截谓词（门拦"会话内没执行过约定验证动作的提交"）；门先 observe 不 enforce；把 `REVIEW.md` 的五条机制从文档接到流程（base 分支读规则、评审绑 commit、code owner 写检查、拉人说 why、单一 reviewer 多轮）。
- **吸收建议**：建议 5（验证戳 + 三档 + 拦截谓词）、建议 7（REVIEW 判卷清单与五条独立性）
- **验收 gate**：
  - 门以 observe 模式运行 → 记录误拦数为 0
  - REVIEW.md 五条机制 → 从文档接到流程（base 分支读规则、评审绑 commit）且可从 diff 读 trigger
- **完成定义**：门在 observe 下稳定、判卷清单可操作。

### 第五批：补测试与漏检闭环

- **做什么**：补覆盖率与变异门禁；在已有 canary/快照属性测试上引入外部属性库与独立生成器（round-trip / 不变量 / 幂等 / 等价四模式）；漏检→规则双法（三门槛 + bug finder 回放已知事故）；以 `governance/golden-set.md` 为底做元验证（每例一句话答案、只有正确描述该 bug 才计分、数据集隔离）；`static_risk_check.py` 接 CI 常驻门保持 0 命中。
- **吸收建议**：建议 6（覆盖率与变异）、建议 8（属性测试）、建议 9（漏检回流双法 + 元验证 + flaky 常驻门）
- **验收 gate**：
  - `go test ./...` → rc=0
  - 属性库依赖接入 → canary/快照四模式齐
  - golden set 每例 → 附一句话答案与计分口径
- **完成定义**：三层测试投资（静态冒烟 / 属性 / 判卷）各有真实 gate。

## 需拍板项（单列）

下列只圈必须人定的具体值；仓库内能落的驱动入口、证据落点、比对脚本照常进批次，待定值只作为参数，不整批推迟。

| 编号 | 决策点 | 推荐值 | 理由 | 默认动作 |
| --- | --- | --- | --- | --- |
| ① | E-05 连续失败转人阈值取多少 | 3 次（redlines 已配该值） | 报告与蓝图 §3 默认值一致，低于 3 易误转、高于 3 浪费轮次 | 按推荐值 3；要改请指出 |
| ② | 验证戳门何时从 observe 转 enforce | 观察满一周且误拦为零再转 | 直接 enforce 会拦住尚未接钩子的历史提交 | 按推荐值；要提前转请指出 |

## 当前不适用（不进批次）

| 建议 | 不适用理由 |
| --- | --- |
| 无 | 本仓库 10 条建议全部纳入批次；§4.9 差分测试与 §4.10 前端视觉在报告里为当前不适用，未列为建议 |
