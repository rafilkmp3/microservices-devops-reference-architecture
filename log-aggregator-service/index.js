const express = require("express");
const mysql = require("mysql2/promise");
const redis = require("redis");
const cors = require("cors");
const rateLimit = require("express-rate-limit");
const helmet = require("helmet");
const winston = require("winston");
require("dotenv").config();

const app = express();
const PORT = process.env.PORT || 3002;

// Configure Winston logger
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || "info",
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json(),
  ),
  transports: [
    new winston.transports.File({ filename: "logs/error.log", level: "error" }),
    new winston.transports.File({ filename: "logs/combined.log" }),
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple(),
      ),
    }),
  ],
});

// Security and rate limiting
app.use(helmet());
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: "Too many requests from this IP, please try again later.",
  standardHeaders: true,
  legacyHeaders: false,
});
app.use(limiter);

// Middleware
app.use(cors());
app.use(express.json({ limit: "10mb" }));

// Request logging middleware
app.use((req, res, next) => {
  logger.info(`${req.method} ${req.url}`, {
    ip: req.ip,
    userAgent: req.get("User-Agent"),
    timestamp: new Date().toISOString(),
  });
  next();
});

// Database connections
let db;
let redisClient;

// Initialize database connections
async function initializeConnections() {
  try {
    // MySQL connection with connection pooling
    db = await mysql.createConnection({
      host: process.env.MYSQL_HOST || "localhost",
      port: process.env.MYSQL_PORT || 3306,
      user: process.env.MYSQL_USER || "root",
      password: process.env.MYSQL_PASSWORD || "password",
      database: process.env.MYSQL_DATABASE || "logs_db",
      charset: "utf8mb4",
    });

    // Create logs table if not exists
    await db.execute(`
      CREATE TABLE IF NOT EXISTS logs (
        id BIGINT AUTO_INCREMENT PRIMARY KEY,
        service_name VARCHAR(255) NOT NULL,
        level ENUM('error', 'warn', 'info', 'debug', 'trace') NOT NULL DEFAULT 'info',
        message TEXT NOT NULL,
        metadata JSON,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        processed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        INDEX idx_service_timestamp (service_name, timestamp),
        INDEX idx_level_timestamp (level, timestamp)
      )
    `);

    // Redis connection
    redisClient = redis.createClient({
      host: process.env.REDIS_HOST || "localhost",
      port: process.env.REDIS_PORT || 6379,
      retryDelayOnFailover: 100,
      maxRetriesPerRequest: 3,
    });

    redisClient.on("error", (err) => {
      logger.error("Redis Client Error:", err);
    });

    redisClient.on("connect", () => {
      logger.info("Connected to Redis");
    });

    await redisClient.connect();

    logger.info("Database connections established successfully");
  } catch (error) {
    logger.error("Error initializing connections:", error);
    process.exit(1);
  }
}

// Health check endpoint
app.get("/health", (req, res) => {
  res.json({
    status: "healthy",
    service: "log-aggregator-service",
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  });
});

// Store log entry
app.post("/logs", async (req, res) => {
  try {
    const { serviceName, level = "info", message, metadata = {} } = req.body;

    // Validation
    if (!serviceName || !message) {
      return res.status(400).json({
        error: "serviceName and message are required",
        code: "MISSING_REQUIRED_FIELDS",
      });
    }

    const validLevels = ["error", "warn", "info", "debug", "trace"];
    if (!validLevels.includes(level)) {
      return res.status(400).json({
        error: `Invalid log level. Must be one of: ${validLevels.join(", ")}`,
        code: "INVALID_LOG_LEVEL",
      });
    }

    // Insert into MySQL
    const [result] = await db.execute(
      "INSERT INTO logs (service_name, level, message, metadata) VALUES (?, ?, ?, ?)",
      [serviceName, level, message, JSON.stringify(metadata)],
    );

    const logId = result.insertId;

    // Cache recent logs in Redis (last 1000 logs per service)
    const cacheKey = `logs:${serviceName}:recent`;
    const logEntry = {
      id: logId,
      level,
      message,
      metadata,
      timestamp: new Date().toISOString(),
    };

    await redisClient.lPush(cacheKey, JSON.stringify(logEntry));
    await redisClient.lTrim(cacheKey, 0, 999); // Keep only last 1000 logs
    await redisClient.expire(cacheKey, 3600); // Expire in 1 hour

    // Log the aggregated entry
    logger.info("Log aggregated", {
      logId,
      serviceName,
      level,
      messageLength: message.length,
    });

    res.status(201).json({
      message: "Log entry stored successfully",
      logId,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error("Error storing log entry:", error);
    res.status(500).json({
      error: "Internal server error",
      code: "LOG_STORAGE_ERROR",
    });
  }
});

// Get logs with filtering and pagination
app.get("/logs", async (req, res) => {
  try {
    const {
      serviceName,
      level,
      startTime,
      endTime,
      limit = 100,
      offset = 0,
      sortOrder = "DESC",
    } = req.query;

    let query = "SELECT * FROM logs WHERE 1=1";
    const params = [];

    // Build dynamic query
    if (serviceName) {
      query += " AND service_name = ?";
      params.push(serviceName);
    }

    if (level) {
      query += " AND level = ?";
      params.push(level);
    }

    if (startTime) {
      query += " AND timestamp >= ?";
      params.push(startTime);
    }

    if (endTime) {
      query += " AND timestamp <= ?";
      params.push(endTime);
    }

    query += ` ORDER BY timestamp ${sortOrder === "ASC" ? "ASC" : "DESC"}`;
    query += " LIMIT ? OFFSET ?";
    params.push(parseInt(limit), parseInt(offset));

    const [rows] = await db.execute(query, params);

    // Parse metadata JSON
    const logs = rows.map((row) => ({
      ...row,
      metadata:
        typeof row.metadata === "string"
          ? JSON.parse(row.metadata)
          : row.metadata,
    }));

    // Get total count for pagination
    let countQuery = "SELECT COUNT(*) as total FROM logs WHERE 1=1";
    const countParams = params.slice(0, -2); // Remove limit and offset

    if (serviceName) {
      countQuery += " AND service_name = ?";
    }
    if (level) {
      countQuery += " AND level = ?";
    }
    if (startTime) {
      countQuery += " AND timestamp >= ?";
    }
    if (endTime) {
      countQuery += " AND timestamp <= ?";
    }

    const [countResult] = await db.execute(countQuery, countParams);
    const total = countResult[0].total;

    res.json({
      logs,
      pagination: {
        total,
        limit: parseInt(limit),
        offset: parseInt(offset),
        hasMore: parseInt(offset) + parseInt(limit) < total,
      },
    });
  } catch (error) {
    logger.error("Error retrieving logs:", error);
    res.status(500).json({
      error: "Internal server error",
      code: "LOG_RETRIEVAL_ERROR",
    });
  }
});

// Get recent logs from cache (faster access)
app.get("/logs/:serviceName/recent", async (req, res) => {
  try {
    const { serviceName } = req.params;
    const { limit = 50 } = req.query;

    const cacheKey = `logs:${serviceName}:recent`;
    const cachedLogs = await redisClient.lRange(
      cacheKey,
      0,
      parseInt(limit) - 1,
    );

    const logs = cachedLogs.map((log) => JSON.parse(log));

    res.json({
      serviceName,
      logs,
      cached: true,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error("Error retrieving recent logs:", error);
    res.status(500).json({
      error: "Internal server error",
      code: "CACHE_RETRIEVAL_ERROR",
    });
  }
});

// Get log statistics
app.get("/stats", async (req, res) => {
  try {
    const { serviceName, timeRange = "1h" } = req.query;

    let timeFilter = "";
    const params = [];

    // Convert timeRange to MySQL interval
    const timeMap = {
      "1h": "INTERVAL 1 HOUR",
      "24h": "INTERVAL 24 HOUR",
      "7d": "INTERVAL 7 DAY",
      "30d": "INTERVAL 30 DAY",
    };

    timeFilter = `AND timestamp >= NOW() - ${timeMap[timeRange] || "INTERVAL 1 HOUR"}`;

    let baseQuery = `FROM logs WHERE 1=1 ${timeFilter}`;
    if (serviceName) {
      baseQuery += " AND service_name = ?";
      params.push(serviceName);
    }

    // Get total count
    const [totalResult] = await db.execute(
      `SELECT COUNT(*) as total ${baseQuery}`,
      params,
    );

    // Get count by level
    const [levelStats] = await db.execute(
      `SELECT level, COUNT(*) as count ${baseQuery} GROUP BY level`,
      params,
    );

    // Get count by service (if no specific service filter)
    let serviceStats = [];
    if (!serviceName) {
      const [serviceResult] = await db.execute(
        `SELECT service_name, COUNT(*) as count ${baseQuery} GROUP BY service_name ORDER BY count DESC LIMIT 10`,
        params,
      );
      serviceStats = serviceResult;
    }

    res.json({
      timeRange,
      serviceName: serviceName || "all",
      total: totalResult[0].total,
      levelStats: levelStats.reduce((acc, stat) => {
        acc[stat.level] = stat.count;
        return acc;
      }, {}),
      serviceStats,
      generatedAt: new Date().toISOString(),
    });
  } catch (error) {
    logger.error("Error retrieving statistics:", error);
    res.status(500).json({
      error: "Internal server error",
      code: "STATS_RETRIEVAL_ERROR",
    });
  }
});

// Bulk log insertion endpoint
app.post("/logs/bulk", async (req, res) => {
  try {
    const { logs } = req.body;

    if (!Array.isArray(logs) || logs.length === 0) {
      return res.status(400).json({
        error: "logs array is required and must not be empty",
        code: "INVALID_BULK_DATA",
      });
    }

    if (logs.length > 1000) {
      return res.status(400).json({
        error: "Maximum 1000 logs per bulk request",
        code: "BULK_LIMIT_EXCEEDED",
      });
    }

    const validLevels = ["error", "warn", "info", "debug", "trace"];

    // Validate all logs
    for (const log of logs) {
      if (!log.serviceName || !log.message) {
        return res.status(400).json({
          error: "Each log must have serviceName and message",
          code: "INVALID_LOG_ENTRY",
        });
      }

      if (log.level && !validLevels.includes(log.level)) {
        return res.status(400).json({
          error: `Invalid log level: ${log.level}. Must be one of: ${validLevels.join(", ")}`,
          code: "INVALID_LOG_LEVEL",
        });
      }
    }

    // Prepare bulk insert
    const values = logs.map((log) => [
      log.serviceName,
      log.level || "info",
      log.message,
      JSON.stringify(log.metadata || {}),
    ]);

    const placeholders = values.map(() => "(?, ?, ?, ?)").join(",");
    const flatValues = values.flat();

    const [result] = await db.execute(
      `INSERT INTO logs (service_name, level, message, metadata) VALUES ${placeholders}`,
      flatValues,
    );

    logger.info("Bulk logs inserted", {
      count: logs.length,
      firstId: result.insertId,
    });

    res.status(201).json({
      message: "Bulk logs stored successfully",
      count: logs.length,
      firstId: result.insertId,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    logger.error("Error storing bulk logs:", error);
    res.status(500).json({
      error: "Internal server error",
      code: "BULK_STORAGE_ERROR",
    });
  }
});

// Global error handling middleware
app.use((err, req, res, next) => {
  logger.error("Unhandled error:", {
    error: err.message,
    stack: err.stack,
    url: req.url,
    method: req.method,
    ip: req.ip,
  });

  // Don't expose error details in production
  const isDevelopment = process.env.NODE_ENV === "development";

  res.status(err.status || 500).json({
    error: isDevelopment ? err.message : "Internal server error",
    code: err.code || "INTERNAL_ERROR",
    ...(isDevelopment && { stack: err.stack }),
  });
});

// Handle 404 errors
app.use((req, res) => {
  logger.warn("Route not found:", { url: req.url, method: req.method });
  res.status(404).json({
    error: "Route not found",
    code: "ROUTE_NOT_FOUND",
    path: req.url,
  });
});

// Graceful shutdown
process.on("SIGTERM", async () => {
  logger.info("SIGTERM received, shutting down gracefully");

  if (db) {
    await db.end();
    logger.info("MySQL connection closed");
  }

  if (redisClient) {
    await redisClient.quit();
    logger.info("Redis connection closed");
  }

  process.exit(0);
});

// Start server
async function startServer() {
  await initializeConnections();

  const server = app.listen(PORT, () => {
    logger.info(`Log Aggregator Service running on port ${PORT}`);
  });

  return server;
}

// Export app for testing
module.exports = { app, startServer, initializeConnections };

// Start server if not in test mode
if (process.env.NODE_ENV !== "test") {
  startServer().catch((error) => {
    logger.error("Failed to start server:", error);
    process.exit(1);
  });
}
