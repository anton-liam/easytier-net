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
2. 重启 C Web 后轮询 A/B 访问 C Web。
3. 短暂停止 A/B Agent 后恢复进程。
4. 检查 Web policy snapshot 是否重新出现 observed report。

验证命令：

```sh
PATH="/Users/anton/www/easytier-net/build/utm-ssh:$PATH" UTM_STABILITY_CHAOS=1 make utm-stability-test
```

预期结果：

- 故障注入后 A/B 不永久失联。
- Agent 恢复后 observed state 重新上报。
- 脚本失败时返回非零退出码并输出故障节点。

## 当前边界

第一版先实现阶段 1 和阶段 2。阶段 3 需要确认 A/B 上 Agent 已经由 procd 或等价 supervisor 管理，否则脚本不能可靠恢复被停止的进程。
