# Microservices Deployment Guide

This guide provides step-by-step instructions for deploying the Configuration Service and Log Aggregator Service microservices using various orchestration platforms.

## Architecture Overview

The system consists of:
- **Configuration Service** (Port 3001): Centralized configuration management
- **Log Aggregator Service** (Port 3002): Log collection and processing  
- **MySQL Database**: Data persistence layer
- **Redis Cache**: High-performance caching layer
- **Nginx**: Load balancer and reverse proxy

## Prerequisites

### For Kubernetes Deployment
- Kubernetes cluster (v1.20+)
- kubectl configured to access your cluster
- NGINX Ingress Controller installed
- Docker registry access (for custom images)

### For Docker Compose Deployment  
- Docker Engine 20.0+
- Docker Compose v2.0+
- At least 4GB RAM available
- At least 10GB disk space

### For Local Development
- Node.js 18+
- MySQL 8.0+
- Redis 7+
- Git

## Deployment Options

### Option 1: Kubernetes Deployment (Recommended for Production)

#### Step 1: Prepare Container Images

```bash
# Build Configuration Service image
cd configuration-service
docker build -t your-registry/configuration-service:latest .
docker push your-registry/configuration-service:latest

# Build Log Aggregator Service image  
cd ../log-aggregator-service
docker build -t your-registry/log-aggregator-service:latest .
docker push your-registry/log-aggregator-service:latest
```

#### Step 2: Update Image References

Edit the Kubernetes manifests to use your registry:

```bash
# Update k8s-manifests/configuration-service.yaml
sed -i 's|configuration-service:latest|your-registry/configuration-service:latest|' k8s-manifests/configuration-service.yaml

# Update k8s-manifests/log-aggregator-service.yaml
sed -i 's|log-aggregator-service:latest|your-registry/log-aggregator-service:latest|' k8s-manifests/log-aggregator-service.yaml
```

#### Step 3: Deploy to Kubernetes

```bash
# Create namespace
kubectl apply -f k8s-manifests/namespace.yaml

# Deploy database services
kubectl apply -f k8s-manifests/mysql-deployment.yaml
kubectl apply -f k8s-manifests/redis-deployment.yaml

# Wait for databases to be ready
kubectl wait --for=condition=available --timeout=300s deployment/mysql -n microservices
kubectl wait --for=condition=available --timeout=300s deployment/redis -n microservices

# Deploy microservices
kubectl apply -f k8s-manifests/configuration-service.yaml
kubectl apply -f k8s-manifests/log-aggregator-service.yaml

# Wait for services to be ready
kubectl wait --for=condition=available --timeout=300s deployment/configuration-service -n microservices
kubectl wait --for=condition=available --timeout=300s deployment/log-aggregator-service -n microservices
```

#### Step 4: Verify Deployment

```bash
# Check pod status
kubectl get pods -n microservices

# Check services
kubectl get services -n microservices

# Check ingress
kubectl get ingress -n microservices

# Test services
kubectl port-forward service/configuration-service 3001:3001 -n microservices &
curl http://localhost:3001/health

kubectl port-forward service/log-aggregator-service 3002:3002 -n microservices &
curl http://localhost:3002/health
```

#### Step 5: Configure DNS (Optional)

Add to your `/etc/hosts` file for local testing:

```bash
# Get ingress IP
INGRESS_IP=$(kubectl get ingress configuration-service-ingress -n microservices -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# Add to /etc/hosts
echo "$INGRESS_IP config.local" | sudo tee -a /etc/hosts
echo "$INGRESS_IP logs.local" | sudo tee -a /etc/hosts
```

### Option 2: Docker Compose Deployment (Recommended for Development)

#### Step 1: Clone and Navigate

```bash
git clone <repository-url>
cd andela-devops
```

#### Step 2: Create Environment Files

```bash
# Configuration Service
cp configuration-service/.env.example configuration-service/.env

# Log Aggregator Service  
cp log-aggregator-service/.env.example log-aggregator-service/.env
```

#### Step 3: Deploy with Docker Compose

```bash
# Build and start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Check status
docker-compose ps
```

#### Step 4: Verify Deployment

```bash
# Test Configuration Service
curl http://localhost:3001/health

# Test Log Aggregator Service
curl http://localhost:3002/health

# Test through Nginx (if configured)
curl http://localhost/health
```

#### Step 5: Test Log Aggregation

```bash
# Send a test log
curl -X POST http://localhost:3002/logs \
  -H "Content-Type: application/json" \
  -d '{
    "serviceName": "test-service",
    "level": "info", 
    "message": "Test deployment successful",
    "metadata": {"source": "deployment-guide"}
  }'

# Retrieve logs
curl "http://localhost:3002/logs?serviceName=test-service"
```

### Option 3: Local Development Setup

#### Step 1: Start Dependencies

```bash
# Start MySQL
docker run -d --name dev-mysql \
  -e MYSQL_ROOT_PASSWORD=password \
  -e MYSQL_DATABASE=microservices_db \
  -p 3306:3306 \
  mysql:8.0

# Start Redis
docker run -d --name dev-redis \
  -p 6379:6379 \
  redis:7-alpine
```

#### Step 2: Setup Configuration Service

```bash
cd configuration-service

# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Start in development mode
npm run dev
```

#### Step 3: Setup Log Aggregator Service

```bash
cd ../log-aggregator-service

# Install dependencies  
npm install

# Create logs directory
mkdir -p logs

# Copy environment file
cp .env.example .env

# Start in development mode
npm run dev
```

## Configuration

### Database Configuration

#### MySQL Initial Setup
The services will automatically create the required tables. Default credentials:
- Username: `root` / `myuser`
- Password: `password` / `mypassword`
- Database: `microservices_db`

#### Redis Configuration
No initial setup required. Services connect automatically.

### Environment Variables

#### Configuration Service
- `PORT=3001` - Server port
- `MYSQL_HOST=mysql` - Database hostname
- `MYSQL_DATABASE=microservices_db` - Database name
- `REDIS_HOST=redis` - Redis hostname

#### Log Aggregator Service  
- `PORT=3002` - Server port
- `LOG_LEVEL=info` - Winston log level
- `NODE_ENV=production` - Environment mode

### Scaling Configuration

#### Kubernetes Horizontal Pod Autoscaler
The Log Aggregator Service includes HPA configuration:
- Min replicas: 2
- Max replicas: 10
- Target CPU: 70%
- Target Memory: 80%

#### Manual Scaling
```bash
# Scale Configuration Service
kubectl scale deployment configuration-service --replicas=3 -n microservices

# Scale Log Aggregator Service
kubectl scale deployment log-aggregator-service --replicas=5 -n microservices
```

## CI/CD Pipeline Setup

### GitHub Actions
The repository includes workflows for both services:
- Automated testing on push/PR
- Docker image building and pushing
- Kubernetes deployment on main branch

#### Required Secrets
- `KUBE_CONFIG` - Base64 encoded kubeconfig file
- Container registry credentials (automatically provided for GitHub Container Registry)

### Jenkins Pipeline
1. Install required Jenkins plugins:
   - Docker Pipeline
   - Kubernetes CLI
   - Git
   
2. Configure credentials:
   - Docker registry credentials
   - Kubeconfig file
   
3. Create pipeline job pointing to `Jenkinsfile`

### GitLab CI/CD
1. Configure variables in GitLab:
   - `KUBE_CONTEXT` - Kubernetes context name
   - Container registry automatically configured

2. Pipeline runs automatically on push to main branch

## Monitoring and Observability

### Health Checks
Both services provide health endpoints:
- Configuration Service: `http://config.local/health`
- Log Aggregator Service: `http://logs.local/health`

### Kubernetes Monitoring
```bash
# View pod status
kubectl get pods -n microservices

# View logs
kubectl logs -f deployment/configuration-service -n microservices
kubectl logs -f deployment/log-aggregator-service -n microservices

# Check resource usage
kubectl top pods -n microservices
```

### Application Logs
Log Aggregator Service writes logs to:
- `logs/error.log` - Error logs only
- `logs/combined.log` - All log levels
- Console output (development)

## Security Considerations

### Production Security Checklist
- [ ] Change default database passwords
- [ ] Use Kubernetes secrets for sensitive data
- [ ] Enable TLS/SSL for external access
- [ ] Implement network policies
- [ ] Set up proper RBAC
- [ ] Enable audit logging
- [ ] Configure resource limits
- [ ] Use non-root containers (already configured)

### Network Security
- Services communicate within cluster network
- External access controlled by Ingress
- Rate limiting configured in Nginx and application
- CORS configured for cross-origin requests

## Troubleshooting

### Common Issues

#### Database Connection Issues
```bash
# Check MySQL status
kubectl exec -it deployment/mysql -n microservices -- mysql -u root -ppassword -e "SHOW DATABASES;"

# Check Redis status  
kubectl exec -it deployment/redis -n microservices -- redis-cli ping
```

#### Service Communication Issues
```bash
# Check DNS resolution
kubectl exec -it deployment/configuration-service -n microservices -- nslookup mysql

# Test internal connectivity
kubectl exec -it deployment/configuration-service -n microservices -- curl http://redis:6379
```

#### Resource Issues
```bash
# Check resource usage
kubectl describe pods -n microservices

# Check events
kubectl get events -n microservices --sort-by='.lastTimestamp'
```

### Debug Commands

```bash
# Get detailed pod information
kubectl describe pod <pod-name> -n microservices

# Access pod shell
kubectl exec -it <pod-name> -n microservices -- /bin/sh

# View service logs
kubectl logs <pod-name> -n microservices --previous
```

## Performance Tuning

### Database Optimization
- Configure MySQL connection pooling
- Set appropriate `innodb_buffer_pool_size`
- Monitor slow query log
- Regular database maintenance

### Redis Optimization  
- Configure appropriate `maxmemory` policy
- Monitor memory usage
- Use Redis clustering for high availability

### Application Optimization
- Enable Node.js clustering
- Configure appropriate heap sizes
- Use PM2 for production process management
- Implement connection pooling

## Backup and Recovery

### Database Backups
```bash
# MySQL backup
kubectl exec deployment/mysql -n microservices -- mysqldump -u root -ppassword microservices_db > backup.sql

# Redis backup
kubectl exec deployment/redis -n microservices -- redis-cli BGSAVE
```

### Disaster Recovery
- Implement regular database backups
- Store backups in external storage
- Test restore procedures regularly
- Document recovery processes

## Maintenance

### Regular Maintenance Tasks
- [ ] Update container images
- [ ] Rotate database passwords
- [ ] Clean up old logs
- [ ] Update SSL certificates
- [ ] Review resource usage
- [ ] Update dependencies

### Upgrade Procedures
1. Test upgrades in staging environment
2. Backup databases before upgrades  
3. Use rolling updates for zero downtime
4. Verify functionality after upgrades
5. Have rollback plan ready

## Additional Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [Node.js Production Best Practices](https://nodejs.org/en/docs/guides/nodejs-docker-webapp/)
- [MySQL Performance Tuning](https://dev.mysql.com/doc/refman/8.0/en/optimization.html)
- [Redis Best Practices](https://redis.io/topics/admin)