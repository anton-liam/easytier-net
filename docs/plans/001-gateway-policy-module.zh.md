# 出口网关策略模块 (gateway_policy) 实现计划

**目标：** 在 EasyTier fork 内实现 `gateway_policy` 模块，支持 D → A → B → Internet 出口网关策略的下发、执行、健康监控和自动回滚。模块作为 easytier-core 的内部功能，与主进程共生命周期。

**依据：**
- `AGENTS.md` — 网络拓扑、策略模型、状态机设计

**技术栈：** Rust, protobuf, tokio, nftables, iproute2, EasyTier config-server RPC 通道

**状态：** 已完成（代码实现 + 本地编译验证 + 单元测试通过）

---

## 架构决策

### Fork 内部模块方案

```
vendor/EasyTier/easytier/src/
├── gateway_policy/             # 新增：功能模块（feature-gated）
│   ├── mod.rs                  # GatewayPolicyManager + run loop
│   ├── state.rs                # 状态机 (Idle/Applied/Degraded)
│   ├── monitor.rs              # tun0/peer 健康检查
│   └── executor.rs             # nft/ip rule/route 执行与清理
├── proto/
│   ├── gateway_policy.proto    # 新增：消息和 RPC 服务定义
│   └── gateway_policy.rs       # 新增：include 生成代码
├── rpc_service/
│   ├── gateway_policy.rs       # 新增：RPC 服务实现
│   └── api.rs                  # 修改：register_gateway_policy_rpc()
└── web_client/
    └── controller.rs           # 修改：持有 GatewayPolicyManager
```

```
vendor/EasyTier/easytier-web/src/restful/
├── gateway_policy.rs           # 新增：REST API (POST/GET/DELETE)
├── rpc.rs                      # 修改：添加 proxy-rpc 路由
└── mod.rs                      # 修改：注册路由
```

**设计决策记录：**
- Proto 定义**始终编译**（无 feature gate），因为 easytier-web 也需要访问类型定义
- 功能模块 `src/gateway_policy/` 和 RPC 服务用 `#[cfg(feature = "gateway-policy")]` 守护
- RPC 注册通过独立函数 `register_gateway_policy_rpc()` 而非修改 `register_api_rpc_service()` 签名，减少侵入性
- Controller 通过 `set_gateway_policy_manager()` 可选注入 manager

---

## 实现阶段

### 阶段 1：Proto 定义 + 模块骨架 ✅

- [x] 新建 `src/proto/gateway_policy.proto` — 消息定义 + RPC 服务
- [x] 新建 `src/proto/gateway_policy.rs` — include 生成代码
- [x] 新建 `src/gateway_policy/mod.rs` — GatewayPolicyManager 完整实现
- [x] 新建 `src/gateway_policy/state.rs` — 三状态机 + 3 个单元测试
- [x] 修改 `Cargo.toml` — 添加 `gateway-policy = []` feature
- [x] 修改 `src/lib.rs` — `#[cfg(feature = "gateway-policy")] pub mod gateway_policy;`
- [x] 修改 `build/main.rs` — 添加 proto 编译
- [x] 修改 `src/proto/mod.rs` — `pub mod gateway_policy;`（始终编译）
- [x] 验证 `cargo check --features gateway-policy` 编译通过

### 阶段 2：Executor — nft/route 规则执行 ✅

- [x] 实现 `executor.rs` — Source 角色：nft mark + policy route
- [x] 实现 `executor.rs` — Exit 角色：sysctl + masquerade
- [x] 实现 `executor.rs` — 统一清理逻辑（清理时忽略不存在错误）

### 阶段 3：Monitor + Run Loop ✅

- [x] 实现 `monitor.rs` — tun0 存在检查 + peer 可达检查（ping）
- [x] 实现 `mod.rs` — 完整 run loop（tokio::select + 5s interval）
- [x] 实现自动回滚：Applied + tunnel_down → cleanup → Degraded → Idle

### 阶段 4：RPC 服务注册 + Web Client 集成 ✅

- [x] 新建 `rpc_service/gateway_policy.rs` — GatewayPolicyRpcService 实现
- [x] 修改 `rpc_service/mod.rs` — 添加模块声明
- [x] 修改 `rpc_service/api.rs` — 添加 `register_gateway_policy_rpc()` 函数
- [x] 修改 `web_client/controller.rs` — Controller 持有可选 GatewayPolicyManager
- [x] 修改 `scripts/build-openwrt.sh` — `--features gateway-policy`
- [x] 修改 `scripts/build-server.sh` — `--features gateway-policy`
- [x] 验证编译通过

### 阶段 5：Web API ✅

- [x] 新建 `easytier-web/src/restful/gateway_policy.rs` — REST 端点
  - `POST   /api/v1/gateway-policy/:machine-id` — 下发策略
  - `GET    /api/v1/gateway-policy/:machine-id` — 查询状态
  - `DELETE /api/v1/gateway-policy/:machine-id` — 移除策略
- [x] 修改 `restful/rpc.rs` — 添加 proxy-rpc 路由支持
- [x] 修改 `restful/mod.rs` — 注册 gateway_policy 路由
- [x] 验证 `cargo check -p easytier-web` 编译通过
- [x] 单元测试通过（3/3）

### 待完成：集成测试

- [ ] Docker Compose 4 节点拓扑集成测试
- [ ] 测试用例：D→A→B→Internet 转发验证
- [ ] 测试用例：策略还原后网络干净
- [ ] 测试用例：组网断开自动回滚
- [ ] 测试用例：进程退出规则清理

---

## 验证结果

| 验证项 | 状态 |
|--------|------|
| `cargo check --features gateway-policy -p easytier` | ✅ 通过 |
| `cargo check -p easytier-web` | ✅ 通过 |
| `cargo test --features gateway-policy -- gateway_policy` | ✅ 3/3 通过 |
| Docker 交叉编译 | ⏳ 待网络恢复后验证 |

## 关键文件清单

| 文件 | 操作 |
|------|------|
| `vendor/EasyTier/easytier/src/proto/gateway_policy.proto` | 新建 |
| `vendor/EasyTier/easytier/src/proto/gateway_policy.rs` | 新建 |
| `vendor/EasyTier/easytier/src/gateway_policy/mod.rs` | 新建 |
| `vendor/EasyTier/easytier/src/gateway_policy/state.rs` | 新建 |
| `vendor/EasyTier/easytier/src/gateway_policy/monitor.rs` | 新建 |
| `vendor/EasyTier/easytier/src/gateway_policy/executor.rs` | 新建 |
| `vendor/EasyTier/easytier/src/rpc_service/gateway_policy.rs` | 新建 |
| `vendor/EasyTier/easytier-web/src/restful/gateway_policy.rs` | 新建 |
| `vendor/EasyTier/easytier/Cargo.toml` | 修改（feature） |
| `vendor/EasyTier/easytier/build/main.rs` | 修改（proto 编译） |
| `vendor/EasyTier/easytier/src/lib.rs` | 修改（mod 声明） |
| `vendor/EasyTier/easytier/src/proto/mod.rs` | 修改（mod 声明） |
| `vendor/EasyTier/easytier/src/rpc_service/mod.rs` | 修改（mod 声明） |
| `vendor/EasyTier/easytier/src/rpc_service/api.rs` | 修改（RPC 注册函数） |
| `vendor/EasyTier/easytier/src/web_client/controller.rs` | 修改（Manager 持有） |
| `vendor/EasyTier/easytier-web/src/restful/mod.rs` | 修改（路由注册） |
| `vendor/EasyTier/easytier-web/src/restful/rpc.rs` | 修改（proxy-rpc） |
| `scripts/build-openwrt.sh` | 修改（feature flag） |
| `scripts/build-server.sh` | 修改（feature flag） |
