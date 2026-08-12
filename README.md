# GX10 Monitor

ASUS GX10 (NVIDIA DGX Spark) 实时监控脚本，一站式查看系统运行状态与 vLLM 推理服务负载。

## 功能

| 模块 | 监控项 |
|------|--------|
| **系统** | 运行时间、CPU 占用率、核心数、内存使用 |
| **GPU** | 占用率、温度（含最高值）、功耗（含最高值） |
| **Port 8000** | vLLM 连接详情，区分本地 / 外部 / Docker / 内网 |
| **vLLM 状态** | 健康检查、模型名称、实时负载、Token 统计 |
| **网络** | 实时上下行速率 |

## 安装

```bash
git clone https://github.com/Suplily/gx10_mon.git
cd gx10_mon
chmod +x gx10_monitor.sh
```

## 使用

```bash
./gx10_monitor.sh
```

- 刷新间隔：**2 秒**
- vLLM 状态刷新：**30 秒**
- 按 `Ctrl+C` 退出

## 配置

脚本内置 vLLM API Key 为 `asus1234`，如需修改请编辑脚本第 12 行：

```bash
API_KEY="your_api_key"
```

## 依赖

- `nvidia-smi` — GPU 监控
- `ss` / `lsof` — 端口连接查看
- `curl` — vLLM API 调用
- `python3` — JSON 解析

## 效果预览

```
┌────────────────────────────────────────┐
│      ASUS GX10 实时监控面板           │
└────────────────────────────────────────┘

[系统] 运行:1h45m | CPU:7%(20核) | 内存:102G/121G(84%)
[GPU]  占用:92% | 54°C(高:85°C) | 32W(高:94W)

[Port8000] 监听中 | 总:33 L:2 E:3 TW:26 CW:1 FW:1
         本地:4 | 外部:1 | 127.0.0.1×4[本地] 172.17.0.2×1[容器]

[vLLM] 健康:正常 | 模型:nvidia/Qwen3.6-35B-A3B-NVFP4
         运行:1 等待:0 | KV:2.8% | Prefix:90.4%
         Prompt:24.7M Gen:426.8K | 完成:正常1.2K 截断45 中断12

[网络] ↓14Mi/s ↑49Mi/s

刷新: 17:36:54 | Ctrl+C 退出
```

## 指标说明

| 缩写 | 含义 |
|------|------|
| `L` | LISTEN（监听） |
| `E` | ESTABLISHED（已建立） |
| `TW` | TIME-WAIT |
| `CW` | CLOSE-WAIT |
| `FW` | FIN-WAIT |
| `KV` | GPU KV Cache 使用率 |
| `Prefix` | Prefix Cache 命中率 |

## License

MIT
