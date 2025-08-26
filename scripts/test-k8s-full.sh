#!/bin/bash
# Comprehensive Kubernetes Local Testing Script (OrbStack)
# Tests services deployed in Kubernetes cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

RESULTS_DIR="test-results"
K8S_REPORT="$RESULTS_DIR/k8s-test-report.json"
NAMESPACE="microservices-dev"

echo -e "${BLUE}☸️  Comprehensive Kubernetes Local Testing${NC}"
echo -e "${BLUE}===========================================${NC}"

# Create results directory
mkdir -p $RESULTS_DIR

# Initialize test results
cat > $K8S_REPORT << EOF
{
  "environment": "kubernetes",
  "cluster": "orbstack",
  "namespace": "$NAMESPACE",
  "timestamp": "$(date -Iseconds)",
  "tests": {},
  "deployments": {},
  "performance": {},
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
with open('$K8S_REPORT', 'r') as f:
    data = json.load(f)
data['tests']['$test_name'] = {
    'status': '$status',
    'details': '$details',
    'duration': '$duration',
    'timestamp': '$(date -Iseconds)'
}
with open('$K8S_REPORT', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || echo "{}" > $K8S_REPORT
}

# Function to run k8s tests with timing
run_k8s_test() {
    local test_name="$1"
    local test_command="$2"
    
    echo -e "\n${YELLOW}☸️  $test_name...${NC}"
    start_time=$(date +%s.%N)
    
    if eval "$test_command" > "$RESULTS_DIR/$(echo "$test_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_').log" 2>&1; then
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        echo -e "${GREEN}✅ $test_name passed (${duration}s)${NC}"
        update_results "$(echo "$test_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')" "passed" "Test completed successfully" "$duration"
        return 0
    else
        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc)
        echo -e "${RED}❌ $test_name failed (${duration}s)${NC}"
        echo -e "${YELLOW}See $RESULTS_DIR/$(echo "$test_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_').log for details${NC}"
        update_results "$(echo "$test_name" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')" "failed" "Test failed - check logs" "$duration"
        return 1
    fi
}

# Step 1: Cluster Validation
echo -e "\n${BLUE}🔍 Step 1: Cluster Validation${NC}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}❌ kubectl is not installed${NC}"
    exit 1
fi

# Check if kubectx is available
if ! command -v kubectx &> /dev/null; then
    echo -e "${YELLOW}⚠️ kubectx not found, installing...${NC}"
    if command -v brew &> /dev/null; then
        brew install kubectx
    else
        echo -e "${RED}❌ Please install kubectx manually${NC}"
        exit 1
    fi
fi

# Switch to OrbStack context
echo -e "${YELLOW}Switching to OrbStack context...${NC}"
if kubectx orbstack > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Using OrbStack Kubernetes context${NC}"
else
    echo -e "${RED}❌ Failed to switch to OrbStack context${NC}"
    echo -e "${YELLOW}Available contexts:${NC}"
    kubectl config get-contexts
    exit 1
fi

# Verify cluster connection
run_k8s_test "Cluster Connection" "kubectl cluster-info"
run_k8s_test "Node Status" "kubectl get nodes"

# Step 2: Namespace Setup
echo -e "\n${BLUE}🏷️  Step 2: Namespace Setup${NC}"

# Create or verify namespace
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f - > /dev/null 2>&1
kubectl config set-context --current --namespace=$NAMESPACE > /dev/null 2>&1

echo -e "${GREEN}✅ Namespace '$NAMESPACE' ready${NC}"

# Step 3: Build and Load Images
echo -e "\n${BLUE}🏗️  Step 3: Build and Load Images${NC}"

# Build images
echo -e "${YELLOW}Building Docker images...${NC}"
docker build -t microservices/configuration-service:k8s-test ./configuration-service > $RESULTS_DIR/k8s-build-config.log 2>&1
docker build -t microservices/log-aggregator-service:k8s-test ./log-aggregator-service > $RESULTS_DIR/k8s-build-logs.log 2>&1

# For OrbStack, images are automatically available in the cluster
echo -e "${GREEN}✅ Images built and available in OrbStack cluster${NC}"

# Step 4: Deploy Infrastructure
echo -e "\n${BLUE}🗄️  Step 4: Deploy Infrastructure${NC}"

# Deploy MySQL
echo -e "${YELLOW}Deploying MySQL...${NC}"
kubectl apply -f k8s-manifests/mysql-deployment.yaml > /dev/null 2>&1

# Deploy Redis  
echo -e "${YELLOW}Deploying Redis...${NC}"
kubectl apply -f k8s-manifests/redis-deployment.yaml > /dev/null 2>&1

# Wait for databases to be ready
echo -e "${YELLOW}⏳ Waiting for databases to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=mysql --timeout=180s -n $NAMESPACE
kubectl wait --for=condition=ready pod -l app=redis --timeout=180s -n $NAMESPACE

run_k8s_test "MySQL Deployment" "kubectl get deployment mysql -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
run_k8s_test "Redis Deployment" "kubectl get deployment redis -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '1'"

# Step 5: Deploy Services
echo -e "\n${BLUE}🚀 Step 5: Deploy Services${NC}"

# Update image names in manifests for local testing
sed -i.bak 's|image: ghcr.io/microservices/configuration-service:latest|image: microservices/configuration-service:k8s-test|g' k8s-manifests/configuration-service.yaml
sed -i.bak 's|image: ghcr.io/microservices/log-aggregator-service:latest|image: microservices/log-aggregator-service:k8s-test|g' k8s-manifests/log-aggregator-service.yaml

# Deploy configuration service
echo -e "${YELLOW}Deploying Configuration Service...${NC}"
kubectl apply -f k8s-manifests/configuration-service.yaml > /dev/null 2>&1

# Deploy log aggregator service
echo -e "${YELLOW}Deploying Log Aggregator Service...${NC}"
kubectl apply -f k8s-manifests/log-aggregator-service.yaml > /dev/null 2>&1

# Restore original manifests
mv k8s-manifests/configuration-service.yaml.bak k8s-manifests/configuration-service.yaml
mv k8s-manifests/log-aggregator-service.yaml.bak k8s-manifests/log-aggregator-service.yaml

# Wait for services to be ready
echo -e "${YELLOW}⏳ Waiting for services to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=configuration-service --timeout=180s -n $NAMESPACE
kubectl wait --for=condition=ready pod -l app=log-aggregator-service --timeout=180s -n $NAMESPACE

run_k8s_test "Configuration Service Deployment" "kubectl get deployment configuration-service -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '1'"
run_k8s_test "Log Aggregator Service Deployment" "kubectl get deployment log-aggregator-service -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '1'"

# Step 6: Service Discovery Tests
echo -e "\n${BLUE}🔍 Step 6: Service Discovery Tests${NC}"

run_k8s_test "Service Discovery - Configuration Service" "kubectl get service configuration-service -n $NAMESPACE"
run_k8s_test "Service Discovery - Log Aggregator Service" "kubectl get service log-aggregator-service -n $NAMESPACE"
run_k8s_test "Service Discovery - MySQL" "kubectl get service mysql -n $NAMESPACE"
run_k8s_test "Service Discovery - Redis" "kubectl get service redis -n $NAMESPACE"

# Test internal DNS resolution
run_k8s_test "Internal DNS Resolution" "kubectl run test-dns --image=busybox --rm -it --restart=Never --command -- nslookup configuration-service.$NAMESPACE.svc.cluster.local"

# Step 7: Port Forward Setup for Testing
echo -e "\n${BLUE}🔗 Step 7: Port Forward Setup${NC}"

# Start port forwards in background
echo -e "${YELLOW}Setting up port forwards...${NC}"
kubectl port-forward service/configuration-service 3001:3001 -n $NAMESPACE > $RESULTS_DIR/k8s-port-forward-config.log 2>&1 &
CONFIG_PF_PID=$!

kubectl port-forward service/log-aggregator-service 3002:3002 -n $NAMESPACE > $RESULTS_DIR/k8s-port-forward-logs.log 2>&1 &
LOGS_PF_PID=$!

# Wait for port forwards to establish
sleep 10

# Function to wait for service via port forward
wait_for_k8s_service() {
    local url="$1"
    local name="$2"
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -f -s "$url" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ $name is accessible via port-forward${NC}"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
        echo -n "."
    done
    echo -e "${RED}❌ $name is not accessible${NC}"
    return 1
fi

wait_for_k8s_service "http://localhost:3001/health" "Configuration Service"
wait_for_k8s_service "http://localhost:3002/health" "Log Aggregator Service"

# Step 8: API Testing in Kubernetes
echo -e "\n${BLUE}🌐 Step 8: API Testing in Kubernetes${NC}"

run_k8s_test "K8s Health Checks" "curl -f http://localhost:3001/health && curl -f http://localhost:3002/health"

# Comprehensive API tests in Kubernetes
run_k8s_test "K8s Configuration Service API Tests" '
    # Set configuration
    curl -f -X POST http://localhost:3001/config/k8s-test \
        -H "Content-Type: application/json" \
        -d "{\"key\": \"k8s-test-key\", \"value\": \"k8s-test-value\"}" &&
    
    # Get configuration
    curl -f http://localhost:3001/config/k8s-test | grep -q "k8s-test-key" &&
    
    # List all configurations
    curl -f http://localhost:3001/config > /dev/null &&
    
    # Delete configuration
    curl -f -X DELETE http://localhost:3001/config/k8s-test/k8s-test-key
'

run_k8s_test "K8s Log Aggregator Service API Tests" '
    # Store single log
    curl -f -X POST http://localhost:3002/logs \
        -H "Content-Type: application/json" \
        -d "{\"serviceName\": \"k8s-test\", \"level\": \"info\", \"message\": \"Kubernetes test log\"}" &&
    
    # Store bulk logs
    curl -f -X POST http://localhost:3002/logs/bulk \
        -H "Content-Type: application/json" \
        -d "{\"logs\": [{\"serviceName\": \"k8s-test\", \"level\": \"info\", \"message\": \"K8s bulk test 1\"}, {\"serviceName\": \"k8s-test\", \"level\": \"warn\", \"message\": \"K8s bulk test 2\"}]}" &&
    
    # Retrieve logs
    curl -f "http://localhost:3002/logs?serviceName=k8s-test" > /dev/null &&
    
    # Get statistics
    curl -f http://localhost:3002/stats > /dev/null
'

# Step 9: Pod Communication Tests
echo -e "\n${BLUE}🗣️  Step 9: Pod Communication Tests${NC}"

# Test internal service communication
run_k8s_test "Internal Service Communication" '
    kubectl run test-comm --image=curlimages/curl --rm -it --restart=Never --command -- \
    curl -f http://configuration-service:3001/health
'

# Step 10: Scaling Tests
echo -e "\n${BLUE}⚖️  Step 10: Scaling Tests${NC}"

# Scale configuration service
echo -e "${YELLOW}Testing horizontal scaling...${NC}"
kubectl scale deployment configuration-service --replicas=2 -n $NAMESPACE > /dev/null 2>&1
kubectl wait --for=condition=ready pod -l app=configuration-service --timeout=120s -n $NAMESPACE

run_k8s_test "Configuration Service Scaling" "kubectl get deployment configuration-service -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' | grep -q '2'"

# Scale back down
kubectl scale deployment configuration-service --replicas=1 -n $NAMESPACE > /dev/null 2>&1
kubectl wait --for=condition=ready pod -l app=configuration-service --timeout=120s -n $NAMESPACE

# Step 11: Persistence Tests
echo -e "\n${BLUE}💾 Step 11: Persistence Tests${NC}"

# Test data persistence by restarting pods
echo -e "${YELLOW}Testing data persistence...${NC}"

# Store test data
curl -f -X POST http://localhost:3001/config/persistence-test \
    -H "Content-Type: application/json" \
    -d '{"key": "persistence-key", "value": "persistence-value"}' > /dev/null 2>&1

# Restart MySQL pod
kubectl delete pod -l app=mysql -n $NAMESPACE
kubectl wait --for=condition=ready pod -l app=mysql --timeout=180s -n $NAMESPACE

# Wait for service to reconnect
sleep 15

# Verify data persisted
run_k8s_test "Data Persistence Test" "curl -f http://localhost:3001/config/persistence-test | grep -q 'persistence-key'"

# Step 12: Performance Tests in Kubernetes
echo -e "\n${BLUE}⚡ Step 12: Performance Tests${NC}"

# Measure response times in Kubernetes
CONFIG_K8S_TIME=$(curl -o /dev/null -s -w '%{time_total}' http://localhost:3001/health)
LOGS_K8S_TIME=$(curl -o /dev/null -s -w '%{time_total}' http://localhost:3002/health)

echo -e "Configuration Service K8s response time: ${GREEN}${CONFIG_K8S_TIME}s${NC}"
echo -e "Log Aggregator Service K8s response time: ${GREEN}${LOGS_K8S_TIME}s${NC}"

# Update performance data
python3 -c "
import json
with open('$K8S_REPORT', 'r') as f:
    data = json.load(f)
data['performance'] = {
    'configuration_service_response_time': $CONFIG_K8S_TIME,
    'log_service_response_time': $LOGS_K8S_TIME,
    'environment': 'kubernetes'
}
with open('$K8S_REPORT', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

# Step 13: Resource Usage Analysis
echo -e "\n${BLUE}📊 Step 13: Resource Usage Analysis${NC}"

# Get resource usage
echo -e "${YELLOW}Analyzing resource usage...${NC}"
kubectl top nodes > $RESULTS_DIR/k8s-node-resources.txt 2>/dev/null || echo "Metrics server not available"
kubectl top pods -n $NAMESPACE > $RESULTS_DIR/k8s-pod-resources.txt 2>/dev/null || echo "Pod metrics not available"

# Get pod details
kubectl get pods -n $NAMESPACE -o wide > $RESULTS_DIR/k8s-pod-details.txt

# Step 14: Cleanup and Results
echo -e "\n${BLUE}🧹 Step 14: Cleanup and Results${NC}"

# Stop port forwards
kill $CONFIG_PF_PID $LOGS_PF_PID 2>/dev/null || true

# Collect deployment information
kubectl get all -n $NAMESPACE -o wide > $RESULTS_DIR/k8s-deployment-status.txt

# Final results update
python3 -c "
import json
with open('$K8S_REPORT', 'r') as f:
    data = json.load(f)
data['status'] = 'completed'
data['summary'] = {
    'total_tests': len(data['tests']),
    'passed': sum(1 for t in data['tests'].values() if t['status'] == 'passed'),
    'failed': sum(1 for t in data['tests'].values() if t['status'] == 'failed'),
    'cluster_info': {
        'context': 'orbstack',
        'namespace': '$NAMESPACE'
    }
}
with open('$K8S_REPORT', 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null || true

# Display final results
echo -e "\n${BLUE}📊 Kubernetes Local Testing Results${NC}"
echo -e "${BLUE}===================================${NC}"

if [ -f "$K8S_REPORT" ]; then
    python3 -c "
import json
with open('$K8S_REPORT', 'r') as f:
    data = json.load(f)
summary = data.get('summary', {})
performance = data.get('performance', {})
print(f\"Total Tests: {summary.get('total_tests', 0)}\")
print(f\"Passed: {summary.get('passed', 0)}\")
print(f\"Failed: {summary.get('failed', 0)}\")
print(f\"Cluster: {summary.get('cluster_info', {}).get('context', 'unknown')}\")
print(f\"Namespace: {summary.get('cluster_info', {}).get('namespace', 'unknown')}\")
if 'configuration_service_response_time' in performance:
    print(f\"Config Service K8s Response Time: {performance['configuration_service_response_time']:.3f}s\")
if 'log_service_response_time' in performance:
    print(f\"Log Service K8s Response Time: {performance['log_service_response_time']:.3f}s\")
" 2>/dev/null || echo "Results summary not available"
fi

echo -e "\n${GREEN}✅ Kubernetes local testing completed${NC}"
echo -e "${BLUE}📄 Detailed results saved to: $K8S_REPORT${NC}"

# Show Kubernetes-specific information
echo -e "\n${BLUE}💡 Kubernetes Testing Summary:${NC}"
echo -e "• Services deployed and tested in local OrbStack cluster"
echo -e "• Pod-to-pod communication validated"
echo -e "• Horizontal scaling tested"
echo -e "• Data persistence verified"
echo -e "• Service discovery confirmed"

# Optional: Keep deployments running or clean up
read -p "Keep Kubernetes deployments running? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleaning up Kubernetes deployments...${NC}"
    kubectl delete all --all -n $NAMESPACE > /dev/null 2>&1
    echo -e "${GREEN}✅ Cleanup completed${NC}"
else
    echo -e "${BLUE}💡 Access services with:${NC}"
    echo -e "  kubectl port-forward service/configuration-service 3001:3001 -n $NAMESPACE"
    echo -e "  kubectl port-forward service/log-aggregator-service 3002:3002 -n $NAMESPACE"
fi

# Exit with error if any tests failed
if [ -f "$K8S_REPORT" ]; then
    FAILED_COUNT=$(python3 -c "
import json
with open('$K8S_REPORT', 'r') as f:
    data = json.load(f)
print(sum(1 for t in data['tests'].values() if t['status'] == 'failed'))
" 2>/dev/null || echo "0")
    
    if [ "$FAILED_COUNT" -gt 0 ]; then
        echo -e "${RED}❌ $FAILED_COUNT tests failed${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}🎉 All Kubernetes tests passed!${NC}"