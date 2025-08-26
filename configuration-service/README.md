# Configuration Service

A centralized configuration management service for microservices architecture. This service provides configuration storage and retrieval capabilities with Redis caching for improved performance.

## Features

- **Centralized Configuration Management**: Store and manage configurations for multiple services
- **Redis Caching**: Fast configuration retrieval with automatic cache invalidation
- **MySQL Persistence**: Reliable data storage with structured schema
- **RESTful API**: Simple HTTP endpoints for configuration operations
- **Health Monitoring**: Built-in health check endpoint
- **Environment Configuration**: Flexible environment-based configuration

## API Endpoints

### Health Check
- `GET /health` - Service health status

### Configuration Management
- `GET /config/:serviceName` - Retrieve configuration for a service
- `POST /config/:serviceName` - Set/update configuration for a service
- `GET /config` - Get all configurations
- `DELETE /config/:serviceName/:key` - Delete a specific configuration

## Prerequisites

- Node.js 18+ 
- MySQL 8.0+
- Redis 7+
- Docker (optional)

## Installation

### Local Development

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd configuration-service
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your database configurations
   ```

4. **Start the service**
   ```bash
   # Development mode with auto-reload
   npm run dev

   # Production mode
   npm start
   ```

### Docker Deployment

1. **Build Docker image**
   ```bash
   docker build -t configuration-service .
   ```

2. **Run with Docker**
   ```bash
   docker run -d \
     --name configuration-service \
     -p 3001:3001 \
     -e MYSQL_HOST=your-mysql-host \
     -e MYSQL_USER=your-user \
     -e MYSQL_PASSWORD=your-password \
     -e MYSQL_DATABASE=your-database \
     -e REDIS_HOST=your-redis-host \
     configuration-service
   ```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `3001` |
| `MYSQL_HOST` | MySQL server hostname | `localhost` |
| `MYSQL_PORT` | MySQL server port | `3306` |
| `MYSQL_USER` | MySQL username | `root` |
| `MYSQL_PASSWORD` | MySQL password | `password` |
| `MYSQL_DATABASE` | MySQL database name | `config_db` |
| `REDIS_HOST` | Redis server hostname | `localhost` |
| `REDIS_PORT` | Redis server port | `6379` |

## Usage Examples

### Set Configuration
```bash
curl -X POST http://localhost:3001/config/user-service \
  -H "Content-Type: application/json" \
  -d '{"key": "max_connections", "value": "100"}'
```

### Get Configuration
```bash
curl http://localhost:3001/config/user-service
```

### Response Example
```json
{
  "max_connections": "100",
  "timeout": "30",
  "debug_mode": "false"
}
```

## Database Schema

The service automatically creates the following table:

```sql
CREATE TABLE configurations (
  id INT AUTO_INCREMENT PRIMARY KEY,
  service_name VARCHAR(255) NOT NULL,
  config_key VARCHAR(255) NOT NULL,
  config_value TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_service_key (service_name, config_key)
);
```

## Caching Strategy

- Configurations are cached in Redis with a 5-minute TTL
- Cache is invalidated when configurations are updated
- Cache key format: `config:{serviceName}`

## Health Check

The service provides a health endpoint at `/health` that returns:

```json
{
  "status": "healthy",
  "service": "configuration-service",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## Development

### Running Tests
```bash
npm test
```

### Code Linting
```bash
npm run lint
```

### Development with Hot Reload
```bash
npm run dev
```

## Production Deployment

### Kubernetes
The service is designed to run in Kubernetes with:
- ConfigMaps for environment variables
- Secrets for sensitive data (database passwords)
- Health checks for liveness and readiness probes
- Horizontal Pod Autoscaler for scaling

### Docker Compose
For local testing with full stack:
```bash
docker-compose up -d
```

## Security Considerations

- Database credentials should be stored in Kubernetes secrets
- Use connection pooling for database connections
- Implement rate limiting for API endpoints
- Enable CORS for cross-origin requests
- Use HTTPS in production

## Monitoring

- Health check endpoint for kubernetes probes
- Application logs for debugging
- Consider adding metrics collection (Prometheus/StatsD)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

MIT License