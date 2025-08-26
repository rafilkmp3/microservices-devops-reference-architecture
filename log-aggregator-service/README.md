# Log Aggregator Service

A scalable log aggregation service that collects, processes, and stores logs from multiple microservices. Features real-time log ingestion, structured storage, and powerful query capabilities.

## Features

- **Multi-Service Log Aggregation**: Collect logs from various microservices
- **Structured Storage**: Organized log storage with metadata support
- **Real-time Caching**: Recent logs cached in Redis for fast access
- **Flexible Querying**: Filter logs by service, level, time range
- **Bulk Operations**: Support for bulk log insertion
- **Statistics & Analytics**: Log statistics and metrics
- **Rate Limiting**: Built-in protection against log flooding
- **Security**: Helmet.js for security headers
- **Health Monitoring**: Comprehensive health checks

## API Endpoints

### Health & Status
- `GET /health` - Service health status

### Log Management
- `POST /logs` - Store a single log entry
- `POST /logs/bulk` - Store multiple log entries (up to 1000)
- `GET /logs` - Retrieve logs with filtering and pagination
- `GET /logs/:serviceName/recent` - Get recent cached logs for a service
- `GET /stats` - Get log statistics and analytics

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
   cd log-aggregator-service
   ```

2. **Install dependencies**
   ```bash
   npm install
   ```

3. **Set up environment variables**
   ```bash
   cp .env.example .env
   # Edit .env with your configurations
   ```

4. **Create logs directory**
   ```bash
   mkdir -p logs
   ```

5. **Start the service**
   ```bash
   # Development mode with auto-reload
   npm run dev

   # Production mode
   npm start
   ```

### Docker Deployment

1. **Build Docker image**
   ```bash
   docker build -t log-aggregator-service .
   ```

2. **Run with Docker**
   ```bash
   docker run -d \
     --name log-aggregator-service \
     -p 3002:3002 \
     -e MYSQL_HOST=your-mysql-host \
     -e MYSQL_USER=your-user \
     -e MYSQL_PASSWORD=your-password \
     -e MYSQL_DATABASE=your-database \
     -e REDIS_HOST=your-redis-host \
     -v $(pwd)/logs:/app/logs \
     log-aggregator-service
   ```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Server port | `3002` |
| `NODE_ENV` | Environment (development/production) | `development` |
| `LOG_LEVEL` | Winston log level | `info` |
| `MYSQL_HOST` | MySQL server hostname | `localhost` |
| `MYSQL_PORT` | MySQL server port | `3306` |
| `MYSQL_USER` | MySQL username | `root` |
| `MYSQL_PASSWORD` | MySQL password | `password` |
| `MYSQL_DATABASE` | MySQL database name | `logs_db` |
| `REDIS_HOST` | Redis server hostname | `localhost` |
| `REDIS_PORT` | Redis server port | `6379` |

## Usage Examples

### Single Log Entry
```bash
curl -X POST http://localhost:3002/logs \
  -H "Content-Type: application/json" \
  -d '{
    "serviceName": "user-service",
    "level": "error",
    "message": "Failed to authenticate user",
    "metadata": {
      "userId": 12345,
      "ip": "192.168.1.100",
      "timestamp": "2024-01-01T12:00:00Z"
    }
  }'
```

### Bulk Log Entries
```bash
curl -X POST http://localhost:3002/logs/bulk \
  -H "Content-Type: application/json" \
  -d '{
    "logs": [
      {
        "serviceName": "user-service",
        "level": "info",
        "message": "User logged in",
        "metadata": {"userId": 123}
      },
      {
        "serviceName": "order-service",
        "level": "warn",
        "message": "Inventory low",
        "metadata": {"productId": 456}
      }
    ]
  }'
```

### Query Logs
```bash
# Get logs with filters
curl "http://localhost:3002/logs?serviceName=user-service&level=error&limit=50"

# Get recent cached logs
curl "http://localhost:3002/logs/user-service/recent?limit=20"

# Get statistics
curl "http://localhost:3002/stats?serviceName=user-service&timeRange=24h"
```

## Log Levels

Supported log levels (in order of severity):
- `error` - Error conditions
- `warn` - Warning conditions  
- `info` - Informational messages
- `debug` - Debug-level messages
- `trace` - Trace messages

## Database Schema

The service automatically creates the following table:

```sql
CREATE TABLE logs (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  service_name VARCHAR(255) NOT NULL,
  level ENUM('error', 'warn', 'info', 'debug', 'trace') NOT NULL DEFAULT 'info',
  message TEXT NOT NULL,
  metadata JSON,
  timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_service_timestamp (service_name, timestamp),
  INDEX idx_level_timestamp (level, timestamp)
);
```

## Caching Strategy

- Recent logs (last 1000 per service) cached in Redis
- Cache TTL: 1 hour
- Cache key format: `logs:{serviceName}:recent`
- Automatic cache updates on new log entries

## Query Parameters

### GET /logs
- `serviceName` - Filter by service name
- `level` - Filter by log level
- `startTime` - Start time (ISO 8601)
- `endTime` - End time (ISO 8601)  
- `limit` - Number of results (default: 100, max: 1000)
- `offset` - Pagination offset (default: 0)
- `sortOrder` - ASC or DESC (default: DESC)

### GET /stats
- `serviceName` - Filter by service (optional)
- `timeRange` - Time range: 1h, 24h, 7d, 30d (default: 1h)

## Rate Limiting

- 100 requests per 15 minutes per IP
- Configurable via environment variables
- Uses in-memory store (Redis recommended for production)

## Security Features

- Helmet.js security headers
- Input validation and sanitization
- SQL injection prevention
- Request size limits (10MB for bulk operations)
- Error message sanitization in production

## Logging & Monitoring

### Application Logs
- File-based logging with rotation
- Console output for development
- JSON structured logs
- Log levels: error, warn, info, debug

### Log Files
- `logs/error.log` - Error level logs only
- `logs/combined.log` - All log levels
- Console output with colors (development)

### Health Check Response
```json
{
  "status": "healthy",
  "service": "log-aggregator-service", 
  "timestamp": "2024-01-01T12:00:00.000Z",
  "uptime": 3600
}
```

## Performance Considerations

- Connection pooling for MySQL
- Redis caching for frequent queries
- Database indexing on service_name and timestamp
- Bulk insert operations for high throughput
- Graceful shutdown handling

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

### Kubernetes Features
- Horizontal Pod Autoscaler (2-10 replicas)
- Resource limits and requests
- Liveness and readiness probes
- ConfigMaps and Secrets
- Persistent volume for logs

### Docker Compose
Full stack deployment:
```bash
docker-compose up -d
```

## Monitoring & Observability

### Metrics to Monitor
- Log ingestion rate
- Error rates by service
- Response times
- Database connection pool usage
- Redis cache hit rates
- Disk usage (log files)

### Alerting Recommendations
- High error rates from specific services
- Service unavailability
- Database connection failures
- Disk space usage

## Scaling Considerations

- Horizontal scaling supported
- Database connection pooling
- Redis cluster for high availability
- Log file rotation and cleanup
- Consider log shipping to external systems (ELK, Splunk)

## Security Best Practices

- Use Kubernetes secrets for sensitive data
- Enable TLS for database connections
- Implement log retention policies
- Monitor for unusual log patterns
- Sanitize log content to prevent log injection

## Troubleshooting

### Common Issues
1. **Database Connection Errors**: Check MySQL connectivity and credentials
2. **Redis Connection Errors**: Verify Redis server status
3. **High Memory Usage**: Check log retention settings
4. **Slow Queries**: Review database indexes

### Debug Mode
Set `LOG_LEVEL=debug` to enable detailed logging

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Follow existing code style
5. Submit a pull request

## License

MIT License