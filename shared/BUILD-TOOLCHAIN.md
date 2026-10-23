# BUILD-TOOLCHAIN — 三组件镜像构建工具链要求（containerd 路线）

> 横跨范围：hub / runner / console 三组件镜像构建（`build/<comp>/build.sh`）+ env 仓环境就绪脚本。本文是工具链**版本要求**的统一权威；各仓 README 与 env 脚本为落地实现。

## 1. 版本要求（硬性）

| 工具 | 版本要求 | 原因 |
| --- | --- | --- |
| nerdctl | **>= 2.x** | `nerdctl save` 默认输出 docker 归档格式，无 `--format` 旗标 |
| buildkitd | **>= v0.34** | `--containerd-worker` 为 string 型（`true/false/auto`），必须显式赋值 |
| containerd | 复用宿主托管实例 | 禁止安装 docker / containerd.io——会与宿主 `containerd.service` 冲突（CCE 托管节点 kubelet + containerd 常驻） |
| go | >= 1.27 | 三组件编译（`go.mod` 强制：hub / runner `go 1.27.0`） |
| node + pnpm | node >= 22 / pnpm 11.x | console 构建 |

**版本基线原则：只按最新版要求写。** `build.sh` 无旧版旗标探测分支。

## 2. build.sh 行为要点（三仓同型）

- **`sdp_save`（镜像归档）**：`nerdctl save -o <file> <img>`，默认即 docker 归档格式，不带 `--format` 旗标。
- **`ensure_nerdctl`（buildkitd 拉起）**：`buildkitd --containerd-worker=true --addr tcp://127.0.0.1:1234`。
  - 必须写 `=true`：裸旗标会把后面的 `--addr` 当值吃掉，报 `strconv.ParseBool`。
  - buildkitd 已在运行则跳过拉起（`pgrep -x buildkitd`），`BUILDKIT_HOST=tcp://127.0.0.1:1234` 与启动地址一致。
- **运行时分派**：有 docker 用 docker 路线；无 docker 走 nerdctl + buildkitd 复用宿主 containerd（`nerdctl info` 判活）。
- **构建期环境变量（屏蔽节点坏环境）**：
  - `SDP_GOPROXY`：覆盖 `GOPROXY`（默认 `https://goproxy.cn,direct`）。**不继承节点 `GOPROXY`**——CCE 节点该值常是不可达的 `proxy.golang.org`，直连会污染模块拉取。
  - `go build -buildvcs=false`：交付源码 tar 排除 `.git`，无 VCS 信息，必须关闭 VCS stamping，否则 `go build` 失败。
  - `APT_MIRROR`（Dockerfile `ARG`，默认 `mirrors.huaweicloud.com/ubuntu`）：替换 `deb http://archive.ubuntu.com/ubuntu`。云内网直连 `archive.ubuntu.com` 不通时走镜像源；替换值**必须含 `http://` scheme**，否则写出 `deb mirrors.huaweicloud.com/...` 触发 apt `Malformed entry`。

## 3. buildkitd 配置（registry mirrors）

buildkitd 读取默认配置 `/etc/buildkit/buildkitd.toml`，启动时一次性读取。docker.io 直连不通的环境（华为云内网节点）需配置 mirrors：

```toml
[registry."docker.io"]
  mirrors = ["https://docker.1panel.live", "https://dockerproxy.net", "https://docker.m.daocloud.io", "https://docker.1ms.run"]
```

注意：buildkitd 运行中写入该文件不会热生效，需 `pkill -x buildkitd` 后由 build.sh 下次构建重新拉起。

## 4. 落地位置

| 位置 | 内容 |
| --- | --- |
| 各仓 `build/<comp>/build.sh` | `sdp_save` / `ensure_nerdctl` 实现（hub、runner、console 三仓同型，改动须三仓同步） |
| env 仓 `prod-deplyment/hce-2.0-64bit-env.sh` | HCE 2.0 节点环境就绪（工具安装 + mirrors 写入 + buildkitd 拉起），幂等 |
| env 仓 `prod-deplyment/centos-stream-9-64bit-env.sh` | CentOS Stream 9 节点（docker 路线） |
| 四仓 README（hub / runner / env local-kind-dev / env prod-deplyment） | 版本要求摘录（与本文件保持一致） |
