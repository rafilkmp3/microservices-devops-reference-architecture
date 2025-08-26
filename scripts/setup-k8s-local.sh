#!/bin/bash
# Setup script for local Kubernetes testing with OrbStack
# Configures kubectx, creates local namespace, and sets up development cluster

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="microservices-dev"
ORBSTACK_CONTEXT="orbstack"

echo -e "${BLUE}🚀 Setting up local Kubernetes with OrbStack...${NC}"

# Check if OrbStack is installed
if ! command -v orb &> /dev/null; then
    echo -e "${RED}❌ OrbStack is not installed${NC}"
    echo -e "${YELLOW}Please install OrbStack from: https://orbstack.dev/${NC}"
    exit 1
fi

echo -e "${GREEN}✅ OrbStack found${NC}"

# Check if OrbStack Kubernetes is running
echo -e "\n${YELLOW}Checking OrbStack Kubernetes status...${NC}"
if ! kubectl config get-contexts | grep -q "orbstack"; then
    echo -e "${RED}❌ OrbStack Kubernetes context not found${NC}"
    echo -e "${YELLOW}Please enable Kubernetes in OrbStack settings${NC}"
    exit 1
fi

echo -e "${GREEN}✅ OrbStack Kubernetes context available${NC}"

# Install kubectx if not available
if ! command -v kubectx &> /dev/null; then
    echo -e "\n${YELLOW}Installing kubectx...${NC}"
    if command -v brew &> /dev/null; then
        brew install kubectx
    else
        echo -e "${RED}❌ Please install kubectx manually${NC}"
        echo -e "${YELLOW}macOS: brew install kubectx${NC}"
        echo -e "${YELLOW}Linux: curl -sSLO https://github.com/ahmetb/kubectx/releases/latest/download/kubectx${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ kubectx available${NC}"

# Switch to OrbStack context
echo -e "\n${YELLOW}Switching to OrbStack Kubernetes context...${NC}"
kubectx $ORBSTACK_CONTEXT || {
    echo -e "${RED}❌ Failed to switch to OrbStack context${NC}"
    echo -e "${YELLOW}Available contexts:${NC}"
    kubectl config get-contexts
    exit 1
}

echo -e "${GREEN}✅ Using OrbStack Kubernetes context${NC}"

# Verify cluster connection
echo -e "\n${YELLOW}Verifying cluster connection...${NC}"
if kubectl cluster-info &> /dev/null; then
    echo -e "${GREEN}✅ Connected to Kubernetes cluster${NC}"
    kubectl cluster-info | head -2
else
    echo -e "${RED}❌ Failed to connect to Kubernetes cluster${NC}"
    exit 1
fi

# Create development namespace
echo -e "\n${YELLOW}Creating development namespace...${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -
kubectl config set-context --current --namespace=$NAMESPACE

echo -e "${GREEN}✅ Namespace '$NAMESPACE' created and set as default${NC}"

# Create local Docker registry secret (for OrbStack)
echo -e "\n${YELLOW}Setting up local container registry access...${NC}"
kubectl create secret generic regcred \
    --from-literal=.dockerconfigjson='{}' \
    --type=kubernetes.io/dockerconfigjson \
    --dry-run=client -o yaml | kubectl apply -f - || true

echo -e "${GREEN}✅ Registry credentials configured${NC}"

# Install ingress controller for local testing
echo -e "\n${YELLOW}Setting up NGINX Ingress Controller...${NC}"
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml

# Wait for ingress controller to be ready
echo -e "${YELLOW}Waiting for ingress controller to be ready...${NC}"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=90s

echo -e "${GREEN}✅ NGINX Ingress Controller installed${NC}"

# Create a simple test deployment to verify everything works
echo -e "\n${YELLOW}Creating test deployment...${NC}"
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-nginx
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-nginx
  template:
    metadata:
      labels:
        app: test-nginx
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-nginx-service
  namespace: $NAMESPACE
spec:
  selector:
    app: test-nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  type: ClusterIP
EOF

# Wait for test deployment to be ready
kubectl wait --for=condition=available --timeout=60s deployment/test-nginx -n $NAMESPACE

echo -e "${GREEN}✅ Test deployment created successfully${NC}"

# Show cluster status
echo -e "\n${BLUE}📊 Cluster Status:${NC}"
echo -e "${YELLOW}Context:${NC} $(kubectl config current-context)"
echo -e "${YELLOW}Namespace:${NC} $(kubectl config view --minify --output 'jsonpath={..namespace}')"
echo -e "${YELLOW}Server:${NC} $(kubectl cluster-info | grep 'Kubernetes control plane' | awk '{print $NF}')"

echo -e "\n${YELLOW}Nodes:${NC}"
kubectl get nodes

echo -e "\n${YELLOW}Deployments in $NAMESPACE:${NC}"
kubectl get deployments -n $NAMESPACE

# Create helper scripts
echo -e "\n${YELLOW}Creating helper scripts...${NC}"

# Create port-forward helper
cat > scripts/k8s-port-forward.sh << 'EOF'
#!/bin/bash
# Port forward services for local development

set -e

NAMESPACE="microservices-dev"

echo "🔗 Setting up port forwards for local development..."

# Port forward configuration service
echo "Port forwarding Configuration Service (3001)..."
kubectl port-forward -n $NAMESPACE service/configuration-service 3001:3001 &

# Port forward log aggregator service  
echo "Port forwarding Log Aggregator Service (3002)..."
kubectl port-forward -n $NAMESPACE service/log-aggregator-service 3002:3002 &

# Port forward MySQL
echo "Port forwarding MySQL (3306)..."
kubectl port-forward -n $NAMESPACE service/mysql 3306:3306 &

# Port forward Redis
echo "Port forwarding Redis (6379)..."
kubectl port-forward -n $NAMESPACE service/redis 6379:6379 &

echo "✅ Port forwards established:"
echo "  Configuration Service: http://localhost:3001"
echo "  Log Aggregator Service: http://localhost:3002"  
echo "  MySQL: localhost:3306"
echo "  Redis: localhost:6379"
echo ""
echo "Press Ctrl+C to stop all port forwards"

# Wait for interruption
trap 'echo "Stopping port forwards..."; jobs -p | xargs kill; exit 0' INT
wait
EOF

chmod +x scripts/k8s-port-forward.sh

# Create cleanup script
cat > scripts/k8s-cleanup.sh << 'EOF'
#!/bin/bash
# Clean up local Kubernetes development environment

set -e

NAMESPACE="microservices-dev"

echo "🧹 Cleaning up Kubernetes development environment..."

# Delete microservices deployments
echo "Deleting application deployments..."
kubectl delete all --all -n $NAMESPACE --ignore-not-found=true

# Delete configmaps and secrets
echo "Deleting configmaps and secrets..."
kubectl delete configmaps --all -n $NAMESPACE --ignore-not-found=true
kubectl delete secrets --all -n $NAMESPACE --ignore-not-found=true --field-selector type!=kubernetes.io/service-account-token

# Delete persistent volume claims
echo "Deleting persistent volume claims..."
kubectl delete pvc --all -n $NAMESPACE --ignore-not-found=true

# Optionally delete namespace (uncomment to delete)
# echo "Deleting namespace..."
# kubectl delete namespace $NAMESPACE --ignore-not-found=true

echo "✅ Cleanup completed"
echo "Note: Namespace '$NAMESPACE' was preserved. Uncomment the last section to delete it."
EOF

chmod +x scripts/k8s-cleanup.sh

# Create status check script
cat > scripts/k8s-status.sh << 'EOF'
#!/bin/bash
# Check status of Kubernetes deployments

set -e

NAMESPACE="microservices-dev"

echo "📊 Kubernetes Development Environment Status"
echo "==========================================="

echo -e "\n🏗️  Current Context:"
echo "Context: $(kubectl config current-context)"
echo "Namespace: $(kubectl config view --minify --output 'jsonpath={..namespace}')"

echo -e "\n🎯 Nodes:"
kubectl get nodes -o wide

echo -e "\n📦 Deployments:"
kubectl get deployments -n $NAMESPACE -o wide || echo "No deployments found"

echo -e "\n🔄 Pods:"
kubectl get pods -n $NAMESPACE -o wide || echo "No pods found"

echo -e "\n🌐 Services:"
kubectl get services -n $NAMESPACE -o wide || echo "No services found"

echo -e "\n📊 Persistent Volume Claims:"
kubectl get pvc -n $NAMESPACE || echo "No PVCs found"

echo -e "\n🔍 Recent Events:"
kubectl get events -n $NAMESPACE --sort-by=.metadata.creationTimestamp | tail -10 || echo "No events found"

# Check ingress if available
echo -e "\n🚪 Ingress:"
kubectl get ingress -n $NAMESPACE 2>/dev/null || echo "No ingress found"

echo -e "\n📋 Resource Usage:"
kubectl top nodes 2>/dev/null || echo "Metrics not available"
kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Pod metrics not available"
EOF

chmod +x scripts/k8s-status.sh

echo -e "${GREEN}✅ Helper scripts created${NC}"

# Clean up test deployment
echo -e "\n${YELLOW}Cleaning up test deployment...${NC}"
kubectl delete deployment test-nginx -n $NAMESPACE
kubectl delete service test-nginx-service -n $NAMESPACE

echo -e "\n${GREEN}🎉 Local Kubernetes setup completed!${NC}"
echo -e "\n${BLUE}📚 Quick Start Guide:${NC}"
echo -e "1. Deploy services: ${YELLOW}make k8s-deploy-local${NC}"
echo -e "2. Check status: ${YELLOW}./scripts/k8s-status.sh${NC}"
echo -e "3. Port forward: ${YELLOW}./scripts/k8s-port-forward.sh${NC}"
echo -e "4. Clean up: ${YELLOW}./scripts/k8s-cleanup.sh${NC}"
echo -e "\n${BLUE}💡 Useful commands:${NC}"
echo -e "• Switch context: ${YELLOW}kubectx orbstack${NC}"
echo -e "• View pods: ${YELLOW}kubectl get pods -n $NAMESPACE${NC}"
echo -e "• View logs: ${YELLOW}kubectl logs -f deployment/configuration-service -n $NAMESPACE${NC}"
echo -e "• Shell into pod: ${YELLOW}kubectl exec -it deployment/configuration-service -n $NAMESPACE -- sh${NC}"