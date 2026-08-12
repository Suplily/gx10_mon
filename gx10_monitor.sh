#!/bin/bash
# ASUS GX10 实时监控面板
# 用于监控 CPU/GPU/内存/网络/Port 8000 vLLM 状态
# 刷新间隔: 2秒 | vLLM 状态刷新: 30秒
# 作者: Suplily
# GitHub: https://github.com/Suplily/gx10_mon/

NET_FILE=/tmp/gx10_net_stat
MAX_TEMP_FILE=/tmp/gx10_max_temp
MAX_PWR_FILE=/tmp/gx10_max_power
VLLM_CACHE=/tmp/gx10_vllm_cache
COUNTER=0
API_KEY="asus1234"

[ -f "$MAX_TEMP_FILE" ] || echo "-1" > "$MAX_TEMP_FILE"
[ -f "$MAX_PWR_FILE" ] || echo "-1" > "$MAX_PWR_FILE"

# 数字格式化: 自动转 K/M/B
fmt_num() {
    local n="$1"
    if [ -z "$n" ] || [ "$n" = "0" ]; then echo "0"; return; fi
    awk -v n="$n" 'BEGIN {
        if (n >= 1000000000) printf "%.2fB", n/1000000000;
        else if (n >= 1000000) printf "%.1fM", n/1000000;
        else if (n >= 1000) printf "%.1fK", n/1000;
        else printf "%d", n;
    }'
}

# 从 metrics 中提取指标值(处理带 label 的格式)
get_metric_val() {
    local metrics="$1"
    local name="$2"
    echo "$metrics" | grep "^$name{" | awk '{print $2}' | tail -1
}

while true; do
    clear
    T=$(date +%s)

    printf "\033[1;36m┌────────────────────────────────────────┐\n"
    printf "│      ASUS GX10 实时监控面板           │\n"
    printf "└────────────────────────────────────────┘\033[0m\n"

    # ── 第1行: 运行时间 + CPU + 内存 ──
    UP=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F',' '{print $1}' | sed 's/.*up //')
    CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/')
    CPU_USED=$(awk "BEGIN {printf \"%d\", 100 - $CPU_IDLE}")
    MEM_LINE=$(free | awk '/^Mem:/{printf "%.0fG/%.0fG(%.0f%%)", $3/1024/1024, $2/1024/1024, $3/$2*100}')
    printf "\n\033[1;33m[系统]\033[0m 运行:%s | CPU:%d%%(%d核) | 内存:%s\n" "$UP" "$CPU_USED" "$(nproc)" "$MEM_LINE"

    # ── 第2行: GPU ──
    GPU_INFO=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw --format=csv,noheader,nounits 2>/dev/null)
    if [ -n "$GPU_INFO" ]; then
        GPU_UTIL=$(echo "$GPU_INFO" | awk -F", " '{print $1}')
        GPU_TEMP=$(echo "$GPU_INFO" | awk -F", " '{print $2}')
        GPU_PWR=$(echo "$GPU_INFO" | awk -F", " '{print $3}')
        MAX_TEMP=$(cat "$MAX_TEMP_FILE")
        MAX_PWR=$(cat "$MAX_PWR_FILE")
        NEW_MAX_TEMP=$(awk -v t="$GPU_TEMP" -v m="$MAX_TEMP" 'BEGIN{if(m==-1 || t>m) print t; else print m}')
        NEW_MAX_PWR=$(awk -v p="$GPU_PWR" -v m="$MAX_PWR" 'BEGIN{if(m==-1 || p>m) print p; else print m}')
        echo "$NEW_MAX_TEMP" > "$MAX_TEMP_FILE"
        echo "$NEW_MAX_PWR" > "$MAX_PWR_FILE"
        printf "\033[1;33m[GPU]\033[0m  占用:%s%% | %s°C(高:%s°C) | %sW(高:%sW)\n" "$GPU_UTIL" "$GPU_TEMP" "$NEW_MAX_TEMP" "$GPU_PWR" "$NEW_MAX_PWR"
    else
        printf "\033[1;33m[GPU]\033[0m  信息获取失败\n"
    fi

    # ── 第3-4行: Port 8000 连接 ──
    printf "\n\033[1;33m[Port8000]\033[0m "
    if ss -tlnp 2>/dev/null | grep -q ":8000 "; then
        ALL_CONN=$(ss -tan 2>/dev/null | grep ":8000" | wc -l)
        ESTAB_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "ESTAB")
        TIMEWAIT_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "TIME-WAIT")
        LISTEN_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "LISTEN")
        CLOSEWAIT_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "CLOSE-WAIT")
        FINWAIT_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "FIN-WAIT")
        printf "\033[1;32m监听中\033[0m | 总:%d L:%d E:%d TW:%d CW:%d FW:%d\n" \
            "$ALL_CONN" "$LISTEN_CONN" "$ESTAB_CONN" "$TIMEWAIT_CONN" "$CLOSEWAIT_CONN" "$FINWAIT_CONN"

        LOCAL_COUNT=$(ss -tnp 2>/dev/null | grep ":8000" | grep -v "LISTEN" | grep -cE "127\.0\.0\.1|::1")
        EXT_COUNT=$(ss -tnp 2>/dev/null | grep ":8000" | grep -v "LISTEN" | grep -vE "127\.0\.0\.1|::1" | wc -l)
        printf "         本地:%d | 外部:%d | " "$LOCAL_COUNT" "$EXT_COUNT"

        ss -tn 2>/dev/null | grep ":8000" | grep -v "LISTEN" | awk '{print $5}' | sed 's/:[0-9]*$//' | sort | uniq -c | sort -rn | awk '{
            ip=$2;
            if(ip=="127.0.0.1" || ip=="::1") tag="本地";
            else if(ip ~ /^172\.(1[6-9]|2[0-9]|3[0-1])\./) tag="容器";
            else if(ip ~ /^192\.168\./ || ip ~ /^10\./) tag="内网";
            else tag="外部";
            printf "%s×%s[%s] ", ip, $1, tag;
        }' | head -c 120
        printf "\n"
    else
        printf "\033[1;31m未监听\033[0m\n"
    fi

    # ── 第5-7行: vLLM 状态 ──
    printf "\n\033[1;33m[vLLM]\033[0m "
    if [ $((COUNTER % 15)) -eq 0 ]; then
        {
            VLLM_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
                -H "Authorization: Bearer $API_KEY" http://localhost:8000/health 2>/dev/null || echo "000")
            if [ "$VLLM_HEALTH" = "200" ]; then
                printf "健康:\033[1;32m正常\033[0m | "
            else
                printf "健康:\033[1;31m异常(%s)\033[0m | " "$VLLM_HEALTH"
            fi

            VLLM_MODELS=$(curl -s --max-time 3 -H "Authorization: Bearer $API_KEY" http://localhost:8000/v1/models 2>/dev/null)
            if [ -z "$VLLM_MODELS" ] || ! echo "$VLLM_MODELS" | grep -q '"data"'; then
                VLLM_MODELS=$(curl -s --max-time 3 http://localhost:8000/v1/models 2>/dev/null)
            fi
            MODEL_NAME=$(echo "$VLLM_MODELS" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    models = data.get('data', [])
    if models:
        print(models[0].get('id', models[0].get('root', 'unknown')))
    else:
        print('无')
except:
    print('解析失败')
" 2>/dev/null)
            printf "模型:%s\n" "$MODEL_NAME"

            METRICS=$(curl -s --max-time 3 http://localhost:8000/metrics 2>/dev/null)
            if [ -n "$METRICS" ]; then
                RUNNING=$(get_metric_val "$METRICS" "vllm:num_requests_running")
                WAITING=$(get_metric_val "$METRICS" "vllm:num_requests_waiting")
                GPU_CACHE=$(get_metric_val "$METRICS" "vllm:kv_cache_usage_perc")
                PREFIX_HITS=$(get_metric_val "$METRICS" "vllm:prefix_cache_hits_total")
                PREFIX_QUERIES=$(get_metric_val "$METRICS" "vllm:prefix_cache_queries_total")

                RUN_INT=$(echo "$RUNNING" | awk '{printf "%d", $1}')
                WAIT_INT=$(echo "$WAITING" | awk '{printf "%d", $1}')

                printf "         运行:\033[1;32m%d\033[0m 等待:%d" "$RUN_INT" "$WAIT_INT"
                [ -n "$GPU_CACHE" ] && printf " | KV:%.1f%%" "$GPU_CACHE"

                if [ -n "$PREFIX_HITS" ] && [ -n "$PREFIX_QUERIES" ] && [ "$PREFIX_QUERIES" != "0" ]; then
                    PREFIX_RATE=$(awk -v h="$PREFIX_HITS" -v q="$PREFIX_QUERIES" 'BEGIN{printf "%.1f", h/q*100}')
                    printf " | Prefix:%s%%" "$PREFIX_RATE"
                fi
                printf "\n"

                PROMPT_TPS=$(get_metric_val "$METRICS" "vllm:prompt_tokens_total")
                GEN_TPS=$(get_metric_val "$METRICS" "vllm:generation_tokens_total")
                if [ -n "$PROMPT_TPS" ] && [ -n "$GEN_TPS" ]; then
                    printf "         Prompt:%s Gen:%s" "$(fmt_num "$PROMPT_TPS")" "$(fmt_num "$GEN_TPS")"
                fi

                STOP_REQS=$(echo "$METRICS" | grep 'vllm:request_success_total{.*finished_reason="stop"' | awk '{print $2}')
                LEN_REQS=$(echo "$METRICS" | grep 'vllm:request_success_total{.*finished_reason="length"' | awk '{print $2}')
                ABORT_REQS=$(echo "$METRICS" | grep 'vllm:request_success_total{.*finished_reason="abort"' | awk '{print $2}')
                if [ -n "$STOP_REQS" ] || [ -n "$LEN_REQS" ]; then
                    printf " | 完成:"
                    [ -n "$STOP_REQS" ] && printf "正常%s " "$(fmt_num "$STOP_REQS")"
                    [ -n "$LEN_REQS" ] && printf "截断%s " "$(fmt_num "$LEN_REQS")"
                    [ -n "$ABORT_REQS" ] && printf "中断%s" "$(fmt_num "$ABORT_REQS")"
                fi
                printf "\n"
            else
                printf "         Metrics 不可用\n"
            fi
        } > "$VLLM_CACHE"
    fi
    [ -f "$VLLM_CACHE" ] && cat "$VLLM_CACHE"

    # ── 第8行: 网络速率 ──
    printf "\n\033[1;33m[网络]\033[0m "
    if [ -f "$NET_FILE" ]; then
        read -r P_T P_RX P_TX < "$NET_FILE" 2>/dev/null
        CURR_RX=$(awk '/eth|enp|wlan/{gsub(/:/,""); rx+=$2} END{print rx+0}' /proc/net/dev)
        CURR_TX=$(awk '/eth|enp|wlan/{gsub(/:/,""); tx+=$10} END{print tx+0}' /proc/net/dev)
        D=$((T - P_T)); [ $D -lt 1 ] && D=1
        RX_S=$(((CURR_RX - P_RX) / D))
        TX_S=$(((CURR_TX - P_TX) / D))
        RX_FMT=$(numfmt --to=iec-i ${RX_S} 2>/dev/null || echo "${RX_S}B")
        TX_FMT=$(numfmt --to=iec-i ${TX_S} 2>/dev/null || echo "${TX_S}B")
        printf "↓%s/s ↑%s/s\n" "$RX_FMT" "$TX_FMT"
    else
        printf "计算中...\n"
    fi
    awk 'BEGIN{print "'$T'"} /eth|enp|wlan/{gsub(/:/,""); rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev > "$NET_FILE"

    printf "\n\033[90m刷新: %s | Ctrl+C 退出\033[0m\n" "$(date +%H:%M:%S)"

    COUNTER=$((COUNTER + 1))
    sleep 2
done
