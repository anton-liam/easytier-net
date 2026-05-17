# 003 控制面稳定性和重入兜底 Plan

## 基于 Spec

- `docs/specs/004-control-plane-stability.zh.md`

## 目标

把“任何情况下 A/B 不能与 C 永久失联”落成可验证能力：Agent run loop 具备重入兜底，UTM 环境具备一键稳定性验收入口。

## 阶段 1：Agent Run Loop 重入

目标：`easytier-agent run` 在单次 Web 拉取或上报失败时不退出。

涉及文件：

- `vendor/EasyTier/easytier-agent/src/main.rs`

实施步骤：

1. 增加测试 `run_loop_continues_after_iteration_error`。
2. 抽出 `run_loop_with_iteration`，让单轮失败只记录错误，不终止进程。
3. 保持 `run-once` 行为不变，便于 CI 和人工一次性验证。

验证命令：

```sh
cd /Users/anton/www/easytier-net/.worktrees/gateway-full-tunnel/vendor/EasyTier
cargo test -p easytier-agent run_loop_continues_after_iteration_error
cargo test -p easytier-agent
```

预期结果：

- 单次 iteration 失败后仍继续执行后续 iteration。
- 全量 `easytier-agent` 测试通过。

提交建议：

```sh
git add easytier-agent/src/main.rs
git commit -m "fix(agent): keep run loop alive after transient web errors"
```

## 阶段 2：UTM 稳定性测试入口

目标：从总控仓库根目录一条命令验证 A/B/C 控制面稳定性。

涉及文件：

- `Makefile`
- `scripts/utm-stability-test.sh`

实施步骤：

1. 新增 `make utm-stability-test`。
2. 脚本检查 Docker 以外的真实 UTM 环境，不依赖 containerlab。
3. 脚本通过 SSH 分别检查 A/B。
4. 脚本通过 HTTP 检查 C Web API。
5. 脚本读取 gateway policy snapshot，确认 observed version/status 不错位。

验证命令：

```sh
PATH="/Users/anton/www/easytier-net/build/utm-ssh:$PATH" make utm-stability-test
```

预期结果：

- A/B 均能访问 `http://192.168.64.4:11211/`。
- A/B 到 C 的主路由不经 `easytier` interface。
- Web API 返回当前策略，enabled policy 的 observed source/exit 与 desired version 对齐。

提交建议：

```sh
git add Makefile scripts/utm-stability-test.sh docs/specs/004-control-plane-stability.zh.md docs/plans/003-control-plane-stability-test.zh.md
git commit -m "test: add UTM control plane stability checks"
```

## 阶段 3：故障注入扩展

目标：在可控条件下验证短暂失联后的恢复能力。

涉及文件：

- `scripts/utm-stability-test.sh`

实施步骤：

1. 支持 `UTM_STABILITY_CHAOS=1`。
2. 短暂停止 A/B Agent 进程。
3. 等待 procd 自动恢复 Agent。
4. 重启 C Web 进程。
5. 轮询 A/B 到 C Web 的可达性。
6. 检查 A/B 到 C Web 的路由仍走 underlay。
7. 检查 Web policy snapshot 是否重新出现 observed report。

验证命令：

```sh
PATH="/Users/anton/www/easytier-net/build/utm-ssh:$PATH" UTM_STABILITY_CHAOS=1 make utm-stability-test
```

预期结果：

- 故障注入后 A/B 不永久失联。
- Agent 恢复后 observed state 重新上报。
- 脚本失败时返回非零退出码并输出故障节点。

## 阶段 4：UTM Agent procd 接管

目标：让 A/B 上的 Agent 由 procd 管理，支持故障注入时自动拉起。

涉及文件：

- `Makefile`
- `scripts/utm-configure-agent-service.sh`
- `scripts/openwrt-stage-agent-package.sh`

实施步骤：

1. `openwrt-stage-agent-package.sh` 生成的 init 脚本支持 `interval_seconds`。
2. 新增 `make utm-configure-agent-service`。
3. 通过 UCI 写入 A/B 的 Web URL、user id、machine id、token、EasyTier IPv4、EasyTier iface、执行模式。
4. 启用 `/etc/init.d/easytier-agent enable`。
5. 重启服务并确认 `/etc/init.d/easytier-agent status` 为 `running`。

验证命令：

```sh
PATH="/Users/anton/www/easytier-net/build/utm-ssh:$PATH" make utm-configure-agent-service
PATH="/Users/anton/www/easytier-net/build/utm-ssh:$PATH" make utm-stability-test
```

预期结果：

- A/B 的 `/etc/config/easytier_agent` 中 `enabled=1`。
- A/B 的 Agent 进程由 procd 拉起。
- A/B 的 Agent 命令包含 `--interval-seconds 10`。

## 当前边界

已实现阶段 1、阶段 2、阶段 3 和阶段 4。

当前 chaos 测试覆盖 Agent 进程故障注入、procd 自动重入和 C Web 进程重启；尚未覆盖 EasyTier interface 删除、exit 节点断链和错误路由注入。这些需要在下一阶段补充更细粒度的恢复脚本，且必须保证每个故障注入都有自动恢复命令。
