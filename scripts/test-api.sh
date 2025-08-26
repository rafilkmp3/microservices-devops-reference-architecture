#!/bin/bash
# API Test Script for Microservices
# Tests all API endpoints to ensure services are running correctly

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
TIMEOUT=10

echo -e "${BLUE}🌐 Starting API Tests...${NC}"

# Test Configuration Service Health
echo -e "\n${YELLOW}Testing Configuration Service...${NC}"
if curl -f -s -m $TIMEOUT "$CONFIG_SERVICE_URL/health" > /dev/null; then
    echo -e "${GREEN}✅ Configuration Service health check passed${NC}"
else
    echo -e "${RED}❌ Configuration Service health check failed${NC}"
    exit 1
fi

# Test Configuration Service API
echo "Testing Configuration Service API endpoints..."

# Test setting a configuration
echo "Setting test configuration..."
if curl -f -s -m $TIMEOUT -X POST "$CONFIG_SERVICE_URL/config/test-service" \
    -H "Content-Type: application/json" \
    -d '{"key": "test-key", "value": "test-value"}' > /dev/null; then
    echo -e "${GREEN}✅ Configuration setting works${NC}"
else
    echo -e "${RED}❌ Configuration setting failed${NC}"
    exit 1
fi

# Test getting a configuration
echo "Getting test configuration..."
RESPONSE=$(curl -s -m $TIMEOUT "$CONFIG_SERVICE_URL/config/test-service")
if echo "$RESPONSE" | grep -q "test-key"; then
    echo -e "${GREEN}✅ Configuration retrieval works${NC}"
else
    echo -e "${RED}❌ Configuration retrieval failed${NC}"
    exit 1
fi

# Test getting all configurations
echo "Getting all configurations..."
if curl -f -s -m $TIMEOUT "$CONFIG_SERVICE_URL/config" > /dev/null; then
    echo -e "${GREEN}✅ Get all configurations works${NC}"
else
    echo -e "${RED}❌ Get all configurations failed${NC}"
    exit 1
fi

# Test deleting a configuration
echo "Deleting test configuration..."
if curl -f -s -m $TIMEOUT -X DELETE "$CONFIG_SERVICE_URL/config/test-service/test-key" > /dev/null; then
    echo -e "${GREEN}✅ Configuration deletion works${NC}"
else
    echo -e "${RED}❌ Configuration deletion failed${NC}"
    exit 1
fi

# Test Log Aggregator Service Health
echo -e "\n${YELLOW}Testing Log Aggregator Service...${NC}"
if curl -f -s -m $TIMEOUT "$LOG_SERVICE_URL/health" > /dev/null; then
    echo -e "${GREEN}✅ Log Aggregator Service health check passed${NC}"
else
    echo -e "${RED}❌ Log Aggregator Service health check failed${NC}"
    exit 1
fi

# Test Log Aggregator Service API
echo "Testing Log Aggregator Service API endpoints..."

# Test storing a single log
echo "Storing test log..."
if curl -f -s -m $TIMEOUT -X POST "$LOG_SERVICE_URL/logs" \
    -H "Content-Type: application/json" \
    -d '{"serviceName": "api-test", "level": "info", "message": "API test log", "metadata": {"test": true}}' > /dev/null; then
    echo -e "${GREEN}✅ Single log storage works${NC}"
else
    echo -e "${RED}❌ Single log storage failed${NC}"
    exit 1
fi

# Test bulk log storage
echo "Storing bulk logs..."
if curl -f -s -m $TIMEOUT -X POST "$LOG_SERVICE_URL/logs/bulk" \
    -H "Content-Type: application/json" \
    -d '{
        "logs": [
            {"serviceName": "api-test", "level": "info", "message": "Bulk log 1"},
            {"serviceName": "api-test", "level": "warn", "message": "Bulk log 2"}
        ]
    }' > /dev/null; then
    echo -e "${GREEN}✅ Bulk log storage works${NC}"
else
    echo -e "${RED}❌ Bulk log storage failed${NC}"
    exit 1
fi

# Test log retrieval
echo "Retrieving logs..."
if curl -f -s -m $TIMEOUT "$LOG_SERVICE_URL/logs" > /dev/null; then
    echo -e "${GREEN}✅ Log retrieval works${NC}"
else
    echo -e "${RED}❌ Log retrieval failed${NC}"
    exit 1
fi

# Test recent logs retrieval
echo "Retrieving recent logs..."
if curl -f -s -m $TIMEOUT "$LOG_SERVICE_URL/logs/api-test/recent" > /dev/null; then
    echo -e "${GREEN}✅ Recent logs retrieval works${NC}"
else
    echo -e "${RED}❌ Recent logs retrieval failed${NC}"
    exit 1
fi

# Test statistics
echo "Retrieving log statistics..."
if curl -f -s -m $TIMEOUT "$LOG_SERVICE_URL/stats" > /dev/null; then
    echo -e "${GREEN}✅ Log statistics works${NC}"
else
    echo -e "${RED}❌ Log statistics failed${NC}"
    exit 1
fi

# Test error handling
echo -e "\n${YELLOW}Testing error handling...${NC}"

# Test invalid configuration request
if curl -s -m $TIMEOUT -X POST "$CONFIG_SERVICE_URL/config/test-service" \
    -H "Content-Type: application/json" \
    -d '{"invalid": "data"}' | grep -q "error"; then
    echo -e "${GREEN}✅ Configuration service error handling works${NC}"
else
    echo -e "${RED}❌ Configuration service error handling failed${NC}"
    exit 1
fi

# Test invalid log request
if curl -s -m $TIMEOUT -X POST "$LOG_SERVICE_URL/logs" \
    -H "Content-Type: application/json" \
    -d '{"invalid": "data"}' | grep -q "error"; then
    echo -e "${GREEN}✅ Log service error handling works${NC}"
else
    echo -e "${RED}❌ Log service error handling failed${NC}"
    exit 1
fi

# Test 404 endpoints
if curl -s -m $TIMEOUT "$CONFIG_SERVICE_URL/nonexistent" | grep -q "404\|not found"; then
    echo -e "${GREEN}✅ Configuration service 404 handling works${NC}"
else
    echo -e "${RED}❌ Configuration service 404 handling failed${NC}"
fi

if curl -s -m $TIMEOUT "$LOG_SERVICE_URL/nonexistent" | grep -q "404\|not found"; then
    echo -e "${GREEN}✅ Log service 404 handling works${NC}"
else
    echo -e "${RED}❌ Log service 404 handling failed${NC}"
fi

echo -e "\n${GREEN}🎉 All API tests passed successfully!${NC}"
echo -e "${BLUE}Services are ready for production use.${NC}"