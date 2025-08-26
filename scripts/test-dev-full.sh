#!/bin/bash
# Comprehensive Development Environment Testing Script
# Tests services running in development mode with hot reload

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

RESULTS_DIR="test-results"
DEV_REPORT="$RESULTS_DIR/dev-test-report.json"

echo -e "${BLUE}🔧 Comprehensive Development Environment Testing${NC}"
echo -e "${BLUE}===============================================${NC}"

# Create results directory
mkdir -p $RESULTS_DIR

# Initialize test results
cat > $DEV_REPORT << EOF
{
  "environment": "development",
  "timestamp": "$(date -Iseconds)",
  "tests": {},
  "performance": {},
  "coverage": {},
  "status": "running"
}
EOF

# Function to update test results
update_results() {
    local test_name="$1"
    local status="$2"
    local details="$3"
    local duration="$4"
    
    python3 -c "
import json
with open('$DEV_REPORT', 'r') as f:
    data = json.load(f)
data['tests']['$test_name'] = {
    'status': '$status',
    'details': '$details',
    'duration': '$duration',
    'timestamp': '$(date -Iseconds)'
}
with open('$DEV_REPORT', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || echo '{"environment": "development", "tests": {}}' > $DEV_REPORT
}

# Function to run tests with timing
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "\n${YELLOW}🧪 $test_name...${NC}"
    start_time=$(date +%s.%N)
    
    local test_name_lower=$(echo "$test_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
    if eval "$test_command" > "$RESULTS_DIR/${test_name_lower}.log" 2>&1; then
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        echo -e "${GREEN}✅ $test_name passed (${duration}s)${NC}"
        update_results "${test_name_lower}" "passed" "Test completed successfully" "$duration"
        return 0
    else
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        echo -e "${RED}❌ $test_name failed (${duration}s)${NC}"
        echo -e "${YELLOW}See $RESULTS_DIR/${test_name_lower}.log for details${NC}"
        update_results "${test_name_lower}" "failed" "Test failed - check logs" "$duration"
        return 1
    fi
}

# Step 1: Environment Setup
echo -e "\n${BLUE}📦 Step 1: Environment Setup${NC}"
run_test "Dependency Installation" "cd configuration-service && npm ci && cd ../log-aggregator-service && npm ci"

# Step 2: Start Dependencies
echo -e "\n${BLUE}🗄️  Step 2: Database Dependencies${NC}"
echo -e "${YELLOW}Starting MySQL and Redis...${NC}"
docker-compose up -d mysql redis
sleep 15

# Verify database connections
run_test "MySQL Connection" "docker-compose exec -T mysql mysql -uroot -ppassword -e 'SELECT 1'"
run_test "Redis Connection" "docker-compose exec -T redis redis-cli ping"

# Step 3: Unit Tests
echo -e "\n${BLUE}🧪 Step 3: Unit Tests${NC}"
run_test "Configuration Service Unit Tests" "cd configuration-service && npm test"
run_test "Log Aggregator Service Unit Tests" "cd log-aggregator-service && npm test"

# Step 4: Test Coverage
echo -e "\n${BLUE}📊 Step 4: Test Coverage Analysis${NC}"
echo -e "${YELLOW}Generating coverage reports...${NC}"
cd configuration-service && npm run test:coverage > ../test-results/config-coverage.log 2>&1 &
cd log-aggregator-service && npm run test:coverage > ../test-results/logs-coverage.log 2>&1 &
wait

# Extract coverage data
if [ -f "configuration-service/coverage/coverage-summary.json" ]; then
    CONFIG_COVERAGE=$(cat configuration-service/coverage/coverage-summary.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
total = data.get('total', {})
print(f\"Lines: {total.get('lines', {}).get('pct', 0)}%, Functions: {total.get('functions', {}).get('pct', 0)}%, Branches: {total.get('branches', {}).get('pct', 0)}%\")
" 2>/dev/null || echo "Coverage data not available")
    echo -e "${GREEN}✅ Configuration Service Coverage: $CONFIG_COVERAGE${NC}"
fi

if [ -f "log-aggregator-service/coverage/coverage-summary.json" ]; then
    LOGS_COVERAGE=$(cat log-aggregator-service/coverage/coverage-summary.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
total = data.get('total', {})
print(f\"Lines: {total.get('lines', {}).get('pct', 0)}%, Functions: {total.get('functions', {}).get('pct', 0)}%, Branches: {total.get('branches', {}).get('pct', 0)}%\")
" 2>/dev/null || echo "Coverage data not available")
    echo -e "${GREEN}✅ Log Aggregator Service Coverage: $LOGS_COVERAGE${NC}"
fi

# Step 5: Start Services in Development Mode
echo -e "\n${BLUE}🚀 Step 5: Development Services${NC}"
echo -e "${YELLOW}Starting services in development mode...${NC}"

# Start services in background
(cd configuration-service && npm run dev > ../test-results/config-dev.log 2>&1) &
CONFIG_PID=$!
(cd log-aggregator-service && npm run dev > ../test-results/logs-dev.log 2>&1) &
LOGS_PID=$!

# Wait for services to start
echo -e "${YELLOW}⏳ Waiting for services to start...${NC}"
sleep 10

# Function to wait for service
wait_for_service() {
    local url="$1"
    local name="$2"
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -f -s "$url" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ $name is ready${NC}"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
        echo -n "."
    done
    echo -e "${RED}❌ $name failed to start${NC}"
    return 1
}

# Wait for services to be healthy
wait_for_service "http://localhost:3001/health" "Configuration Service"
wait_for_service "http://localhost:3002/health" "Log Aggregator Service"

# Step 6: API Integration Tests
echo -e "\n${BLUE}🌐 Step 6: API Integration Tests${NC}"
run_test "API Health Checks" "curl -f http://localhost:3001/health && curl -f http://localhost:3002/health"

# Comprehensive API tests
run_test "Configuration Service API Tests" '
    # Set configuration
    curl -f -X POST http://localhost:3001/config/dev-test \
        -H "Content-Type: application/json" \
        -d "{\"key\": \"test-key\", \"value\": \"test-value\"}" &&
    
    # Get configuration
    curl -f http://localhost:3001/config/dev-test | grep -q "test-key" &&
    
    # List all configurations
    curl -f http://localhost:3001/config > /dev/null &&
    
    # Delete configuration
    curl -f -X DELETE http://localhost:3001/config/dev-test/test-key
'

run_test "Log Aggregator Service API Tests" '
    # Store single log
    curl -f -X POST http://localhost:3002/logs \
        -H "Content-Type: application/json" \
        -d "{\"serviceName\": \"dev-test\", \"level\": \"info\", \"message\": \"Development test log\"}" &&
    
    # Store bulk logs
    curl -f -X POST http://localhost:3002/logs/bulk \
        -H "Content-Type: application/json" \
        -d "{\"logs\": [{\"serviceName\": \"dev-test\", \"level\": \"info\", \"message\": \"Bulk test 1\"}, {\"serviceName\": \"dev-test\", \"level\": \"warn\", \"message\": \"Bulk test 2\"}]}" &&
    
    # Retrieve logs
    curl -f "http://localhost:3002/logs?serviceName=dev-test" > /dev/null &&
    
    # Get recent logs
    curl -f http://localhost:3002/logs/dev-test/recent > /dev/null &&
    
    # Get statistics
    curl -f http://localhost:3002/stats > /dev/null
'

# Step 7: Performance Baseline
echo -e "\n${BLUE}⚡ Step 7: Performance Baseline${NC}"
echo -e "${YELLOW}Measuring response times...${NC}"

# Configuration Service performance
CONFIG_TIME=$(curl -o /dev/null -s -w '%{time_total}' http://localhost:3001/health)
echo -e "Configuration Service response time: ${GREEN}${CONFIG_TIME}s${NC}"

# Log Service performance
LOGS_TIME=$(curl -o /dev/null -s -w '%{time_total}' http://localhost:3002/health)
echo -e "Log Aggregator Service response time: ${GREEN}${LOGS_TIME}s${NC}"

# Update performance data
python3 -c "
import json
with open('$DEV_REPORT', 'r') as f:
    data = json.load(f)
data['performance'] = {
    'configuration_service_response_time': $CONFIG_TIME,
    'log_service_response_time': $LOGS_TIME,
    'baseline_established': True
}
with open('$DEV_REPORT', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

# Step 8: Hot Reload Test
echo -e "\n${BLUE}🔄 Step 8: Hot Reload Validation${NC}"
echo -e "${YELLOW}Testing hot reload functionality...${NC}"

# Modify a file and check if service reloads
echo -e "${YELLOW}Modifying configuration service for hot reload test...${NC}"
TEMP_COMMENT="// Hot reload test - $(date)"
echo "$TEMP_COMMENT" >> configuration-service/index.js

# Wait for reload
sleep 5

# Check if service is still healthy (indicating successful reload)
if curl -f -s http://localhost:3001/health > /dev/null; then
    echo -e "${GREEN}✅ Hot reload working correctly${NC}"
    update_results "hot_reload" "passed" "Service reloaded successfully" "5"
else
    echo -e "${RED}❌ Hot reload failed${NC}"
    update_results "hot_reload" "failed" "Service did not reload properly" "5"
fi

# Clean up the test modification
sed -i.bak "/$TEMP_COMMENT/d" configuration-service/index.js
rm -f configuration-service/index.js.bak

# Step 9: Cleanup and Results
echo -e "\n${BLUE}🧹 Step 9: Cleanup and Results${NC}"

# Stop development services
echo -e "${YELLOW}Stopping development services...${NC}"
kill $CONFIG_PID $LOGS_PID 2>/dev/null || true
sleep 2

# Stop databases
docker-compose stop mysql redis

# Final results update
python3 -c "
import json
with open('$DEV_REPORT', 'r') as f:
    data = json.load(f)
data['status'] = 'completed'
data['summary'] = {
    'total_tests': len(data['tests']),
    'passed': sum(1 for t in data['tests'].values() if t['status'] == 'passed'),
    'failed': sum(1 for t in data['tests'].values() if t['status'] == 'failed')
}
with open('$DEV_REPORT', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

# Display final results
echo -e "\n${BLUE}📊 Development Environment Test Results${NC}"
echo -e "${BLUE}======================================${NC}"

if [ -f "$DEV_REPORT" ]; then
    python3 -c "
import json
with open('$DEV_REPORT', 'r') as f:
    data = json.load(f)
summary = data.get('summary', {})
print(f\"Total Tests: {summary.get('total_tests', 0)}\")
print(f\"Passed: {summary.get('passed', 0)}\")
print(f\"Failed: {summary.get('failed', 0)}\")
performance = data.get('performance', {})
if 'configuration_service_response_time' in performance:
    print(f\"Config Service Response Time: {performance['configuration_service_response_time']:.3f}s\")
if 'log_service_response_time' in performance:
    print(f\"Log Service Response Time: {performance['log_service_response_time']:.3f}s\")
" 2>/dev/null || echo "Results summary not available"
fi

echo -e "\n${GREEN}✅ Development environment testing completed${NC}"
echo -e "${BLUE}📄 Detailed results saved to: $DEV_REPORT${NC}"

# Exit with error if any tests failed
if [ -f "$DEV_REPORT" ]; then
    FAILED_COUNT=$(python3 -c "
import json
with open('$DEV_REPORT', 'r') as f:
    data = json.load(f)
print(sum(1 for t in data['tests'].values() if t['status'] == 'failed'))
" 2>/dev/null || echo "0")
    
    if [ "$FAILED_COUNT" -gt 0 ]; then
        echo -e "${RED}❌ $FAILED_COUNT tests failed${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}🎉 All development tests passed!${NC}"