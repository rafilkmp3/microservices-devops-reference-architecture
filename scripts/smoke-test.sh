#!/bin/bash
# Smoke Test Script for Microservices
# Quick verification that all services are operational

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
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
REDIS_HOST="localhost"
REDIS_PORT="6379"
TIMEOUT=5

echo -e "${BLUE}💨 Starting Smoke Tests...${NC}"

# Check if services are reachable
echo -e "\n${YELLOW}Checking service availability...${NC}"

# Test Configuration Service
echo -n "Configuration Service... "
if curl -f -s -m $TIMEOUT "$CONFIG_SERVICE_URL/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ UP${NC}"
else
    echo -e "${RED}❌ DOWN${NC}"
    exit 1
fi

# Test Log Aggregator Service
echo -n "Log Aggregator Service... "
if curl -f -s -m $TIMEOUT "$LOG_SERVICE_URL/health" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ UP${NC}"
else
    echo -e "${RED}❌ DOWN${NC}"
    exit 1
fi

# Check database connectivity
echo -e "\n${YELLOW}Checking database connectivity...${NC}"

# Test MySQL
echo -n "MySQL Database... "
if nc -z -w $TIMEOUT $MYSQL_HOST $MYSQL_PORT 2>/dev/null; then
    echo -e "${GREEN}✅ CONNECTED${NC}"
else
    echo -e "${RED}❌ DISCONNECTED${NC}"
    exit 1
fi

# Test Redis
echo -n "Redis Cache... "
if nc -z -w $TIMEOUT $REDIS_HOST $REDIS_PORT 2>/dev/null; then
    echo -e "${GREEN}✅ CONNECTED${NC}"
else
    echo -e "${RED}❌ DISCONNECTED${NC}"
    exit 1
fi

# Basic functionality tests
echo -e "\n${YELLOW}Testing basic functionality...${NC}"

# Test Configuration Service basic operation
echo -n "Configuration CRUD... "
if curl -f -s -m $TIMEOUT -X POST "$CONFIG_SERVICE_URL/config/smoke-test" \
    -H "Content-Type: application/json" \
    -d '{"key": "smoke", "value": "test"}' > /dev/null 2>&1 && \
   curl -f -s -m $TIMEOUT "$CONFIG_SERVICE_URL/config/smoke-test" | grep -q "smoke" 2>/dev/null; then
    echo -e "${GREEN}✅ WORKING${NC}"
    # Cleanup
    curl -f -s -m $TIMEOUT -X DELETE "$CONFIG_SERVICE_URL/config/smoke-test/smoke" > /dev/null 2>&1
else
    echo -e "${RED}❌ FAILED${NC}"
    exit 1
fi

# Test Log Service basic operation
echo -n "Log Storage... "
if curl -f -s -m $TIMEOUT -X POST "$LOG_SERVICE_URL/logs" \
    -H "Content-Type: application/json" \
    -d '{"serviceName": "smoke-test", "level": "info", "message": "Smoke test log"}' > /dev/null 2>&1; then
    echo -e "${GREEN}✅ WORKING${NC}"
else
    echo -e "${RED}❌ FAILED${NC}"
    exit 1
fi

# Test Log Retrieval
echo -n "Log Retrieval... "
if curl -f -s -m $TIMEOUT "$LOG_SERVICE_URL/logs?serviceName=smoke-test" > /dev/null 2>&1; then
    echo -e "${GREEN}✅ WORKING${NC}"
else
    echo -e "${RED}❌ FAILED${NC}"
    exit 1
fi

# Performance check (response times)
echo -e "\n${YELLOW}Checking response times...${NC}"

# Configuration Service response time
CONFIG_TIME=$(curl -o /dev/null -s -w '%{time_total}' -m $TIMEOUT "$CONFIG_SERVICE_URL/health")
echo -n "Configuration Service response time: "
if (( $(echo "$CONFIG_TIME < 1.0" | bc -l) )); then
    echo -e "${GREEN}${CONFIG_TIME}s ✅${NC}"
else
    echo -e "${YELLOW}${CONFIG_TIME}s ⚠️ SLOW${NC}"
fi

# Log Service response time
LOG_TIME=$(curl -o /dev/null -s -w '%{time_total}' -m $TIMEOUT "$LOG_SERVICE_URL/health")
echo -n "Log Aggregator Service response time: "
if (( $(echo "$LOG_TIME < 1.0" | bc -l) )); then
    echo -e "${GREEN}${LOG_TIME}s ✅${NC}"
else
    echo -e "${YELLOW}${LOG_TIME}s ⚠️ SLOW${NC}"
fi

# Check service memory usage (if running in Docker)
echo -e "\n${YELLOW}Checking resource usage...${NC}"

if command -v docker >/dev/null 2>&1; then
    # Get container stats if available
    if docker ps --format "table {{.Names}}" | grep -q "configuration-service\|log-aggregator-service"; then
        echo "Container resource usage:"
        docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | grep -E "(configuration-service|log-aggregator-service)" || true
    fi
fi

echo -e "\n${GREEN}🎉 All smoke tests passed!${NC}"
echo -e "${BLUE}System is operational and ready.${NC}"

# Summary
echo -e "\n${BLUE}📊 Smoke Test Summary:${NC}"
echo -e "• Configuration Service: ${GREEN}✅ Healthy${NC}"
echo -e "• Log Aggregator Service: ${GREEN}✅ Healthy${NC}"
echo -e "• MySQL Database: ${GREEN}✅ Connected${NC}"
echo -e "• Redis Cache: ${GREEN}✅ Connected${NC}"
echo -e "• Basic Operations: ${GREEN}✅ Working${NC}"
echo -e "• Response Times: $(if (( $(echo "$CONFIG_TIME < 1.0" | bc -l) )) && (( $(echo "$LOG_TIME < 1.0" | bc -l) )); then echo -e "${GREEN}✅ Good${NC}"; else echo -e "${YELLOW}⚠️ Acceptable${NC}"; fi)"