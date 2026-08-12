cat > README.md << 'EOF'
# GX10 Monitor

ASUS GX10 (NVIDIA DGX Spark) 实时监控脚本

## 功能

- **CPU**: 占用率、核心数
- **内存**: 已用/总计/百分比
- **GPU**: 占用率、温度(含最高值)、功耗(含最高值)
- **Port 8000**: vLLM 连接详情，区分本地/外部/Docker/内网
- **vLLM 状态**: 健康检查、模型名称、实时负载、Token 统计
- **网络速率**: 实时上下行速度

## 安装

```bash
git clone https://github.com/Suplily/gx10_mon.git
cd gx10_mon
chmod +x gx10_monitor.sh
