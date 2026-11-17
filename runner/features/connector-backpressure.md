# Connector 背压策略（runner → hub 长连接发送面）

> 权威范围：`software-distribution-platform-runner/pkg/connector` 的出站发送行为。
> 入站（hub 下发）与本策略无关；重连退避、C-05 resync 见 STORY-runner-implementation §4 与 ADR-0001。

## 1. 问题与目标

runner 的所有出站帧（status / log chunk / heartbeat / agent_info / agent_op status）都是 best-effort 遥测：状态由 reconcile 触发上报、重连时经 OnConnect resync 重新对齐（C-05），丢帧不丢正确性。但发送面存在两个失效模式：

1. **goroutine 堆积**：`Send` 向 256 缓冲的 outbox 阻塞投递且不感知取消。当 WS 连接停滞（对端不读、网络半开）导致写泵卡住、outbox 写满后，每个上报 goroutine（status reconcile、日志 tail、agent_op 执行器）都永久阻塞在 channel 上——连接停滞越久，堆积越多。
2. **写泵永久卡死**：出站 `WriteJSON` 未设写超时。TCP 半开（如宿主休眠、NAT 超时）时写操作可能无限阻塞，连接既不恢复也不报错，叠加问题 1 后 runner 出站面整体失活。

目标：出站面在任何连接状态下都不产生无界 goroutine 堆积，停滞连接可被检测并触发重连。

## 2. 设计

### 2.1 Send 非阻塞投递，满则丢弃

- `Send` 对 outbox 用 `select/default` 非阻塞投递：缓冲满即丢弃该帧，不阻塞调用方。
- 丢弃帧不返回错误（调用方语义仍是「已受理」），由 client 内原子计数器记录累计丢弃数；计数为 1 及每满 100 时打一条日志，避免日志风暴。
- 丢弃安全性依据：全部出站帧类型均为遥测语义——
  - `status_update`：下次 reconcile / 重连 resync 重发全量状态；
  - `log_chunk`：只丢当段，tail 继续跟随，连接恢复后后续段正常送达；
  - `heartbeat` / `agent_info`：15s 周期帧与重连即发的身份帧，天然可重发。
- 已接受限制：outbox 跨重连保留旧帧（旧帧仍是有效遥测），极端背压下新连后的 `agent_info` 可能被丢弃，`agent_version` 由下一次重连的身份帧补偿。

### 2.2 写泵带写超时

- 出站循环每次 `WriteJSON` 前设写超时（10s）：停滞连接上写操作按超时报错 → `connectAndServe` 返回 → 进入既有指数退避重连（1s→30s 封顶），而非无限阻塞。
- 重连后 OnConnect resync 重新对齐状态，丢弃与超时不产生持久状态偏差。

### 2.3 边界

- 读侧行为不在本策略内：`ReadJSON` 的活性依赖 TCP 层检测与 hub 网关侧超时（见 shared/NETWORKING-GATEWAY.md）。
- 入站 handler 失败仅记日志、不重试（重派是 hub 的持久队列职责，见 ADR-dispatch-durable-queue）。

## 3. 验证 gate

- 单测：outbox 写满后 `Send` 不阻塞（超时守护）、丢弃计数递增（`pkg/connector` 同包测试）。
- 仓 gate：`gofmt -l`（改动文件）/ `go build ./...` / `go vet ./...` / `go test ./...` 全绿。

## 4. 变更历史

| 日期 | 决策 |
| --- | --- |
| 2026-11-16 | Send 由阻塞投递改为非阻塞 + 满则丢弃（原子计数），写泵加 10s 写超时；依据：全出站帧均为 best-effort 遥测且 C-05 resync 提供状态补偿，阻塞投递会在连接停滞时无界堆积 goroutine。 |
