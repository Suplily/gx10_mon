#!/bin/bash
# ASUS GX10 实时监控面板
# GitHub: https://github.com/Suplily/gx10_mon/

NET_FILE=/tmp/gx10_net_stat
MAX_TEMP_FILE=/tmp/gx10_max_temp
MAX_PWR_FILE=/tmp/gx10_max_power
VLLM_CACHE=/tmp/gx10_vllm_cache
ACC_TOKEN_FILE=/tmp/gx10_acc_tokens
LAST_TOKEN_FILE=/tmp/gx10_last_tokens
COUNTER=0
API_KEY="asus1234"
HOST_NAME=$(hostname)
LOCAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$LOCAL_IP" ] && LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')
[ -z "$LOCAL_IP" ] && LOCAL_IP="N/A"

[ -f "$MAX_TEMP_FILE" ] || echo "-1" > "$MAX_TEMP_FILE"
[ -f "$MAX_PWR_FILE" ] || echo "-1" > "$MAX_PWR_FILE"
[ -f "$ACC_TOKEN_FILE" ] || echo "0 0" > "$ACC_TOKEN_FILE"

# 颜色定义（使用 $'...' 确保转义正确）
C_RED=$'\033[1;31m'
C_GREEN=$'\033[1;32m'
C_YELLOW=$'\033[1;33m'
C_BLUE=$'\033[1;34m'
C_CYAN=$'\033[1;36m'
C_RESET=$'\033[0m'
C_GRAY=$'\033[90m'

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

get_metric_val() {
    local metrics="$1"
    local name="$2"
    echo "$metrics" | grep "^$name{" | awk '{print $2}' | tail -1
}

match_price() {
    local model="$1"
    local lower=$(echo "$model" | tr '[:upper:]' '[:lower:]')

    if echo "$lower" | grep -q "deepseek"; then
        if echo "$lower" | grep -q "flash"; then
            echo "1.0 2.0 DeepSeek-V4-Flash"
        elif echo "$lower" | grep -q "pro"; then
            echo "3.0 6.0 DeepSeek-V4-Pro"
        else
            echo "1.0 2.0 DeepSeek-V4-Flash"
        fi
        return
    fi

    if echo "$lower" | grep -q "qwen"; then
        if echo "$lower" | grep -q "3.8"; then
            echo "14.0 43.0 Qwen3.8-Max"
        elif echo "$lower" | grep -q "3.7"; then
            if echo "$lower" | grep -q "flash"; then
                echo "0.2 1.0 Qwen3.7-Flash"
            else
                echo "9.0 27.0 Qwen3.7-Max"
            fi
        elif echo "$lower" | grep -q "3.6"; then
            if echo "$lower" | grep -q "35b" || echo "$lower" | grep -q "a3b"; then
                echo "1.0 7.0 Qwen3.6-35B-A3B"
            elif echo "$lower" | grep -q "plus"; then
                echo "4.0 22.0 Qwen3.6-Plus"
            elif echo "$lower" | grep -q "max"; then
                echo "9.0 56.0 Qwen3.6-Max"
            else
                echo "1.0 7.0 Qwen3.6-35B-A3B"
            fi
        elif echo "$lower" | grep -q "3.5"; then
            if echo "$lower" | grep -q "397b" || echo "$lower" | grep -q "a17b"; then
                echo "4.0 26.0 Qwen3.5-397B"
            elif echo "$lower" | grep -q "flash"; then
                echo "1.0 3.0 Qwen3.5-Flash"
            elif echo "$lower" | grep -q "plus"; then
                echo "3.0 17.0 Qwen3.5-Plus"
            else
                echo "1.0 3.0 Qwen3.5-Flash"
            fi
        else
            echo "1.0 7.0 Qwen3.6-35B-A3B"
        fi
        return
    fi

    echo "3.0 6.0 未知模型"
}

calc_revenue() {
    local prompt="$1"
    local gen="$2"
    local in_price="$3"
    local out_price="$4"
    awk -v p="$prompt" -v g="$gen" -v ip="$in_price" -v op="$out_price" 'BEGIN{
        revenue = p/1000000*ip + g/1000000*op;
        printf "%.2f", revenue;
    }'
}

# 网络单位格式化：B/s -> KB/s -> MB/s -> GB/s
fmt_net() {
    local n="$1"
    if [ -z "$n" ] || [ "$n" = "0" ]; then echo "0B/s"; return; fi
    awk -v n="$n" 'BEGIN {
        if (n >= 1000000000) printf "%.1fGB/s", n/1000000000;
        else if (n >= 1000000) printf "%.0fMB/s", n/1000000;
        else if (n >= 1000) printf "%.0fKB/s", n/1000;
        else printf "%dB/s", n;
    }'
}

while true; do
    clear
    T=$(date +%s)

    printf "%s┌────────────────────────────────────────┐%s\n" "$C_CYAN" "$C_RESET"
    printf "%s│      ASUS GX10 实时监控面板           │%s\n" "$C_CYAN" "$C_RESET"
    printf "%s└────────────────────────────────────────┘%s\n" "$C_CYAN" "$C_RESET"

    UP=$(uptime -p 2>/dev/null | sed 's/up //' || uptime | awk -F',' '{print $1}' | sed 's/.*up //')
    printf "\n%s[系统]%s 机台:%s%s%s | 运行:%s\n" "$C_YELLOW" "$C_RESET" "$C_CYAN" "$HOST_NAME" "$C_RESET" "$UP"

    CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | sed 's/.*, *\([0-9.]*\)%* id.*/\1/')
    CPU_USED=$(awk "BEGIN {printf \"%d\", 100 - $CPU_IDLE}")
    MEM_LINE=$(free | awk '/^Mem:/{printf "%.0fG/%.0fG(%.0f%%)", $3/1024/1024, $2/1024/1024, $3/$2*100}')
    printf "         CPU:%d%%(%d核) | 内存:%s\n" "$CPU_USED" "$(nproc)" "$MEM_LINE"

    printf "         IP:%s\n" "$LOCAL_IP"

    # ── GPU ──
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

        TEMP_INT=$(echo "$GPU_TEMP" | awk '{printf "%d", $1}')
        MAX_INT=$(echo "$NEW_MAX_TEMP" | awk '{printf "%d", $1}')

        printf "%s[GPU]%s  占用:%s%% | " "$C_YELLOW" "$C_RESET" "$GPU_UTIL"

        # 实时温度颜色
        if [ "$TEMP_INT" -gt 83 ] 2>/dev/null; then
            printf "%s%s°C%s" "$C_RED" "$GPU_TEMP" "$C_RESET"
        else
            printf "%s°C" "$GPU_TEMP"
        fi

        printf "(最高:%s°C) | %sW(最高:%sW)" "$NEW_MAX_TEMP" "$GPU_PWR" "$NEW_MAX_PWR"

        # 最高温度超过85°C显示蓝色告警
        if [ "$MAX_INT" -gt 85 ] 2>/dev/null; then
            printf " %s[GPU最大温度曾达到Slowdown Temp Point 86°C，请检查散热环境]%s" "$C_BLUE" "$C_RESET"
        fi
        printf "\n"
    else
        printf "%s[GPU]%s  信息获取失败\n" "$C_YELLOW" "$C_RESET"
    fi

    printf "\n%s[Port8000]%s " "$C_YELLOW" "$C_RESET"
    if ss -tlnp 2>/dev/null | grep -q ":8000 "; then
        ALL_CONN=$(ss -tan 2>/dev/null | grep ":8000" | wc -l)
        ESTAB_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "ESTAB")
        TIMEWAIT_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "TIME-WAIT")
        LISTEN_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "LISTEN")
        CLOSEWAIT_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "CLOSE-WAIT")
        FINWAIT_CONN=$(ss -tan 2>/dev/null | grep ":8000" | grep -c "FIN-WAIT")
        printf "%s监听中%s | 总:%d L:%d E:%d TW:%d CW:%d FW:%d\n" \
            "$C_GREEN" "$C_RESET" "$ALL_CONN" "$LISTEN_CONN" "$ESTAB_CONN" "$TIMEWAIT_CONN" "$CLOSEWAIT_CONN" "$FINWAIT_CONN"

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
        printf "%s未监听%s\n" "$C_RED" "$C_RESET"
    fi

    printf "\n%s[vLLM]%s " "$C_YELLOW" "$C_RESET"
    if [ $((COUNTER % 15)) -eq 0 ]; then
        {
            VLLM_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
                -H "Authorization: Bearer $API_KEY" http://localhost:8000/health 2>/dev/null || echo "000")
            if [ "$VLLM_HEALTH" = "200" ]; then
                printf "健康:%s正常%s | " "$C_GREEN" "$C_RESET"
            else
                printf "健康:%s异常(%s)%s | " "$C_RED" "$VLLM_HEALTH" "$C_RESET"
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
            echo "$MODEL_NAME" > /tmp/gx10_model_name

            METRICS=$(curl -s --max-time 3 http://localhost:8000/metrics 2>/dev/null)
            if [ -n "$METRICS" ]; then
                RUNNING=$(get_metric_val "$METRICS" "vllm:num_requests_running")
                WAITING=$(get_metric_val "$METRICS" "vllm:num_requests_waiting")
                GPU_CACHE=$(get_metric_val "$METRICS" "vllm:kv_cache_usage_perc")
                PREFIX_HITS=$(get_metric_val "$METRICS" "vllm:prefix_cache_hits_total")
                PREFIX_QUERIES=$(get_metric_val "$METRICS" "vllm:prefix_cache_queries_total")

                RUN_INT=$(echo "$RUNNING" | awk '{printf "%d", $1}')
                WAIT_INT=$(echo "$WAITING" | awk '{printf "%d", $1}')

                printf "         运行:%s%d%s 等待:%d" "$C_GREEN" "$RUN_INT" "$C_RESET" "$WAIT_INT"
                [ -n "$GPU_CACHE" ] && printf " | KV:%.1f%%" "$GPU_CACHE"

                if [ -n "$PREFIX_HITS" ] && [ -n "$PREFIX_QUERIES" ] && [ "$PREFIX_QUERIES" != "0" ]; then
                    PREFIX_RATE=$(awk -v h="$PREFIX_HITS" -v q="$PREFIX_QUERIES" 'BEGIN{printf "%.1f", h/q*100}')
                    printf " | Prefix:%s%%" "$PREFIX_RATE"
                fi
                printf "\n"

                STOP_REQS=$(echo "$METRICS" | grep 'vllm:request_success_total{.*finished_reason="stop"' | awk '{print $2}')
                LEN_REQS=$(echo "$METRICS" | grep 'vllm:request_success_total{.*finished_reason="length"' | awk '{print $2}')
                ABORT_REQS=$(echo "$METRICS" | grep 'vllm:request_success_total{.*finished_reason="abort"' | awk '{print $2}')
                if [ -n "$STOP_REQS" ] || [ -n "$LEN_REQS" ]; then
                    printf "         完成:"
                    [ -n "$STOP_REQS" ] && printf "正常%s " "$(fmt_num "$STOP_REQS")"
                    [ -n "$LEN_REQS" ] && printf "截断%s " "$(fmt_num "$LEN_REQS")"
                    [ -n "$ABORT_REQS" ] && printf "中断%s" "$(fmt_num "$ABORT_REQS")"
                    printf "\n"
                fi

                PROMPT_CUR=$(get_metric_val "$METRICS" "vllm:prompt_tokens_total")
                GEN_CUR=$(get_metric_val "$METRICS" "vllm:generation_tokens_total")

                if [ -n "$PROMPT_CUR" ] && [ -n "$GEN_CUR" ]; then
                    if [ -f "$LAST_TOKEN_FILE" ]; then
                        read -r PROMPT_LAST GEN_LAST < "$LAST_TOKEN_FILE" 2>/dev/null
                        if [ -n "$PROMPT_LAST" ] && [ -n "$GEN_LAST" ]; then
                            PT_CUR_INT=$(echo "$PROMPT_CUR" | awk '{printf "%.0f", $1}')
                            PT_LAST_INT=$(echo "$PROMPT_LAST" | awk '{printf "%.0f", $1}')
                            if [ "$PT_CUR_INT" -lt "$PT_LAST_INT" ] 2>/dev/null; then
                                read -r PROMPT_ACC GEN_ACC < "$ACC_TOKEN_FILE" 2>/dev/null
                                [ -z "$PROMPT_ACC" ] && PROMPT_ACC=0
                                [ -z "$GEN_ACC" ] && GEN_ACC=0
                                NEW_PROMPT_ACC=$(awk -v a="$PROMPT_ACC" -v b="$PROMPT_LAST" 'BEGIN{printf "%.0f", a+b}')
                                NEW_GEN_ACC=$(awk -v a="$GEN_ACC" -v b="$GEN_LAST" 'BEGIN{printf "%.0f", a+b}')
                                echo "$NEW_PROMPT_ACC $NEW_GEN_ACC" > "$ACC_TOKEN_FILE"
                            fi
                        fi
                    fi
                    echo "$PROMPT_CUR $GEN_CUR" > "$LAST_TOKEN_FILE"
                fi
            else
                printf "         Metrics 不可用\n"
            fi
        } > "$VLLM_CACHE"
    fi
    [ -f "$VLLM_CACHE" ] && cat "$VLLM_CACHE"

    # ── 网络速率 ──
    printf "\n%s[网络]%s " "$C_YELLOW" "$C_RESET"
    if [ -f "$NET_FILE" ]; then
        read -r P_T P_RX P_TX < "$NET_FILE" 2>/dev/null
        CURR_RX=$(awk '/eth|enp|wlan/{gsub(/:/,""); rx+=$2} END{print rx+0}' /proc/net/dev)
        CURR_TX=$(awk '/eth|enp|wlan/{gsub(/:/,""); tx+=$10} END{print tx+0}' /proc/net/dev)
        D=$((T - P_T)); [ $D -lt 1 ] && D=1
        RX_S=$(((CURR_RX - P_RX) / D))
        TX_S=$(((CURR_TX - P_TX) / D))
        RX_FMT=$(fmt_net "$RX_S")
        TX_FMT=$(fmt_net "$TX_S")
        printf "↓%s ↑%s\n" "$RX_FMT" "$TX_FMT"
    else
        printf "计算中...\n"
    fi
    awk 'BEGIN{print "'$T'"} /eth|enp|wlan/{gsub(/:/,""); rx+=$2; tx+=$10} END{print rx, tx}' /proc/net/dev > "$NET_FILE"

    # ── 收益 ──
    if [ -f "$LAST_TOKEN_FILE" ] && [ -f /tmp/gx10_model_name ]; then
        MODEL_CUR=$(cat /tmp/gx10_model_name 2>/dev/null)
        if [ -n "$MODEL_CUR" ] && [ "$MODEL_CUR" != "无" ] && [ "$MODEL_CUR" != "解析失败" ]; then
            read -r PROMPT_CUR GEN_CUR < "$LAST_TOKEN_FILE" 2>/dev/null
            read -r PROMPT_ACC GEN_ACC < "$ACC_TOKEN_FILE" 2>/dev/null
            [ -z "$PROMPT_ACC" ] && PROMPT_ACC=0
            [ -z "$GEN_ACC" ] && GEN_ACC=0

            if [ -n "$PROMPT_CUR" ] && [ -n "$GEN_CUR" ]; then
                PROMPT_TOTAL=$(awk -v c="$PROMPT_CUR" -v a="$PROMPT_ACC" 'BEGIN{printf "%.0f", c+a}')
                GEN_TOTAL=$(awk -v c="$GEN_CUR" -v a="$GEN_ACC" 'BEGIN{printf "%.0f", c+a}')

                PRICE_INFO=$(match_price "$MODEL_CUR")
                IN_PRICE=$(echo "$PRICE_INFO" | awk '{print $1}')
                OUT_PRICE=$(echo "$PRICE_INFO" | awk '{print $2}')
                PRICE_MODEL=$(echo "$PRICE_INFO" | awk '{print $3}')

                REV_THIS=$(calc_revenue "$PROMPT_CUR" "$GEN_CUR" "$IN_PRICE" "$OUT_PRICE")
                REV_TOTAL=$(calc_revenue "$PROMPT_TOTAL" "$GEN_TOTAL" "$IN_PRICE" "$OUT_PRICE")

                printf "\n%s[收益]%s 定价:%s 输入%s元/百万 输出%s元/百万\n" \
                    "$C_YELLOW" "$C_RESET" "$PRICE_MODEL" "$IN_PRICE" "$OUT_PRICE"
                printf "         本次启动:输入%s 输出%s | 收益:%s%s元%s\n" \
                    "$(fmt_num "$PROMPT_CUR")" "$(fmt_num "$GEN_CUR")" "$C_GREEN" "$REV_THIS" "$C_RESET"
                printf "         本机累计:输入%s 输出%s | 收益:%s%s元%s\n" \
                    "$(fmt_num "$PROMPT_TOTAL")" "$(fmt_num "$GEN_TOTAL")" "$C_GREEN" "$REV_TOTAL" "$C_RESET"
            fi
        fi
    fi

    printf "\n%s刷新: %s | Ctrl+C 退出%s\n" "$C_GRAY" "$(date +%H:%M:%S)" "$C_RESET"

    COUNTER=$((COUNTER + 1))
    sleep 2
done
