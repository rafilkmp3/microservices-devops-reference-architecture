#!/bin/bash
# Performance Benchmark Script for Microservices
# Measures throughput and response times under load

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONFIG_SERVICE_URL="http://localhost:3001"
LOG_SERVICE_URL="http://localhost:3002"
CONCURRENT_USERS=10
REQUESTS_PER_USER=100
TOTAL_REQUESTS=$((CONCURRENT_USERS * REQUESTS_PER_USER))

echo -e "${BLUE}⚡ Starting Performance Benchmarks...${NC}"

# Check if required tools are available
check_tool() {
    if ! command -v $1 &> /dev/null; then
        echo -e "${RED}❌ $1 is required but not installed${NC}"
        echo -e "${YELLOW}Install with: brew install $1 (macOS) or apt-get install $1 (Linux)${NC}"
        exit 1
    fi
}

echo -e "\n${YELLOW}Checking required tools...${NC}"
check_tool "curl"
check_tool "bc"

if command -v ab &> /dev/null; then
    BENCHMARK_TOOL="ab"
    echo -e "${GREEN}✅ Using Apache Bench (ab)${NC}"
elif command -v wrk &> /dev/null; then
    BENCHMARK_TOOL="wrk"
    echo -e "${GREEN}✅ Using wrk${NC}"
else
    echo -e "${YELLOW}⚠️ No advanced benchmark tool found. Using basic curl tests.${NC}"
    BENCHMARK_TOOL="curl"
fi

# Health check before starting
echo -e "\n${YELLOW}Pre-benchmark health check...${NC}"
if ! curl -f -s "$CONFIG_SERVICE_URL/health" > /dev/null; then
    echo -e "${RED}❌ Configuration Service is not healthy${NC}"
    exit 1
fi

if ! curl -f -s "$LOG_SERVICE_URL/health" > /dev/null; then
    echo -e "${RED}❌ Log Aggregator Service is not healthy${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All services are healthy${NC}"

# Configuration Service Benchmarks
echo -e "\n${BLUE}🔧 Benchmarking Configuration Service...${NC}"

case $BENCHMARK_TOOL in
    "ab")
        echo -e "\n${YELLOW}Testing Configuration Retrieval (GET /config)...${NC}"
        ab -n $TOTAL_REQUESTS -c $CONCURRENT_USERS -q "$CONFIG_SERVICE_URL/config" | \
        grep -E "(Requests per second|Time per request|Transfer rate)" || true

        echo -e "\n${YELLOW}Testing Configuration Setting (POST /config/benchmark)...${NC}"
        ab -n $((TOTAL_REQUESTS/2)) -c $((CONCURRENT_USERS/2)) -q \
           -p <(echo '{"key": "benchmark", "value": "test"}') \
           -T "application/json" \
           "$CONFIG_SERVICE_URL/config/benchmark-service" | \
        grep -E "(Requests per second|Time per request|Transfer rate)" || true
        ;;
    
    "wrk")
        echo -e "\n${YELLOW}Testing Configuration Retrieval (GET /config)...${NC}"
        wrk -t4 -c$CONCURRENT_USERS -d30s --latency "$CONFIG_SERVICE_URL/config"

        echo -e "\n${YELLOW}Testing Configuration Setting (POST /config/benchmark)...${NC}"
        wrk -t4 -c$((CONCURRENT_USERS/2)) -d30s --latency \
            -s <(cat << 'EOF'
wrk.method = "POST"
wrk.body   = '{"key": "benchmark", "value": "test"}'
wrk.headers["Content-Type"] = "application/json"
EOF
) "$CONFIG_SERVICE_URL/config/benchmark-service"
        ;;
    
    "curl")
        echo -e "\n${YELLOW}Basic Configuration Service Performance Test...${NC}"
        
        # Warm up
        for i in {1..5}; do
            curl -s "$CONFIG_SERVICE_URL/health" > /dev/null
        done

        # Measure response time
        start_time=$(date +%s.%N)
        for i in $(seq 1 50); do
            curl -s "$CONFIG_SERVICE_URL/config" > /dev/null &
            if (( i % 10 == 0 )); then
                wait  # Wait for batch completion
            fi
        done
        wait
        end_time=$(date +%s.%N)
        
        duration=$(echo "$end_time - $start_time" | bc)
        rps=$(echo "scale=2; 50 / $duration" | bc)
        avg_time=$(echo "scale=3; $duration / 50" | bc)
        
        echo -e "Completed 50 requests in ${duration}s"
        echo -e "Requests per second: ${GREEN}${rps}${NC}"
        echo -e "Average response time: ${GREEN}${avg_time}s${NC}"
        ;;
esac

# Log Aggregator Service Benchmarks
echo -e "\n${BLUE}📊 Benchmarking Log Aggregator Service...${NC}"

case $BENCHMARK_TOOL in
    "ab")
        echo -e "\n${YELLOW}Testing Log Storage (POST /logs)...${NC}"
        ab -n $((TOTAL_REQUESTS/2)) -c $((CONCURRENT_USERS/2)) -q \
           -p <(echo '{"serviceName": "benchmark", "level": "info", "message": "Benchmark test log", "metadata": {"test": true}}') \
           -T "application/json" \
           "$LOG_SERVICE_URL/logs" | \
        grep -E "(Requests per second|Time per request|Transfer rate)" || true

        echo -e "\n${YELLOW}Testing Log Retrieval (GET /logs)...${NC}"
        ab -n $TOTAL_REQUESTS -c $CONCURRENT_USERS -q "$LOG_SERVICE_URL/logs?limit=50" | \
        grep -E "(Requests per second|Time per request|Transfer rate)" || true
        ;;
    
    "wrk")
        echo -e "\n${YELLOW}Testing Log Storage (POST /logs)...${NC}"
        wrk -t4 -c$((CONCURRENT_USERS/2)) -d30s --latency \
            -s <(cat << 'EOF'
wrk.method = "POST"
wrk.body   = '{"serviceName": "benchmark", "level": "info", "message": "Benchmark test log", "metadata": {"test": true}}'
wrk.headers["Content-Type"] = "application/json"
EOF
) "$LOG_SERVICE_URL/logs"

        echo -e "\n${YELLOW}Testing Log Retrieval (GET /logs)...${NC}"
        wrk -t4 -c$CONCURRENT_USERS -d30s --latency "$LOG_SERVICE_URL/logs?limit=50"
        ;;
    
    "curl")
        echo -e "\n${YELLOW}Basic Log Service Performance Test...${NC}"
        
        # Test log storage
        start_time=$(date +%s.%N)
        for i in $(seq 1 50); do
            curl -s -X POST "$LOG_SERVICE_URL/logs" \
                 -H "Content-Type: application/json" \
                 -d '{"serviceName": "benchmark", "level": "info", "message": "Test log '$i'"}' > /dev/null &
            if (( i % 10 == 0 )); then
                wait
            fi
        done
        wait
        end_time=$(date +%s.%N)
        
        duration=$(echo "$end_time - $start_time" | bc)
        rps=$(echo "scale=2; 50 / $duration" | bc)
        avg_time=$(echo "scale=3; $duration / 50" | bc)
        
        echo -e "Log Storage - Completed 50 requests in ${duration}s"
        echo -e "Requests per second: ${GREEN}${rps}${NC}"
        echo -e "Average response time: ${GREEN}${avg_time}s${NC}"
        
        # Test log retrieval
        start_time=$(date +%s.%N)
        for i in $(seq 1 50); do
            curl -s "$LOG_SERVICE_URL/logs?limit=10" > /dev/null &
            if (( i % 10 == 0 )); then
                wait
            fi
        done
        wait
        end_time=$(date +%s.%N)
        
        duration=$(echo "$end_time - $start_time" | bc)
        rps=$(echo "scale=2; 50 / $duration" | bc)
        avg_time=$(echo "scale=3; $duration / 50" | bc)
        
        echo -e "Log Retrieval - Completed 50 requests in ${duration}s"
        echo -e "Requests per second: ${GREEN}${rps}${NC}"
        echo -e "Average response time: ${GREEN}${avg_time}s${NC}"
        ;;
esac

# Bulk Operations Benchmark
echo -e "\n${BLUE}📦 Benchmarking Bulk Operations...${NC}"

echo -e "\n${YELLOW}Testing Bulk Log Storage...${NC}"
bulk_payload='{
    "logs": [
        {"serviceName": "bulk-test", "level": "info", "message": "Bulk log 1"},
        {"serviceName": "bulk-test", "level": "warn", "message": "Bulk log 2"},
        {"serviceName": "bulk-test", "level": "error", "message": "Bulk log 3"},
        {"serviceName": "bulk-test", "level": "debug", "message": "Bulk log 4"},
        {"serviceName": "bulk-test", "level": "info", "message": "Bulk log 5"}
    ]
}'

start_time=$(date +%s.%N)
for i in $(seq 1 20); do
    curl -s -X POST "$LOG_SERVICE_URL/logs/bulk" \
         -H "Content-Type: application/json" \
         -d "$bulk_payload" > /dev/null &
    if (( i % 5 == 0 )); then
        wait
    fi
done
wait
end_time=$(date +%s.%N)

duration=$(echo "$end_time - $start_time" | bc)
total_logs=$((20 * 5))  # 20 requests * 5 logs per request
logs_per_second=$(echo "scale=2; $total_logs / $duration" | bc)

echo -e "Bulk Operations - Stored $total_logs logs in ${duration}s"
echo -e "Logs per second: ${GREEN}${logs_per_second}${NC}"

# Resource Usage Check
echo -e "\n${BLUE}📈 Resource Usage Summary...${NC}"

if command -v docker >/dev/null 2>&1; then
    if docker ps --format "table {{.Names}}" | grep -q "configuration-service\|log-aggregator-service"; then
        echo -e "\n${YELLOW}Container resource usage during benchmark:${NC}"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" | \
        grep -E "(NAME|configuration-service|log-aggregator-service)" || true
    fi
fi

# Cleanup benchmark data
echo -e "\n${YELLOW}Cleaning up benchmark data...${NC}"
curl -s -X DELETE "$CONFIG_SERVICE_URL/config/benchmark-service/benchmark" > /dev/null || true

echo -e "\n${GREEN}🎉 Benchmark completed successfully!${NC}"
echo -e "${BLUE}📊 Summary: Check the results above for performance metrics${NC}"

# Recommendations
echo -e "\n${BLUE}💡 Performance Recommendations:${NC}"
echo -e "• For production: Use a proper load balancer and multiple instances"
echo -e "• Monitor response times and scale horizontally when needed"
echo -e "• Consider implementing caching strategies for frequently accessed data"
echo -e "• Use database connection pooling and query optimization"
echo -e "• Implement rate limiting to prevent service overload"