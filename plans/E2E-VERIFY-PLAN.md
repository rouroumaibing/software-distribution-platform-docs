# E2E 验证计划（已执行完毕 · 历史归档）

> **状态：已执行（2026-09-24，本机 docker + kind）。** 本计划已走完全部生命周期，正文并入以下两处，**当前状态与未完成项一律以 [plans/STATUS.md](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/plans/STATUS.md) 为唯一权威**：
> - 执行结果与 3 个真 bug（deploy 脚本空数组 / runner RBAC 缺 ingresses / component 删除 500）→ `UNIMPLEMENTED-MODULES-PLAN.md` §16
> - 三轮收口记录（T-U1 端到端 / T-U3 agent_ops / 取消与重跑 E2E）→ `UNIMPLEMENTED-MODULES-PLAN.md` §17–§18
> - 验证产物脚本：`plans/e2e-smoke.sh`、`plans/e2e-cancel-rerun.sh`
>
> 本文件仅保留 §P6 —— 它是「不采纳自升级」六条理由的**唯一权威落点**（`docs/README` §5.4 与多处文档引用此处）。

---

### P6 平台自身部署与升级（二期）—— **2026-09-21 裁决：不走平台，留在平台之外**

> 背景：old/go-devops 是 hub 前身、old/go-devops-ui 是 console 前身，曾由此设想"平台发布平台自己"（当时简称「自举」——**该词随方案撤销一并停用**，全库不再单用「自举」二字，见 [hub/DATA-MODEL.md §9.0 术语消歧](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/hub/DATA-MODEL.md)）。
>
> **裁决（2026-09-21，撤销 2026-09-06 的"自升级默认走平台流水线"）**：平台自身的部署与升级**永远在平台之外**——官方通道 = 各仓 `make package` / `pnpm image` 产出的镜像 + chart 交付包，由**外部 helm / CI** 发布。六条理由见下。

**不采纳「自升级」的六条理由**（本节为唯一权威落点；2026-09-23 自 docs/README §5.4 迁入）

1. **hub 是四重自指**：控制面 + 编排存储 + 制品来源 + 制品消费。升级 hub 的编排存在 hub DB 里、chart 由 hub 的制品库供、签名 URL 指向 hub Service——hub 起不来则**升级通道与回滚通道同时消失**，无法自救。
2. **必须放宽安全边界**：runner 的集群侧权限被刻意限定为"只碰某组件命名空间"；让它 helm-upgrade `sdp-workflow` 是**实质扩权**，且 `pipeline.sdp.io` 的 CRD 是 **cluster-scoped**，schema 变更绕不过集群级权限。
3. **不可灰度、不可回滚**：CRD 是集群级原子生效；helm rollback **不还原 CRD**（helm 不追踪 CRD 版本）；hub 建表靠启动时 AutoMigrate（只加不删）。新版本一旦把控制面锁死，唯一救生索是手工 `kubectl`。
4. **观测真空恰好覆盖最关键的那次运行**：hub 重启期间，这次升级的记录 / 日志 / DAG 全在重启中的 hub 里——**最需要看清的运行恰好看不见**。
5. ~~权限主体在 API 层不存在~~ ✅ **已补（2026-09-22，C-10）**：平台级 RBAC 已有 HTTP 端点，"谁有权批准平台自升级"已可在平台内表达；但「自升级」审批流与到期回收仍未落地（STATUS #3）。
6. **收益错配**：平台组件数量固定（hub / console；runner 是接入侧代理不计入）、升级者就是平台运维本人；通用流水线（版本历史 / 参数管理 / 一键回滚 / 审批）在自升级上边际收益低，而这些恰是外部 CI + helm 的强项。

**允许与不允许的分界**

| | 内容 | 理由 |
|---|---|---|
| ✅ 允许 | **hub / console 与 runner** 的**构建**走平台流水线（编译 hub / runner / console、打镜像、打 chart tgz 并归档进制品库） | 吃狗粮验证 Build 链路；失败可重跑，无自指风险（runner 不属平台自身，但构建同源） |
| ❌ 不允许 | 平台组件的**发布 / 升级**走平台（`Release` 不发布平台自身） | 见上述六条理由；升级失败时平台无法自救 |
| ✅ 保留 | **Gen0 手工 helm 基线长期保留**，不是一次性过渡；每次破坏性变更（CRD / DB schema）都回到手工通道 | — |

**"独立升级页面上传组件包升级平台"**：**本期不做**。它不能挂在 console 下（console 本身是被升级对象，它挂了正是最需要该页的时候）；唯一可行形态是**平台之外常驻的 upgrade-controller**（Gen0 手工安装、**永不自升级**，自己服务静态页 + 执行其余三者的 helm 升级）——那是把"平台之外"这条通道产品化，不是把自升级做进平台。若将来要做，作为独立提案重开。

**保留的历史分析**（自升级方向已撤销，但下列机制性结论在将来重开时仍然成立）

- 代际阶梯（解决鸡生蛋）：Gen0 手工（postgres + hub + runner）→ Gen1 平台发布 demo-app（P3/P5）→ ~~Gen2 平台发布自己~~（**2026-09-21 撤销**）。
- `Build → Approval → Release`：升级自己挂了没人救，人工卡点不可省。
- hub / runner 必须分两个 Release 任务、按阶段顺序先 hub 后 runner：hub 升级时 runner 断连只重连不退出（存量任务照跑）；runner 自升级时，执行升级的 releaseContainer Job 独立于 runner Pod 存活，旧 runner 把 reconcile 跑完。
- 上一版 chart / 镜像必须留在制品库：helm 原生 rollback / P4 回滚随时可用。
- **CRD schema 分级处理**（不是一刀切禁止）：
  - **兼容变更**（新增可选字段、放宽校验、加枚举值）可自动——但必须是显式前置步骤（pre-upgrade hook Job 或独立的 kubectl apply 任务）。注意 Helm 3 的 `crds/` 目录是 install-only，`helm upgrade` **不会**更新它——靠 chart 直升 CRD 需要放 `templates/`（helm 会接管其生命周期，uninstall 连删，不推荐）或走 hook
  - **破坏性变更**（加 required、删字段、改类型、引新版本+conversion）必须手工：先备份存量对象（`kubectl get -o yaml`）再 apply
  - 破坏性变更手工的三个硬理由：① CRD 变更是**集群级原子生效，无法灰度**——Deployment 能金丝雀，schema 不能；② helm rollback **不还原 CRD**（helm 不追踪 CRD 版本），"回滚是安全网"的前提对 schema 失效；③ runner 既是升级执行者又是被升级者——破坏性变更会让旧 runner 写出的对象过不了新校验，**锁死自升级通道本身**，唯一救生索就是手工 kubectl
  - 判断口诀：**改完后，旧版本 runner 创建的对象还能通过新 schema 校验吗？** 能→兼容可自动；不能→破坏必须手工
- **前置改造（若将来重开必做）**：制品存储须先从 hub 自带的 `local` driver 解耦为外部对象存储——否则 hub 挂了拉不到 chart（现 P0 拓扑下 `ARTIFACT_STORE_PUBLIC_URL` 指向 hub Service）。
