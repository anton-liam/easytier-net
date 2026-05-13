# 001 Full Tunnel Exit MVP Plan

## 基于 Spec

- `docs/specs/001-product-scope.zh.md`
- `docs/specs/002-full-tunnel-exit-policy.zh.md`

## 目标

实现最小可运行的 full tunnel 出口策略闭环：Web 可选择任意 source/exit 节点，Agent 可安全应用 source 默认路由和 exit forwarding/NAT，切换过程中不丢失 Web/control-plane 连接。

## 阶段 1：整理 fork 工作区

目标：准备 EasyTier 和 LuCI fork 工作区，不改业务代码。

涉及目录：

- `vendor/EasyTier`
- `vendor/luci-app-easytier`
- `.env.example`
- `scripts/vendor-sync.sh`

实施步骤：

1. 新增 `.env.example`，定义 `EASYTIER_REPO`、`EASYTIER_REF`、`LUCI_REPO`、`LUCI_REF`。
2. 调整 `scripts/vendor-sync.sh` 支持 checkout 指定 ref。
3. 执行 `make vendor`。

验证命令：

```sh
make vendor
git -C vendor/EasyTier status --short
git -C vendor/luci-app-easytier status --short
```

预期结果：

- 两个 vendor 工作区存在。
- ref 可由环境变量指定。
- 总控仓库不提交 vendor 内容。

提交建议：

```sh
git add .env.example scripts/vendor-sync.sh
git commit -m "chore: support fork refs for vendor sync"
```

## 阶段 2：创建 Agent MVP 代码骨架

目标：在 EasyTier fork 中创建 `easytier-agent`，只实现 policy 解析、校验和 dry-run plan。

涉及目录：

- `vendor/EasyTier/easytier-agent`
- `vendor/EasyTier/Cargo.toml`

实施步骤：

1. 创建 Rust crate `easytier-agent`。
2. 定义 policy model：
   - `FullTunnelExitPolicy`
   - `DevicePolicy`
   - `DevicePolicyRole`
   - `PolicyStatus`
3. 定义 dry-run plan：
   - source route plan
   - exit forwarding/NAT plan
   - control-plane protected route plan
4. 添加单元测试。

验证命令：

```sh
cd vendor/EasyTier
cargo test -p easytier-agent
```

预期结果：

- policy JSON 可反序列化。
- source/exit device policy 校验通过。
- machine_id 不匹配、source=exit、缺少 exit peer 等错误能失败。
- dry-run plan 输出明确动作，不执行系统命令。

提交建议：

```sh
cd vendor/EasyTier
git add Cargo.toml easytier-agent
git commit -m "feat(agent): add full tunnel policy planner"
```

## 阶段 3：实现 Linux backend

目标：先在 containerlab Linux 容器中跑通 source/exit 行为。

涉及目录：

- `vendor/EasyTier/easytier-agent/src/platform/linux`
- `tests/lab`

实施步骤：

1. 实现 `PlatformBackend` trait。
2. Linux backend 支持：
   - 查询默认路由。
   - 添加 protected host route。
   - 替换 source default route。
   - 开启 IPv4 forwarding。
   - 添加 nftables masquerade/forwarding 规则。
   - 删除指定 source 的 nftables 规则。
3. 所有 apply 操作先支持 `--dry-run`。
4. 增加幂等测试。

验证命令：

```sh
cd vendor/EasyTier
cargo test -p easytier-agent
```

预期结果：

- 重复 apply 不产生重复规则。
- cleanup 只删除指定 source 规则。
- 不影响其它 source 规则。

提交建议：

```sh
cd vendor/EasyTier
git add easytier-agent
git commit -m "feat(agent): implement linux full tunnel backend"
```

## 阶段 4：实现 control-plane 保护和 rollback

目标：保证切换 source 出口时不失联。

涉及目录：

- `vendor/EasyTier/easytier-agent/src/control_plane`
- `vendor/EasyTier/easytier-agent/src/state`
- `vendor/EasyTier/easytier-agent/src/rollback`

实施步骤：

1. Agent 读取 Web/config/relay endpoint。
2. 切换前解析 endpoint IP。
3. 保存 last known good route snapshot。
4. 添加 protected route。
5. 验证 control-plane 可达。
6. 执行 default route 切换。
7. 再次验证 control-plane。
8. 失败时回滚到 snapshot。

验证命令：

```sh
cd vendor/EasyTier
cargo test -p easytier-agent
```

预期结果：

- control-plane 不可达时拒绝切换。
- 切换后 control-plane 失败时执行 rollback。
- rollback 后状态为 `rollbacked`。

提交建议：

```sh
cd vendor/EasyTier
git add easytier-agent
git commit -m "feat(agent): protect control plane during exit switch"
```

## 阶段 5：containerlab E2E

目标：用一键 lab 验证 `node-a -> node-b`、切换、停用、失败回滚。

涉及目录：

- `tests/lab/clab.yml`
- `tests/lab/images`
- `tests/lab/scripts`

实施步骤：

1. 扩展 lab 为 `web`、`node-a`、`node-b`、`node-c`。
2. Docker image 注入 `easytier-agent` 二进制。
3. 添加测试脚本：
   - `test-enable-exit.sh`
   - `test-switch-exit.sh`
   - `test-disable-exit.sh`
   - `test-unreachable-exit-rollback.sh`
4. `make lab-test` 串联执行。

验证命令：

```sh
make lab-up
make lab-test
make lab-down
```

预期结果：

- `node-a -> node-b` 生效。
- `node-a -> node-c` 切换期间 Web/control-plane 检查不中断超过阈值。
- 停用策略后恢复 last known good。
- 不可达 exit 策略进入 `degraded` 或 `rollbacked`。

提交建议：

```sh
git add tests/lab Makefile
git commit -m "test: add full tunnel exit lab checks"
```

## 阶段 6：Web policy/report API MVP

目标：Web 控制台可以保存 logical policy、生成 device policy、接收 Agent runtime report。

涉及目录：

- `vendor/EasyTier/easytier-web/src/restful`
- `vendor/EasyTier/easytier-web/src/db`
- `vendor/EasyTier/easytier-web/src/client_manager`

实施步骤：

1. 新增 policy 表或复用现有存储时增加明确 source/exit policy model。
2. 新增 API：
   - 创建/更新 full tunnel policy。
   - 启用/停用 policy。
   - 查询 desired/observed state。
   - 接收 runtime report。
3. 第一阶段沿用默认鉴权能力。
4. API 不接收任意 shell 命令。

验证命令：

```sh
cd vendor/EasyTier
cargo test -p easytier-web
```

预期结果：

- 同一个 source 不能启用两个 exit policy。
- 一个 exit 可以服务多个 source。
- report 可更新 observed state。

提交建议：

```sh
cd vendor/EasyTier
git add easytier-web
git commit -m "feat(web): add full tunnel policy api"
```

## 阶段 7：OpenWrt backend 和 LuCI MVP

目标：让 iStoreOS/NanoPi R3S 可安装、可配置、可查看状态。

涉及目录：

- `vendor/EasyTier/easytier-agent/src/platform/openwrt`
- `vendor/luci-app-easytier`
- `targets/nanopi-r3s`

实施步骤：

1. OpenWrt backend 使用 `uci firewall -> fw4 reload -> nftables`。
2. LuCI 增加 Agent 配置入口：
   - Web 地址。
   - token。
   - machine id。
3. LuCI 增加状态页：
   - Agent 状态。
   - 当前 policy version。
   - observed exit。
   - last error。
4. target build 接入 package 构建。

验证命令：

```sh
make build TARGET=nanopi-r3s
```

预期结果：

- 生成 NanoPi R3S 构建输入。
- OpenWrt package 可安装。
- procd 可拉起 Agent。

提交建议：

```sh
git add targets/nanopi-r3s
git commit -m "build: wire nanopi r3s agent package target"
```

