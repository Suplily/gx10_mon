[README.md](https://github.com/user-attachments/files/31216136/README.md)
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
# ASUS GX10 即時監控面板

一個 Bash 即時監控腳本，用於 ASUS GX10（NVIDIA DGX Spark）一覽系統、GPU、vLLM 推理服務、網路流量與推論收益，全程免安裝、免背景服務，執行即可用。

## 功能

| 模組 | 監控項目 |
|------|----------|
| **系統** | 運行時間、CPU 使用率、核心數、記憶體使用、本機 IP |
| **GPU** | 使用率、溫度（含運行最高值）、功耗（含運行最高值）、過熱告警 |
| **Port 8000** | vLLM 監聽狀態、連線狀態分佈、本地 / 外部連線數、連線來源分類 |
| **vLLM** | 健康檢查、模型名稱、運行 / 等待請求、KV Cache 使用率、Prefix Cache 命中率、完成統計 |
| **網路** | 即時上下行速率（自動換算 B/s、KB/s、MB/s、GB/s） |
| **收益** | Token 統計與推論收益估算，區分「本次啟動」與「本機累計」 |

## 安裝

```bash
git clone https://github.com/Suplily/gx10_mon.git
cd gx10_mon
chmod +x gx10_monitor.sh
```

## 使用

```bash
./gx10_monitor.sh
```

- 畫面刷新間隔：**2 秒**
- vLLM 狀態刷新：**30 秒**（每 15 個循環）
- 按 `Ctrl+C` 結束

## 配置

腳本內建 vLLM API Key 為 `asus1234`，如需修改請編輯腳本第 12 行：

```bash
API_KEY="your_api_key"
```

## 收益計算

腳本會依目前模型名稱自動比對定價表（`match_price`），將 vLLM 的輸入 / 輸出 Token 換算成推論收益（元）：

```
收益 = 輸入 Token / 1,000,000 × 輸入單價 + 輸出 Token / 1,000,000 × 輸出單價
```

內建定價表如下（單位：元 / 百萬 Token）：

| 模型 | 輸入單價 | 輸出單價 |
|------|:------:|:------:|
| DeepSeek-V4-Flash | 1.0 | 2.0 |
| DeepSeek-V4-Pro | 3.0 | 6.0 |
| Qwen3.8-Max | 14.0 | 43.0 |
| Qwen3.7-Max | 9.0 | 27.0 |
| Qwen3.7-Flash | 0.2 | 1.0 |
| Qwen3.6-Max | 9.0 | 56.0 |
| Qwen3.6-Plus | 4.0 | 22.0 |
| Qwen3.6-35B-A3B | 1.0 | 7.0 |
| Qwen3.5-397B | 4.0 | 26.0 |
| Qwen3.5-Plus | 3.0 | 17.0 |
| Qwen3.5-Flash | 1.0 | 3.0 |
| 未知模型 | 3.0 | 6.0 |

- **本次啟動**：顯示目前 vLLM 進程啟動以來的 Token 與收益。
- **本機累計**：包含先前所有啟動的累計值。當 vLLM 重啟導致計數器歸零時，腳本會自動把重啟前的數值加進累計，跨重啟也不漏算。
- 定價表不符需求時，可直接修改腳本內的 `match_price` 函式。

## 狀態提示與連線分類

- 當前 GPU 溫度高於 **83°C** 以紅色顯示；運行期間最高溫超過 **85°C** 會出現藍色告警（GX10 的 GPU Slowdown Temp Point 為 86°C，請留意散熱環境）。
- Port 8000 連線來源分類規則：

| 標籤 | 來源 |
|------|------|
| `本地` | `127.0.0.1` / `::1` |
| `容器` | `172.16.x.x` ~ `172.31.x.x` |
| `內網` | `192.168.x.x` / `10.x.x` |
| `外部` | 其他 IP |

- 連線狀態縮寫：`L` = LISTEN（監聽）、`E` = ESTABLISHED（已建立）、`TW` = TIME-WAIT、`CW` = CLOSE-WAIT、`FW` = FIN-WAIT。
- `KV` 為 GPU KV Cache 使用率，`Prefix` 為 Prefix Cache 命中率。

## 暫存檔案

腳本會將累計與計算所需的狀態存放在 `/tmp` 下，重啟腳本或 vLLM 不影響本機累計：

| 檔案 | 用途 |
|------|------|
| `/tmp/gx10_max_temp` | GPU 運行最高溫 |
| `/tmp/gx10_max_power` | GPU 運行最高功耗 |
| `/tmp/gx10_acc_tokens` | Token 本機累計值 |
| `/tmp/gx10_last_tokens` | 上次讀取的 Token 計數 |
| `/tmp/gx10_vllm_cache` | vLLM 狀態快取 |
| `/tmp/gx10_net_stat` | 網路速率計算用快照 |
| `/tmp/gx10_model_name` | 目前模型名稱 |

## 依賴

- `nvidia-smi` — GPU 監控
- `ss`（iproute2）— 連線狀態查看
- `curl` — vLLM API 呼叫
- `python3` — JSON 解析
- `free`、`top`、`uptime`、`nproc`、`awk`、`grep` — 系統資訊

## 效果預覽

```
┌────────────────────────────────────────┐
│      ASUS GX10 即時監控面板           │
└────────────────────────────────────────┘

[系統] 機台:gx10 | 運行:1h45m
         CPU:7%(20核) | 記憶體:102G/121G(84%)
         IP:192.168.1.100

[GPU]  使用率:92% | 54°C(最高:85°C) | 32W(最高:94W)

[Port8000] 監聽中 | 總:33 L:2 E:3 TW:26 CW:1 FW:1
         本地:4 | 外部:1 | 127.0.0.1×4[本地] 172.17.0.2×1[容器]

[vLLM] 健康:正常 | 模型:nvidia/Qwen3.6-35B-A3B-NVFP4
         運行:1 等待:0 | KV:2.8% | Prefix:90.4%
         完成:正常1.2K 截斷45 中斷12

[網路] ↓14Mi/s ↑49Mi/s

[收益] 定價:Qwen3.6-35B-A3B 輸入1元/百萬 輸出7元/百萬
         本次啟動:輸入24.7M 輸出426.8K | 收益:27.69元
         本機累計:輸入56.1M 輸出1.2M | 收益:64.50元

刷新: 17:36:54 | Ctrl+C 結束
```

## License

MIT

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
