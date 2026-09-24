# hub 认证子系统：Keycloak 子 chart 与 realm 预置

> **一句话**：hub 的 chart **内嵌** codecentric/`keycloakx` 7.3.2 子 chart（vendor 在 `charts/keycloak/`，随 hub **一次安装**），并预置本项目 realm `sdp` —— 它为 console 的 OIDC 登录与 hub 的令牌校验提供**身份底座**。
>
> **权威落点（代码）**：hub 仓 `build/hub/charts/software-distribution-platform-hub/` 下的 `Chart.yaml`（依赖声明）、`values.yaml`（`keycloak:` 参数段）、`templates/keycloak-realm-configmap.yaml`（realm 预置）。
> **权威落点（认证逻辑）**：hub 仓 [`internal/middleware/`](https://github.com/rouroumaibing/software-distribution-platform-hub/tree/main/internal/middleware)（`auth.go` / `user_context.go` / `WIRING.md`）。

---

## 1. chart 从哪来（上游来源与固定版本）

| 项 | 值 |
| --- | --- |
| 上游仓库 | [codecentric/helm-charts](https://github.com/codecentric/helm-charts) 的 [`charts/keycloakx`](https://github.com/codecentric/helm-charts/tree/master/charts/keycloakx) |
| chart 版本 | **7.3.2**（固定） |
| Keycloak 版本（`appVersion`） | **26.7.4**（Quarkus 发行版） |
| Helm repo 地址 | `https://codecentric.github.io/helm-charts` |
| 获取命令 | `helm repo add codecentric https://codecentric.github.io/helm-charts`<br>`helm pull codecentric/keycloakx --version 7.3.2` |

- **为什么用它**：`keycloakx` 是社区维护度最高的**官方通用** Keycloak chart（Quarkus 版），无任何厂商定制。
- **为什么不 vendor `~/Downloads/keycloak/keycloak`**：那份是**华为 CCE 定制 fork**（keycloakx **2.3.0** / Keycloak 22.0.5）——模板硬引用 `tenant-management-service-server` secret、`PAAS_CRYPTO_PATH` / `ENCRYPT_JGROUPS` 环境、CCE 节点亲和，以及标准镜像里不存在的 `keycloakadm add-mgn` Job 命令。在通用 k8s 上它的 Pod / Job **必起不来**，故不采用。
- 参考：[Keycloak 官方项目](https://github.com/keycloak/keycloak)。

---

## 2. 本地如何共存（vendored 子 chart，不走远程依赖）

子 chart **整包 vendor 进 hub 仓**，安装时不联网拉依赖：

```
software-distribution-platform-hub/
└── build/hub/charts/software-distribution-platform-hub/
    ├── Chart.yaml                      # dependencies: name=keycloak, repository=file://charts/keycloak
    ├── Chart.lock                      # 依赖锁定（helm dependency build 生成）
    ├── values.yaml                     # keycloak: 段 —— 参数透传入口
    ├── charts/
    │   ├── keycloak/                   # vendored 子 chart 源码目录（唯一人工维护点）
    │   └── keycloak-7.3.2.tgz          # helm dependency build 的产物（file:// 就地打包）
    └── templates/
        └── keycloak-realm-configmap.yaml   # 项目 realm 预置（CM sdp-keycloak-realm）
```

依赖声明（[`Chart.yaml`](https://github.com/rouroumaibing/software-distribution-platform-hub/blob/main/build/hub/charts/software-distribution-platform-hub/Chart.yaml)）：

```yaml
dependencies:
  - name: keycloak
    version: 7.3.2
    repository: "file://charts/keycloak"   # 本地 vendor，不触发联网
```

**三个必须知道的点**：

1. **`file://` 是本地路径依赖**：`helm dependency build` 会把 `charts/keycloak/` 就地打成 `keycloak-7.3.2.tgz`，**不联外网**。（当初拉取上游 chart 时才需联网一次：`helm pull`。）
2. **子 chart 内部 `name` 已由 `keycloakx` 改为 `keycloak`**：否则与 `dependencies.name: keycloak`、`values.yaml` 的 `keycloak:` 透传作用域对不上，helm 会报「`keycloakx` 依赖缺失」。改名后 `_helpers.tpl` 用 `.Chart.Name` 拼资源名，行为一致。
3. **`charts/` 与 `.tgz` 并存是正常的**：源目录用于人工改动，`.tgz` 是 build 产物；打包交付时（`build/hub/build.sh` → `output/charts`）会把整个 chart 目录随 `charts` 交付，**不改仓内源文件**。

---

## 3. 参数如何传（values 透传链路）

链路：**hub `values.yaml` 的 `keycloak:` 段 → 子 chart 作用域 `keycloak.*`**。即 `keycloak:` 下的每个键，就是 keycloakx chart 的顶层 values。

```yaml
# hub: build/hub/charts/.../values.yaml
keycloak:
  image: { repository: quay.io/keycloak/keycloak, tag: "26.7.4" }
  extraEnv: |            # 首次启动的 admin 引导（见 §7）
    - name: KEYCLOAK_ADMIN
      value: admin
    - name: KEYCLOAK_ADMIN_PASSWORD
      value: "sdp@12345"
  extraVolumes: |        # 挂 realm CM（见 §5）
    - name: sdp-realm-import
      configMap: { name: sdp-keycloak-realm }
  extraVolumeMounts: |
    - name: sdp-realm-import
      mountPath: /opt/keycloak/data/import
      readOnly: true
  args:                  # 替换镜像 CMD，等效 kc.sh start --import-realm
    - "start"
    - "--import-realm"
  database: { vendor: postgres, hostname: postgres.sdp-workflow.svc, port: 5432, database: sdp, username: sdp, password: sdp }
  http: { relativePath: /keycloak }    # ⚠️ 不能用 Keycloak 默认的 /auth，见「坑 4」
  serviceAccount: { create: false }
  ingress:                             # 对外入口：同域名 + /keycloak 前缀（nginx-ingress 最长前缀路由）
    enabled: true
    ingressClassName: nginx
    servicePort: http
    annotations: { nginx.ingress.kubernetes.io/proxy-buffer-size: 128k }
    rules:
      - host: www.sdpworkflow.com
        paths:
          - { path: /keycloak, pathType: Prefix }
    tls:
      - hosts: [www.sdpworkflow.com]
        secretName: console-ingress-tls   # 与 console 共用同一 host 证书；改名需两 chart 同步
  proxy: { enabled: true, mode: xforwarded }   # ⚠️ 不是 keycloakx 默认的 forwarded，见「坑 5」
```

| 参数 | 作用 | 一句话说明 |
| --- | --- | --- |
| `image` | 镜像 | 固定 Keycloak 26.7.4，与 chart `appVersion` 对齐 |
| `extraEnv` | 附加环境变量 | 首次启动引导 admin 账号（`KEYCLOAK_ADMIN*`） |
| `extraVolumes` / `extraVolumeMounts` | 卷 / 挂载 | 把 realm ConfigMap 挂进 `/opt/keycloak/data/import` |
| `args` | 启动参数 | **替换**镜像 CMD：`start --import-realm` |
| `database.*` | 数据库 | 接本平台 postgres；chart 自动拼 `KC_DB_URL_*` 等环境 |
| `http.relativePath` | HTTP 相对路径 | **`/keycloak`** —— 刻意不用默认 `/auth`（会撞 console SPA 的 `/auth/callback`），见「坑 4」 |
| `ingress.*` | 对外入口 | 同域名 `www.sdpworkflow.com` + 前缀 `/keycloak`；TLS 复用 console 的 `console-ingress-tls`；**不加 `rewrite-target`**（该前缀就是 keycloak 的真实路径） |
| `proxy` | 反代模式 | **`xforwarded`**（不是 keycloakx 默认的 `forwarded`）—— 解析 `X-Forwarded-*`，见「坑 5」 |
| `serviceAccount.create` | SA | 复用默认 SA（`false`） |

**hub 自身的 OIDC 校验参数（顶层 `auth:` 段，与子 chart 无关）**

上表是**子 chart** 的参数（作用域 `keycloak.*`）。hub **自己**的鉴权开关是**另一个顶层键** `auth:`——它渲染进 hub Deployment 的环境变量（`KEYCLOAK_ISSUER` / `KEYCLOAK_CLIENT_ID`），与子 chart 互不相干：

```yaml
# hub: build/hub/charts/.../values.yaml
auth:
  keycloakIssuerUrl: ""          # 空 => 关闭鉴权（dev 默认）
  keycloakClientId: "sdp-console"
```

| 参数 | 渲染为 | 一句话说明 |
| --- | --- | --- |
| `auth.keycloakIssuerUrl` | `KEYCLOAK_ISSUER` | realm 的公开地址；**空 = 关闭鉴权**。模板会去掉末尾斜杠，避免 `iss` 对不上 |
| `auth.keycloakClientId` | `KEYCLOAK_CLIENT_ID` | 校验令牌 `azp`；须与 console 的 `keycloakClientId` 相同 |

> **键名刻意与 console chart 的 `auth.*` 对齐**（同名 `keycloakIssuerUrl` / `keycloakClientId`），使同一份 values 可同时喂两端、避免两端 issuer 漂移。
> ⚠️ `auth`（hub 自身）与 `keycloak`（子 chart）是**两个不同的顶层键**，勿混。

**五个坑（都踩过）**：

1. **`args` 会替换镜像 CMD（不是追加）** —— 必须写全 `start --import-realm`；只写 `--import-realm` 会因缺子命令而启动失败。
2. **`extraVolumes` / `extraVolumeMounts` 是字符串（经 `tpl` 注入）**，不是 YAML 列表 —— 用 `|` 块标量写。
3. **命名空间**：hub chart 自己的模板（含 realm CM）注入 `metadata.namespace: {{ .Values.namespace }}`（默认 `sdp-workflow`）；子 chart 的资源用 `.Release.Namespace`，随 `helm -n sdp-workflow` 一并落该命名空间。
4. **`http.relativePath` 不能用默认的 `/auth`** —— console 是 SPA，它的 OIDC 回调路由就是 **`/auth/callback`**（`console/src/router/index.ts:14`）。若 keycloak 占住 `/auth` 前缀，nginx-ingress 会按**最长前缀**把 `https://<host>/auth/callback` 路由到 **keycloak**，登录回调直接失败。故本项目改走专属前缀 **`/keycloak`**（console 侧零占用）。
   **结构性隔离 > 依赖路由优先级**：不要用"再给 `/auth/callback` 加一条更长的 console 规则"来绕——那是跨 chart 的隐式优先级，任一侧改了路径就静默失效。
5. **`proxy.mode` 必须是 `xforwarded`，不是 chart 默认的 `forwarded`** —— Keycloak 官方语义：`forwarded` 解析 **RFC 7239 的 `Forwarded`** 头，`xforwarded` 解析 **`X-Forwarded-*`**。而本仓 nginx-ingress（`deploy/manifests/05-ingress-nginx.yaml`，controller ConfigMap 为原版 `data: null`）**只发 `X-Forwarded-*`，不发 RFC 7239 `Forwarded`**。用 `forwarded` 的后果：keycloak 取不到原始 scheme/host → 令牌 `iss` 被推导成集群内地址（`http://hub-keycloak-http.<ns>.svc/...`）→ hub 按配置的 issuer 校验**必然失败**。另：完全不设 `proxy-headers` 时，经代理的请求会因 origin 校验直接 **403**，所以此项必设。

**资源命名规则**：子 chart 资源名 = `<release>-keycloak…`。默认部署 release 名为 **`hub`**（见 §4），故实际是：

| 资源 | 名字 |
| --- | --- |
| StatefulSet | `hub-keycloak` |
| Service（HTTP） | `hub-keycloak-http` |
| Service（headless，JGroups） | `hub-keycloak-headless` |
| DB 密码 Secret（chart 自动生成） | `hub-keycloak-database` |
| realm ConfigMap（本项目模板） | `sdp-keycloak-realm` |
| Ingress（对外 `/keycloak`） | `hub-keycloak` |

---

## 4. 安装步骤

**前置**：命名空间 + postgres 已就绪（keycloak 复用本平台 postgres；chart 里**不含** postgres）。

```bash
# 1) 前置依赖（若尚未装）
kubectl apply -f deploy/manifests/00-namespace.yaml       # ns sdp-workflow
kubectl apply -f deploy/manifests/10-postgres.yaml        # postgres（keycloak 的 DB）
kubectl -n sdp-workflow rollout status deploy/postgres --timeout=180s

# 2) 构建子 chart 依赖（本地 file://，不联网；产物 charts/keycloak-7.3.2.tgz）
helm dependency build build/hub/charts/software-distribution-platform-hub

# 3) 安装 / 升级（keycloak 随 hub 一次装齐，无需单独安装 keycloak）
helm upgrade --install hub build/hub/charts/software-distribution-platform-hub \
  --namespace sdp-workflow

# 4) 验证
kubectl -n sdp-workflow get pods -l app.kubernetes.io/name=keycloak   # hub-keycloak-0 Running
kubectl -n sdp-workflow logs hub-keycloak-0 | grep -i "import"        # 看到 realm 导入日志
kubectl -n sdp-workflow get ingress hub-keycloak                      # /keycloak -> hub-keycloak-http(http)
# issuer 可达性（浏览器与 hub 都要能取到 discovery 文档）：
curl -k https://www.sdpworkflow.com/keycloak/realms/sdp/.well-known/openid-configuration

# 5) 验证预置账号 admin 可登录（password grant 直连 realm；sdp-console 已开 directAccessGrants）
curl -k -s -X POST https://www.sdpworkflow.com/keycloak/realms/sdp/protocol/openid-connect/token \
  -d grant_type=password -d client_id=sdp-console \
  -d username=admin -d password='sdp@12345' | head -c 160
# 返回包含 "access_token" 即成功；invalid_grant = 用户/密码不对或 realm 未导入
```

- 走交付形态时，`build/hub/build.sh` 会自动 `helm dependency build` + 把 `charts/` 复制进 `output/charts` 再打包（见 hub 仓 `build/hub/build.sh`），无需手工 build。
- **幂等**：`helm upgrade --install` 可重复执行。

**访问管理控制台**（两种方式：ingress 对外，或本地端口转发）：

```bash
# A) 对外（ingress 已开）：https://www.sdpworkflow.com/keycloak/admin/
# B) 本地端口转发：
kubectl -n sdp-workflow port-forward svc/hub-keycloak-http 8080:80
# 浏览器打开 http://localhost:8080/keycloak/admin/   → 用 §7 的 admin 账号登录
```

> HTTP 相对路径由 chart `http.relativePath` 决定；本项目**刻意设为 `/keycloak`**（不是 keycloak 默认的 `/auth`）——原因见 §3「坑 4」。
> ⚠️ 该前缀会让 **`/keycloak/admin` 也对外可达**（Prefix 匹配包含管理台）。生产建议给管理台加来源限制，如 `nginx.ingress.kubernetes.io/whitelist-source-range`。

---

## 5. realm 预置内容（一句话说明）

realm 由 [`templates/keycloak-realm-configmap.yaml`](https://github.com/rouroumaibing/software-distribution-platform-hub/blob/main/build/hub/charts/software-distribution-platform-hub/templates/keycloak-realm-configmap.yaml) 定义，ConfigMap `sdp-keycloak-realm` 内嵌 `sdp-realm.json`，经 keycloak 首次启动的 `--import-realm` **自动导入**（DB 已有该 realm 时不会重复覆盖）。

| 预置项 | 内容 | 一句话说明 |
| --- | --- | --- |
| realm | `sdp` | 本项目唯一的域（区别于内置 `master`）；用户 / 客户端 / 角色都挂在它下面 |
| `displayName` | `Software Distribution Platform` | 登录页显示名 |
| `sslRequired` | `none` | 允许非 HTTPS 访问（本地 / 内网联调用；**生产应改 `external`**） |
| `defaultLocale` / `supportedLocales` | `zh-CN` | 登录页默认中文 |
| `accessTokenLifespan` 等 | 300s / 会话 1800s… | 令牌与会话生命周期（与常见默认一致） |
| 客户端 `sdp-console` | **public** + PKCE(S256) | console（SPA）登录用；回调 `https://www.sdpworkflow.com/*`；不存 client secret；`baseUrl` = `/keycloak/realms/sdp/account`（随相对路径） |
| 客户端 `sdp-backend` | **confidential** + service account | 预留的服务间调用客户端（client credentials） |
| 角色 `default-roles-sdp` | 复合角色 | 新用户默认授予（含 `offline_access` / `uma_authorization` / 内置 `account` 自助） |
| 角色 `view` / `edit` / `admin` | 普通 realm 角色 | 与 hub 组件级 RBAC 的**粒度命名对齐**（授权判定仍落 hub，见 §6） |
| 用户 `admin` | **预置的人类登录账号** | realm `sdp` 下的普通用户：用户名 `admin` / 密码 **`sdp@12345`**（`temporary: false`，不强制改密），带 `default-roles-sdp` + `admin` 两个 realm 角色；console 登录用它 |
| 用户 `service-account-sdp-backend` | 服务账号 | `sdp-backend` 客户端自动生成的服务账号（**不是**人类登录账号） |
| protocolMapper `roles` / `groups` | OIDC 映射 | 把 realm 角色、组成员关系写进令牌（hub 当前只消费 `groups`，见 §6） |
| 组 `/org:<slug>`（**由 hub 运行时自动预置**） | 组织载体（**D1 默认 ②**） | 「组织」维度的落点：组**不再靠静态 realm JSON 预置**，而由 hub `orgsvc` 在 `Create` 后幂等 `EnsureGroup("/org:<slug>")`、启动 `ReconcileGroups` 回填存量（`internal/keycloak` Admin 客户端，依赖 `KEYCLOAK_ADMIN_CLIENT_SECRET`；缺失则 dev 不建组只告警）。Keycloak Organizations 的**组织集导入未证实**，故仍走 ② 路径（见 `shared/ACCOUNT-PERMISSION-MODEL.md` §2.1 / §2.3）。**`/org:` 为保留前缀** —— 该类组**不得**作为 `subject_type=group` 的绑定主体（组织不作 RBAC 主体）。**无需**开 realm 的 Organizations 开关（可避免 identity-first 登录流变化）。**真集群 E2E 已验证（2026-09-23）**：hub 注入 issuer+secret 后 `POST /orgs` 201 → KC 组列表出现 `org:e2e-org2`；还原 env 后 dev 姿态恢复 |

**E2E 揪出的三个 KC26 集成坑（2026-09-23，均已修/规避）**：
1. **realm JSON 的 `realmRoles` 装不下 realm-management 客户端角色**：`query-groups` / `manage-users` 是 realm-management **client roles**，写在 user 的 `realmRoles` 里会被 `--import-realm` **静默丢弃**（导入不报错），provisioner 调 Admin API 时 403。修复：改用 user 的 **`clientRoles`: {"realm-management": ["query-groups","manage-users"]}**（已改 `build/hub/charts/.../keycloak-realm-configmap.yaml`，仅新 realm 首次导入生效）；存量 realm 用 kcadm 对 `role-mappings/clients/<realm-management-uuid>` POST 角色数组补授（`add-roles` 在此场景报 `Role not found`，须走 REST）。
2. **issuer 端点形态**：KC 26 实际通告的 issuer 是 `http://hub-keycloak-http/keycloak/realms/sdp`（svc **短名**、默认端口被剥）——hub 的 `KEYCLOAK_ISSUER` 必须与之一字不差，否则 go-oidc 报 issuer mismatch（fatal crash-loop）。
3. **password grant 报 `Account is not fully set up`**：声明式 user profile 下用户缺 `firstName`/`lastName` 会隐式触发 UPDATE_PROFILE，即使 `requiredActions=[]` 也拒绝发 token——E2E 用户必须带全姓名字段。

**说明**：这里**没有直接采用** `~/Downloads/keycloak/realms-config.json` 那份全量导出（realm 名 `console-account`）——它含华为 CCE 定制 protocolMapper（`org_viewer`/`org_admin`）且引用内置 client / role，全量导入易冲突。本表是**按项目内容手写的聚焦版**；如需保留原导出的额外字段（如自定义认证流），在预置 JSON 中增补即可。

**预置账号的密码存法**：realm JSON 里写的是**明文** `credentials[].value`，keycloak 在 `--import-realm` 时自行哈希入库；`temporary: false` 表示不强制首登改密。`--import-realm` **不覆盖已存在的 realm / 用户**，所以改预置值后必须删掉该 realm 再重装才生效（详见 §7）。

---

## 6. 与 console、hub 的交互逻辑

**设计原则（见 [README §5.2](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/README.md)）**：**Keycloak 只管身份 + 组**；业务授权与审批全部落 hub（app 内 RBAC + 审批表）。Keycloak 不是授权中心。

由此推出两条**容易误解**的实际结论（预置 `admin` 账号尤其要留意）：

1. **realm 角色不参与授权**：[`internal/middleware/auth.go`](https://github.com/rouroumaibing/software-distribution-platform-hub/blob/main/internal/middleware/auth.go) 只读 `sub` / `preferred_username` / `email` / `groups` / `azp`，**刻意不读角色**（本 realm 的角色实际写在**顶层 `roles` claim** —— `sdp-console` 上挂的是 `oidc-usermodel-realm-role-mapper`、`claim.name: roles`，**不是** Keycloak 默认的 `realm_access.roles`；按 `realm_access` 去查会误判为「角色没进 token」）。所以给用户加 realm 角色 `admin` 只是 Keycloak 侧的标注，**不会**让它在 hub 里有管理员权限。依据见 [shared/ACCOUNT-PERMISSION-MODEL.md §2.2](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md)。
2. **授权 = hub DB 里的绑定行**：判定走 `platform_role_bindings` / `component_role_bindings`（`subject_type` 支持 `user` 或 `group`）。用 `group` 时匹配的是令牌里的 `groups` claim（由 `sdp-console` 的 `groups` mapper 写入），但**绑定行本身仍要落在 hub DB**。2026-09-22 起有两条变化：① **平台级绑定已有 API**（`/platform-role-bindings`，C-10）；② seed 里**已种一条组绑定** `/sdp-admin` → `sdp-admin`（`cmd/hub/conf/09_rbac_multiorg.sql`）—— **该种子要生效，realm 必须先存在组 `/sdp-admin`**，而当前 realm **无任何组**（claim 为空，见 §5.3），故实际仍需先在 Keycloak 侧建组。组件级绑定仍只能经 API 创建。

> 落到预置 `admin`：它登录后**能看到整个 console 界面**（console 路由守卫只校验「已登录」，见 [`console/src/router/index.ts`](https://github.com/rouroumaibing/software-distribution-platform-console/blob/main/src/router/index.ts)），但**组件级写操作会 403** —— hub 只对少数组件级路由挂 `RequirePermission`（触发流水线 / 审批 / 重派发 / 列出流水线运行），且当前**没有**给任何主体建绑定。要给 `admin` 完整能力，二选一：① 把它设为组件 owner（owner 天然持有 `component-admin`，见 hub DATA-MODEL §7.4）；② 在 console「组件权限」页给它绑 `component-admin`（或建 group 绑定）。

> ✅ **曾经的接线缺口（2026-09-22 已修复，backlog B-18）**：过去有 4 条流水线路由**无法靠绑定获得权限**。`cmd/hub/main.go` 给它们的 `RequirePermission` 传的 ID 参数名都是 `id`，而中间件是把该参数**当组件 ID 用**的，可这些路由的 `:id` 实际是 **pipeline id / run id**：
>
> - `POST /pipelines/:id/runs`（`pipeline:trigger`）
> - `GET /pipelines/:id/runs`（`component:read`）
> - `POST /pipelines/:id/runs/:runId/tasks/:taskName/decision`（`approval:approve`）
> - `POST /runs/:id/redispatch`（`pipeline:trigger`，这里 `:id` 是 **run id**）
>
> 过去的后果：查询永远匹配不到绑定行（pipeline/run 的 UUID 不会等于组件 UUID），⇒ 那 4 条路由对所有人（含组件 owner）都返回 403，**与绑定无关**。
>
> **现状（已修复）**：`middleware.RequirePermission` 改为按 `Requirement.Resource`（component / pipeline / run）解析路径 id，`internal/permission/service/locator.go` 负责反查（run 走 **run → pipeline → component** 两跳）；拒码语义固定为 **401 无身份 / 400 参数非 UUID / 404 反查不到 / 403 确实无权限 / 500 查询本身失败**（故障不再伪装成「没权限」）。因此上面那 4 条路由现在**可以**通过绑定获得权限（组件 owner 天然持有 `component-admin`，见 DATA-MODEL §7.4）。
>
> ⚠️ **仍然成立的一点**：repo 里**没有 seed 任何绑定** ⇒ 在给主体建绑定之前，这些路由依旧会 403。**但这已经是「没配权限」，不是「配了也不生效」。**

**时序**：

```
 浏览器(console SPA)            Keycloak(hub-keycloak)              hub(Go)
      │                              │                               │
      │ 1. 未登录 → signinRedirect   │                               │
      ├─────────────────────────────▶│  登录页(zh-CN)                │
      │    Authorization Code + PKCE │                               │
      │◀─────────────────────────────┤  code                        │
      │ 2. 换 token(含 groups 等)     │                               │
      ├─────────────────────────────▶│                               │
      │◀─── access_token ────────────┤                               │
      │                                                              │
      │ 3. GET /api/v1/...  Authorization: Bearer <access_token>      │
      ├─────────────────────────────────────────────────────────────▶│
      │                                      4. 用 JWKS 验签/过期/issuer/azp
      │                                      5. UserContext: keycloak_id=sub
      │                                         首次登录自动建本地 users 行
      │                                      6. RequirePermission: 组件级 RBAC
      │◀─────────────────────── 响应 / 401 ───────────────────────────┤
```

**权威代码位置**：

| 环节 | 位置 | 一句话 |
| --- | --- | --- |
| hub 令牌校验中间件 | [`internal/middleware/auth.go`](https://github.com/rouroumaibing/software-distribution-platform-hub/blob/main/internal/middleware/auth.go) | 走 **OIDC 标准流程**（discovery → JWKS → 验签）+ 校验 `azp == KEYCLOAK_CLIENT_ID`；读取 `sub`/`preferred_username`/`email`/`groups`。**协议细节（hub = Resource Server、校验清单、fail-fast、不调 introspection/userinfo）见 [shared/ACCOUNT-PERMISSION-MODEL.md §2.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md)** |
| hub 用户上下文 | [`internal/middleware/user_context.go`](https://github.com/rouroumaibing/software-distribution-platform-hub/blob/main/internal/middleware/user_context.go) | 首次登录按 `keycloak_id` 自动建本地 `users` 行（无手工开户步骤） |
| hub 接线 | [`cmd/hub/main.go`](https://github.com/rouroumaibing/software-distribution-platform-hub/blob/main/cmd/hub/main.go) | `AuthDisabled()` 为假才挂 `auth.Middleware()`；组件级路由包 `RequirePermission` |
| hub 配置 | [`internal/config/config.go`](https://github.com/rouroumaibing/software-distribution-platform-hub/blob/main/internal/config/config.go) | `KEYCLOAK_ISSUER`（空=关闭鉴权）、`KEYCLOAK_CLIENT_ID`（默认 `sdp-console`） |
| DB 关联 | [`migrations/0003_keycloak_auth.sql`](https://github.com/rouroumaibing/software-distribution-platform-hub/blob/main/migrations/0003_keycloak_auth.sql) | `users.keycloak_id`（唯一）关联 Keycloak 的 `sub` |
| console 登录 | [`console/src/stores/auth.ts`](https://github.com/rouroumaibing/software-distribution-platform-console/blob/main/src/stores/auth.ts) | oidc-client-ts，Authorization Code + PKCE，`VITE_*` 运行时配置 |
| console 图配置 | [`build/console/.../templates/config.yaml`](https://github.com/rouroumaibing/software-distribution-platform-console/blob/main/build/console/charts/software-distribution-platform-console/templates/config.yaml) | chart `auth.*` → `config.js` 的 `window.__APP_CONFIG__` |

**❗ 当前状态：两端代码就绪，但开关默认关着（本期有意）**

| 端 | 现状 | 依据 |
| --- | --- | --- |
| console | `auth.authDisabled: "true"` —— 跳过 Keycloak，直接进已登录态 | console chart `values.yaml` 的 `auth:` 段 |
| hub | `auth.keycloakIssuerUrl` 默认为**空** → 渲染出 `KEYCLOAK_ISSUER=""` → `AuthDisabled()` 为真 → 不挂鉴权中间件 + dev 用户自动供给 | hub chart `values.yaml` 的 `auth:` 段 → `deployment-hub.yaml` env（已透传） |

**要打开鉴权**（两处需同时改）：

1. **console**：`auth.authDisabled: "false"`，并填 `keycloakIssuerUrl`、`keycloakClientId: sdp-console`、`keycloakRedirectUri`（本地 = `https://www.sdpworkflow.com:8443/auth/callback`）。
2. **hub**：设 `auth.keycloakIssuerUrl`（填 console 用的**同一个** issuer）。模板**已透传**为 `KEYCLOAK_ISSUER` / `KEYCLOAK_CLIENT_ID`（2026-09-21 补齐）；另透传 `KEYCLOAK_ADMIN_CLIENT_SECRET`（org 载体组预置，取值 = realm JSON 里 `sdp-backend` 的 secret 字面量）。
3. **一致性**：console 的 `keycloakClientId` 必须与 hub 的 `KEYCLOAK_CLIENT_ID` 相同（hub 校验令牌 `azp`）。两处键名同名（见 §3），可按同一份 values 下发。
4. **前置（已完成，2026-09-22）**：keycloak 的 `keycloak.ingress` 已关，路由走 Envoy Gateway 的 keycloak HTTPRoute（同域名 `www.sdpworkflow.com`、前缀 `/keycloak`、TLS 复用 `console-ingress-tls`）；`http.relativePath` 已同步为 `/keycloak`，`proxy.mode` 已修为 `xforwarded`（见 §3 坑 4/坑 5）。

### 6.5 真对接已落地（2026-09-23，本地 kind 全链 E2E 通过）

由 `deploy-local.sh` 默认开启（`SKIP_AUTH=1` 退回 dev 姿态），**issuer 三方一字不差** = `https://www.sdpworkflow.com:8443/keycloak/realms/sdp`：

| 侧 | 配置 | 关键点 |
| --- | --- | --- |
| Keycloak | `keycloak.hostname: "https://www.sdpworkflow.com:8443/keycloak"`（KC_HOSTNAME，完整 URL） | ⚠️ **路径必须带上 `/keycloak`**——实测 KC 不把 `http.relativePath` 追加到 KC_HOSTNAME 后面，不带路径时 issuer 通告成 `.../realms/sdp`，网关 `/keycloak` 前缀路由下不可达 |
| 网关 | https listener 端口 **8443**（根 `deploy/gateway-sdp.yaml`） | 与浏览器访问端口/issuer 端口三方一致；listener 443 会令 X-Forwarded-Port=443、issuer 丢端口，而 host 443 映射须重建 kind 集群 |
| hub | `auth.keycloakIssuerUrl`（同 issuer）+ 两个 dev-only 脚手架 | ① hostAliases 指 **envoy svc ClusterIP**（`auth.resolveHostIp`）——**不能指节点 IP**：pod 只能达 nodePort 30k 段，URL 的 `:8443` 对不上；② `auth.trustedCASecret: console-tls` 挂自签 CA + `SSL_CERT_FILE`（Go 系统信任池读该变量） |
| console | `auth.authDisabled=false` + issuer/clientId/redirectUri | ⚠️ helm `--set xxx=false` 解析成 **bool**，模板 `false \| default "true"` 会被 sprig 当零值顶掉——模板须先 `\| toString`（chart config.yaml 已修） |

E2E 证据（全部经网关 https 或 hub API 实测）：discovery 通告 issuer 与配置一字不差；无 token 调 hub API 401（直连与走网关皆验）；带 token `GET /targets` 200、`POST /orgs` 201 且 KC 自动出现 `/org:e2e-auth` 组（provisioner 经公网 issuer 走 Admin API 全链）；console `config.js` 三键注入正确。

**临时密码强制重置**：realm JSON 预置 admin 的 `credentials[].temporary: true`（存量集群以 `UPDATE_PASSWORD` requiredAction 等价落地——KC26 对临时凭据登录也是加该 action），首次登录被 KC 硬性拦截改密；API 可验证：password grant 返回 `400 invalid_grant "Account is not fully set up"`。

> `sdp-console` 是 public client（SPA 无 secret）；hub **不需要**单独建 client —— 它只是被动验签，用的是同一个 console client ID（详见 hub 仓 `internal/middleware/WIRING.md`）。

---

## 7. 用户名 / 密码如何修改

| 对象 | 当前值 | 怎么改 |
| --- | --- | --- |
| **`admin`（管理控制台，realm `master`）** | `admin` / `sdp@12345`（**dev 默认**） | 首次启动由 `keycloak.extraEnv` 的 `KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD` **引导**（仅「master realm 尚无 `admin`」时生效 —— 已用旧口令启动过则改这里无效，须先删该用户或用 `kc.sh bootstrap-admin user` 重置）。<br>① 生产：改成 `valueFrom.secretKeyRef` 引一个 Secret（chart README「Creating a Keycloak Admin User」即此写法）；<br>② 改已有密码：登录控制台 → realm **`master`** → Users → 选中用户 → Credentials → Set password。 |
| **`admin`（realm `sdp`，console 登录用）** | `admin` / **`sdp@12345`**（**临时密码**，预置 `temporary: true` / 存量集群以 `UPDATE_PASSWORD` requiredAction 强制首次改密） | 预置在 realm JSON（`templates/keycloak-realm-configmap.yaml`）的 `users[]`。<br>① **改密（推荐）**：控制台 → realm `sdp` → Users → `admin` → Credentials → Set password（改完不必动 chart，重启也不回滚）；<br>② **改预置值**：改 realm JSON 的 `credentials[].value` 后，**删掉 realm `sdp` 再 `helm upgrade`** —— `--import-realm` 对已存在的 realm / 用户不覆盖；<br>③ **加用户**：同样在 `users[]` 增补，或直接在控制台建。 |
| **realm 普通用户（其他）** | 未预置 | 首次登录**自动开户**（`keycloak_id=sub`），但用户须先在 Keycloak 里存在。手工建用户 / 改密：控制台 `https://www.sdpworkflow.com/keycloak/admin/`（或端口转发后 `http://localhost:8080/keycloak/admin/`）→ realm `sdp` → Users。 |
| **服务账号 `service-account-sdp-backend`** | 凭 `sdp-backend` 客户端 secret | 控制台 → Clients → `sdp-backend` → Credentials 查看/重置。 |
| **console 登录** | 无 client secret | public client + PKCE，**不需要** secret。 |

> ⚠️ `admin` / `sdp@12345`（master 与 realm `sdp` 两处）与 realm JSON 里 `sdp-backend` 的 `secret: "**********"` 都是**开发默认值**，生产务必替换为强凭据并经 Secret 注入（至少把 `KEYCLOAK_ADMIN_PASSWORD` 改成 `valueFrom.secretKeyRef`）。console 登录说明页（`/login-hint`，2026-09-23 落地）会把预置账号批注为「**临时初始密码，仅供首次登录，登录后请立即重置**」并提供 Keycloak 账户控制台（`{issuer}/account`）重置入口；展示值由 console chart values `auth.loginHintUser` / `auth.loginHintPassword`（经 config.js `VITE_LOGIN_HINT_USER/PASSWORD` 注入）提供，**与 realm JSON 同源、改动须两处同步**，生产可置空隐藏凭证块。
>
> ⚠️ 两个 `admin` 是**不同 realm 的两个账号**：`master` 的那个能管 Keycloak 本身（管理台），realm `sdp` 的那个只是 console 的业务账号。dev 刻意用同一口令便于记忆，**改密时务必看清当前 realm**，改错 realm 会出现「密码明明改了却登不上」。
>
> ⚠️ **在 Keycloak 侧删用户 / 改角色，不会回收 hub 侧的绑定行**：hub 的授权是 `platform_role_bindings` / `component_role_bindings` 里的**独立数据**（不动式②：hub 是唯一权限权威），Keycloak 的身份变化**不会**同步过去。人员离职 / 换岗时须**两侧都处理**（Keycloak 停用账号 **+** hub 侧解绑），否则会留下「身份已失效、绑定仍生效」的行。绑定的**到期回收**由 hub 负责（见 [shared/ACCOUNT-PERMISSION-MODEL.md §7.4](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md)）。

---

## 8. 相关文档

- [hub ACCOUNT-PERMISSION-MODEL](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/ACCOUNT-PERMISSION-MODEL.md) —— **下游规范**：账号与权限（三条不动式、鉴权两段式、RBAC 引擎、审计、权限申请审批）。**本文只讲「认证子系统如何部署」；「权限如何判定」以该文为准。**
- [hub API-REFERENCE](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/API-REFERENCE.md) —— API 端点与鉴权约定。
- [hub DATA-MODEL](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/shared/DATA-MODEL.md) —— `users` / 授权模型（§7 授权模型）。
- [README §5.2 授权模型（G7）](https://github.com/rouroumaibing/software-distribution-platform-docs/blob/main/README.md) —— Keycloak（身份+组）/ k8s RBAC / hub 业务授权三者的边界。
- 上游：[codecentric/helm-charts · keycloakx](https://github.com/codecentric/helm-charts/tree/master/charts/keycloakx) · [Keycloak 官方](https://github.com/keycloak/keycloak)。
