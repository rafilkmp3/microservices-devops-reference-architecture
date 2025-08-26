const express = require("express");
const mysql = require("mysql2/promise");
const redis = require("redis");
const cors = require("cors");
require("dotenv").config();

const app = express();
const PORT = process.env.PORT || 3001;

// Middleware
app.use(cors());
app.use(express.json());

// Database connection
let db;
let redisClient;

// Configuration storage
const configurations = new Map();

// Initialize database connections
async function initializeConnections() {
  try {
    // MySQL connection
    db = await mysql.createConnection({
      host: process.env.MYSQL_HOST || "localhost",
      port: process.env.MYSQL_PORT || 3306,
      user: process.env.MYSQL_USER || "root",
      password: process.env.MYSQL_PASSWORD || "password",
      database: process.env.MYSQL_DATABASE || "config_db",
    });

    // Create configurations table if not exists
    await db.execute(`
      CREATE TABLE IF NOT EXISTS configurations (
        id INT AUTO_INCREMENT PRIMARY KEY,
        service_name VARCHAR(255) NOT NULL,
        config_key VARCHAR(255) NOT NULL,
        config_value TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY unique_service_key (service_name, config_key)
      )
    `);

    // Redis connection
    redisClient = redis.createClient({
      host: process.env.REDIS_HOST || "localhost",
      port: process.env.REDIS_PORT || 6379,
    });

    await redisClient.connect();

    console.log("Database connections established successfully");
  } catch (error) {
    console.error("Error initializing connections:", error);
    process.exit(1);
  }
}

// Routes
app.get("/health", (req, res) => {
  res.json({
    status: "healthy",
    service: "configuration-service",
    timestamp: new Date().toISOString(),
  });
});

// Get configuration for a service
app.get("/config/:serviceName", async (req, res) => {
  try {
    const { serviceName } = req.params;

    // Try Redis cache first
    const cached = await redisClient.get(`config:${serviceName}`);
    if (cached) {
      return res.json(JSON.parse(cached));
    }

    // Get from MySQL
    const [rows] = await db.execute(
      "SELECT config_key, config_value FROM configurations WHERE service_name = ?",
      [serviceName],
    );

    const config = rows.reduce((acc, row) => {
      acc[row.config_key] = row.config_value;
      return acc;
    }, {});

    // Cache in Redis for 5 minutes
    await redisClient.setEx(
      `config:${serviceName}`,
      300,
      JSON.stringify(config),
    );

    res.json(config);
  } catch (error) {
    console.error("Error fetching configuration:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Set configuration for a service
app.post("/config/:serviceName", async (req, res) => {
  try {
    const { serviceName } = req.params;
    const { key, value } = req.body;

    if (!key || !value) {
      return res.status(400).json({ error: "Key and value are required" });
    }

    // Insert or update configuration
    await db.execute(
      "INSERT INTO configurations (service_name, config_key, config_value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE config_value = VALUES(config_value)",
      [serviceName, key, value],
    );

    // Invalidate cache
    await redisClient.del(`config:${serviceName}`);

    res.json({ message: "Configuration updated successfully" });
  } catch (error) {
    console.error("Error updating configuration:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Get all configurations
app.get("/config", async (req, res) => {
  try {
    const [rows] = await db.execute(
      "SELECT * FROM configurations ORDER BY service_name, config_key",
    );
    res.json(rows);
  } catch (error) {
    console.error("Error fetching all configurations:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Delete configuration
app.delete("/config/:serviceName/:key", async (req, res) => {
  try {
    const { serviceName, key } = req.params;

    await db.execute(
      "DELETE FROM configurations WHERE service_name = ? AND config_key = ?",
      [serviceName, key],
    );

    // Invalidate cache
    await redisClient.del(`config:${serviceName}`);

    res.json({ message: "Configuration deleted successfully" });
  } catch (error) {
    console.error("Error deleting configuration:", error);
    res.status(500).json({ error: "Internal server error" });
  }
});

// Start server
async function startServer() {
  await initializeConnections();

  const server = app.listen(PORT, () => {
    console.log(`Configuration Service running on port ${PORT}`);
  });

  return server;
}

// Export app for testing
module.exports = { app, startServer, initializeConnections };

// Start server if not in test mode
if (process.env.NODE_ENV !== "test") {
  startServer();
}
