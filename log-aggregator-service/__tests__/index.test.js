const request = require("supertest");
const mysql = require("mysql2/promise");
const redis = require("redis");
const winston = require("winston");

// Mock external dependencies
jest.mock("mysql2/promise");
jest.mock("redis");
jest.mock("winston");

// Import the app after mocking dependencies
const { app } = require("../index");

describe("Log Aggregator Service", () => {
  let mockDb;
  let mockRedisClient;
  let mockLogger;

  beforeAll(() => {
    // Setup environment variables for testing
    process.env.NODE_ENV = "test";
    process.env.PORT = "3002";
    process.env.MYSQL_HOST = "localhost";
    process.env.MYSQL_PORT = "3306";
    process.env.MYSQL_USER = "testuser";
    process.env.MYSQL_PASSWORD = "testpass";
    process.env.MYSQL_DATABASE = "test_logs_db";
    process.env.REDIS_HOST = "localhost";
    process.env.REDIS_PORT = "6379";
    process.env.LOG_LEVEL = "silent"; // Suppress logs during testing
  });

  beforeEach(async () => {
    // Clear module cache and mocks
    jest.clearAllMocks();

    // Mock MySQL connection
    mockDb = {
      execute: jest.fn(),
      end: jest.fn(),
    };
    mysql.createConnection.mockResolvedValue(mockDb);

    // Mock Redis client
    mockRedisClient = {
      connect: jest.fn().mockResolvedValue(undefined),
      get: jest.fn(),
      lPush: jest.fn(),
      lTrim: jest.fn(),
      expire: jest.fn(),
      lRange: jest.fn(),
      quit: jest.fn().mockResolvedValue(undefined),
      on: jest.fn(),
    };
    redis.createClient.mockReturnValue(mockRedisClient);

    // Mock Winston logger
    mockLogger = {
      info: jest.fn(),
      error: jest.fn(),
      warn: jest.fn(),
      debug: jest.fn(),
    };

    const mockTransports = {
      File: jest.fn(),
      Console: jest.fn(),
    };

    winston.createLogger.mockReturnValue(mockLogger);
    winston.transports = mockTransports;
    winston.format = {
      combine: jest.fn().mockReturnValue({}),
      timestamp: jest.fn().mockReturnValue({}),
      errors: jest.fn().mockReturnValue({}),
      json: jest.fn().mockReturnValue({}),
      colorize: jest.fn().mockReturnValue({}),
      simple: jest.fn().mockReturnValue({}),
    };

    // Setup default database responses
    mockDb.execute
      .mockResolvedValueOnce([]) // CREATE TABLE response
      .mockResolvedValue([[], {}]); // Default response

    // Wait for initialization
    await new Promise((resolve) => setTimeout(resolve, 100));
  });

  afterEach(async () => {
    if (app && app.close) {
      await new Promise((resolve) => app.close(resolve));
    }
  });

  describe("Health Check", () => {
    test("GET /health should return healthy status", async () => {
      const response = await request(app).get("/health").expect(200);

      expect(response.body).toEqual({
        status: "healthy",
        service: "log-aggregator-service",
        timestamp: expect.any(String),
        uptime: expect.any(Number),
      });
    });
  });

  describe("Log Storage", () => {
    describe("POST /logs", () => {
      test("should store log entry successfully", async () => {
        const mockResult = { insertId: 123, affectedRows: 1 };
        mockDb.execute.mockResolvedValue([mockResult]);

        const logEntry = {
          serviceName: "test-service",
          level: "info",
          message: "Test log message",
          metadata: { userId: 123, action: "login" },
        };

        const response = await request(app)
          .post("/logs")
          .send(logEntry)
          .expect(201);

        expect(response.body).toEqual({
          message: "Log entry stored successfully",
          logId: 123,
          timestamp: expect.any(String),
        });

        expect(mockDb.execute).toHaveBeenCalledWith(
          "INSERT INTO logs (service_name, level, message, metadata) VALUES (?, ?, ?, ?)",
          [
            "test-service",
            "info",
            "Test log message",
            JSON.stringify({ userId: 123, action: "login" }),
          ],
        );
      });

      test("should cache recent logs in Redis", async () => {
        const mockResult = { insertId: 123 };
        mockDb.execute.mockResolvedValue([mockResult]);

        const logEntry = {
          serviceName: "test-service",
          level: "info",
          message: "Test log message",
          metadata: { userId: 123 },
        };

        await request(app).post("/logs").send(logEntry).expect(201);

        expect(mockRedisClient.lPush).toHaveBeenCalledWith(
          "logs:test-service:recent",
          expect.stringContaining('"message":"Test log message"'),
        );
        expect(mockRedisClient.lTrim).toHaveBeenCalledWith(
          "logs:test-service:recent",
          0,
          999,
        );
        expect(mockRedisClient.expire).toHaveBeenCalledWith(
          "logs:test-service:recent",
          3600,
        );
      });

      test("should return 400 for missing serviceName", async () => {
        const logEntry = {
          level: "info",
          message: "Test log message",
        };

        const response = await request(app)
          .post("/logs")
          .send(logEntry)
          .expect(400);

        expect(response.body).toEqual({
          error: "serviceName and message are required",
          code: "MISSING_REQUIRED_FIELDS",
        });
      });

      test("should return 400 for missing message", async () => {
        const logEntry = {
          serviceName: "test-service",
          level: "info",
        };

        const response = await request(app)
          .post("/logs")
          .send(logEntry)
          .expect(400);

        expect(response.body).toEqual({
          error: "serviceName and message are required",
          code: "MISSING_REQUIRED_FIELDS",
        });
      });

      test("should return 400 for invalid log level", async () => {
        const logEntry = {
          serviceName: "test-service",
          level: "invalid-level",
          message: "Test log message",
        };

        const response = await request(app)
          .post("/logs")
          .send(logEntry)
          .expect(400);

        expect(response.body).toEqual({
          error:
            "Invalid log level. Must be one of: error, warn, info, debug, trace",
          code: "INVALID_LOG_LEVEL",
        });
      });

      test("should default to info level when not specified", async () => {
        const mockResult = { insertId: 123 };
        mockDb.execute.mockResolvedValue([mockResult]);

        const logEntry = {
          serviceName: "test-service",
          message: "Test log message",
        };

        await request(app).post("/logs").send(logEntry).expect(201);

        expect(mockDb.execute).toHaveBeenCalledWith(
          "INSERT INTO logs (service_name, level, message, metadata) VALUES (?, ?, ?, ?)",
          ["test-service", "info", "Test log message", "{}"],
        );
      });

      test("should handle database errors gracefully", async () => {
        mockDb.execute.mockRejectedValue(new Error("Database error"));

        const logEntry = {
          serviceName: "test-service",
          level: "info",
          message: "Test log message",
        };

        const response = await request(app)
          .post("/logs")
          .send(logEntry)
          .expect(500);

        expect(response.body).toEqual({
          error: "Internal server error",
          code: "LOG_STORAGE_ERROR",
        });
      });
    });

    describe("POST /logs/bulk", () => {
      test("should store multiple log entries successfully", async () => {
        const mockResult = { insertId: 100, affectedRows: 2 };
        mockDb.execute.mockResolvedValue([mockResult]);

        const bulkLogs = {
          logs: [
            {
              serviceName: "service1",
              level: "info",
              message: "First log message",
              metadata: { userId: 1 },
            },
            {
              serviceName: "service2",
              level: "error",
              message: "Error message",
              metadata: { error: "timeout" },
            },
          ],
        };

        const response = await request(app)
          .post("/logs/bulk")
          .send(bulkLogs)
          .expect(201);

        expect(response.body).toEqual({
          message: "Bulk logs stored successfully",
          count: 2,
          firstId: 100,
          timestamp: expect.any(String),
        });

        expect(mockDb.execute).toHaveBeenCalledWith(
          "INSERT INTO logs (service_name, level, message, metadata) VALUES (?, ?, ?, ?),(?, ?, ?, ?)",
          [
            "service1",
            "info",
            "First log message",
            '{"userId":1}',
            "service2",
            "error",
            "Error message",
            '{"error":"timeout"}',
          ],
        );
      });

      test("should return 400 for empty logs array", async () => {
        const response = await request(app)
          .post("/logs/bulk")
          .send({ logs: [] })
          .expect(400);

        expect(response.body).toEqual({
          error: "logs array is required and must not be empty",
          code: "INVALID_BULK_DATA",
        });
      });

      test("should return 400 for exceeding bulk limit", async () => {
        const largeBatch = {
          logs: Array(1001).fill({
            serviceName: "test-service",
            message: "Test message",
          }),
        };

        const response = await request(app)
          .post("/logs/bulk")
          .send(largeBatch)
          .expect(400);

        expect(response.body).toEqual({
          error: "Maximum 1000 logs per bulk request",
          code: "BULK_LIMIT_EXCEEDED",
        });
      });

      test("should validate all log entries in bulk request", async () => {
        const bulkLogs = {
          logs: [
            {
              serviceName: "service1",
              message: "Valid log",
            },
            {
              serviceName: "service2",
              // Missing message
            },
          ],
        };

        const response = await request(app)
          .post("/logs/bulk")
          .send(bulkLogs)
          .expect(400);

        expect(response.body).toEqual({
          error: "Each log must have serviceName and message",
          code: "INVALID_LOG_ENTRY",
        });
      });
    });
  });

  describe("Log Retrieval", () => {
    describe("GET /logs", () => {
      test("should retrieve logs with default parameters", async () => {
        const mockLogs = [
          {
            id: 1,
            service_name: "test-service",
            level: "info",
            message: "Test message",
            metadata: '{"userId":123}',
            timestamp: "2024-01-01T00:00:00Z",
          },
        ];

        const mockCountResult = [{ total: 1 }];
        mockDb.execute
          .mockResolvedValueOnce([mockLogs])
          .mockResolvedValueOnce([mockCountResult]);

        const response = await request(app).get("/logs").expect(200);

        expect(response.body).toEqual({
          logs: [
            {
              id: 1,
              service_name: "test-service",
              level: "info",
              message: "Test message",
              metadata: { userId: 123 },
              timestamp: "2024-01-01T00:00:00Z",
            },
          ],
          pagination: {
            total: 1,
            limit: 100,
            offset: 0,
            hasMore: false,
          },
        });
      });

      test("should filter logs by service name", async () => {
        const mockLogs = [
          {
            id: 1,
            service_name: "specific-service",
            level: "info",
            message: "Test message",
            metadata: "{}",
            timestamp: "2024-01-01T00:00:00Z",
          },
        ];

        const mockCountResult = [{ total: 1 }];
        mockDb.execute
          .mockResolvedValueOnce([mockLogs])
          .mockResolvedValueOnce([mockCountResult]);

        const response = await request(app)
          .get("/logs?serviceName=specific-service")
          .expect(200);

        expect(mockDb.execute).toHaveBeenCalledWith(
          expect.stringContaining("AND service_name = ?"),
          expect.arrayContaining(["specific-service"]),
        );
      });

      test("should filter logs by level", async () => {
        mockDb.execute
          .mockResolvedValueOnce([[]])
          .mockResolvedValueOnce([[{ total: 0 }]]);

        await request(app).get("/logs?level=error").expect(200);

        expect(mockDb.execute).toHaveBeenCalledWith(
          expect.stringContaining("AND level = ?"),
          expect.arrayContaining(["error"]),
        );
      });

      test("should apply pagination correctly", async () => {
        mockDb.execute
          .mockResolvedValueOnce([[]])
          .mockResolvedValueOnce([[{ total: 0 }]]);

        await request(app).get("/logs?limit=50&offset=100").expect(200);

        expect(mockDb.execute).toHaveBeenCalledWith(
          expect.stringContaining("LIMIT ? OFFSET ?"),
          expect.arrayContaining([50, 100]),
        );
      });

      test("should filter by time range", async () => {
        mockDb.execute
          .mockResolvedValueOnce([[]])
          .mockResolvedValueOnce([[{ total: 0 }]]);

        await request(app)
          .get(
            "/logs?startTime=2024-01-01T00:00:00Z&endTime=2024-01-02T00:00:00Z",
          )
          .expect(200);

        expect(mockDb.execute).toHaveBeenCalledWith(
          expect.stringContaining("AND timestamp >= ?"),
          expect.arrayContaining(["2024-01-01T00:00:00Z"]),
        );
      });
    });

    describe("GET /logs/:serviceName/recent", () => {
      test("should retrieve recent cached logs", async () => {
        const cachedLogs = [
          JSON.stringify({
            id: 1,
            level: "info",
            message: "Recent message",
            metadata: { userId: 123 },
            timestamp: "2024-01-01T00:00:00Z",
          }),
        ];

        mockRedisClient.lRange.mockResolvedValue(cachedLogs);

        const response = await request(app)
          .get("/logs/test-service/recent")
          .expect(200);

        expect(response.body).toEqual({
          serviceName: "test-service",
          logs: [
            {
              id: 1,
              level: "info",
              message: "Recent message",
              metadata: { userId: 123 },
              timestamp: "2024-01-01T00:00:00Z",
            },
          ],
          cached: true,
          timestamp: expect.any(String),
        });

        expect(mockRedisClient.lRange).toHaveBeenCalledWith(
          "logs:test-service:recent",
          0,
          49,
        );
      });

      test("should handle custom limit for recent logs", async () => {
        mockRedisClient.lRange.mockResolvedValue([]);

        await request(app)
          .get("/logs/test-service/recent?limit=20")
          .expect(200);

        expect(mockRedisClient.lRange).toHaveBeenCalledWith(
          "logs:test-service:recent",
          0,
          19,
        );
      });

      test("should handle Redis errors gracefully", async () => {
        mockRedisClient.lRange.mockRejectedValue(new Error("Redis error"));

        const response = await request(app)
          .get("/logs/test-service/recent")
          .expect(500);

        expect(response.body).toEqual({
          error: "Internal server error",
          code: "CACHE_RETRIEVAL_ERROR",
        });
      });
    });
  });

  describe("Statistics", () => {
    describe("GET /stats", () => {
      test("should return log statistics", async () => {
        const mockTotalResult = [{ total: 100 }];
        const mockLevelStats = [
          { level: "info", count: 60 },
          { level: "error", count: 30 },
          { level: "warn", count: 10 },
        ];
        const mockServiceStats = [
          { service_name: "service1", count: 70 },
          { service_name: "service2", count: 30 },
        ];

        mockDb.execute
          .mockResolvedValueOnce([mockTotalResult])
          .mockResolvedValueOnce([mockLevelStats])
          .mockResolvedValueOnce([mockServiceStats]);

        const response = await request(app).get("/stats").expect(200);

        expect(response.body).toEqual({
          timeRange: "1h",
          serviceName: "all",
          total: 100,
          levelStats: {
            info: 60,
            error: 30,
            warn: 10,
          },
          serviceStats: [
            { service_name: "service1", count: 70 },
            { service_name: "service2", count: 30 },
          ],
          generatedAt: expect.any(String),
        });
      });

      test("should filter stats by service", async () => {
        mockDb.execute
          .mockResolvedValue([[{ total: 50 }]])
          .mockResolvedValue([[]]);

        await request(app)
          .get("/stats?serviceName=specific-service")
          .expect(200);

        expect(mockDb.execute).toHaveBeenCalledWith(
          expect.stringContaining("AND service_name = ?"),
          expect.arrayContaining(["specific-service"]),
        );
      });

      test("should support different time ranges", async () => {
        mockDb.execute
          .mockResolvedValue([[{ total: 0 }]])
          .mockResolvedValue([[]]);

        await request(app).get("/stats?timeRange=24h").expect(200);

        expect(mockDb.execute).toHaveBeenCalledWith(
          expect.stringContaining("INTERVAL 24 HOUR"),
          expect.any(Array),
        );
      });
    });
  });

  describe("Error Handling and Edge Cases", () => {
    test("should handle malformed JSON in request body", async () => {
      const response = await request(app)
        .post("/logs")
        .send("invalid json")
        .set("Content-Type", "application/json")
        .expect(400);
    });

    test("should handle 404 for non-existent routes", async () => {
      const response = await request(app)
        .get("/non-existent-route")
        .expect(404);

      expect(response.body).toEqual({
        error: "Route not found",
        code: "ROUTE_NOT_FOUND",
        path: "/non-existent-route",
      });
    });

    test("should handle very large log messages", async () => {
      const mockResult = { insertId: 123 };
      mockDb.execute.mockResolvedValue([mockResult]);

      const largeMessage = "x".repeat(50000); // 50KB message

      const logEntry = {
        serviceName: "test-service",
        level: "info",
        message: largeMessage,
      };

      const response = await request(app)
        .post("/logs")
        .send(logEntry)
        .expect(201);

      expect(response.body.message).toBe("Log entry stored successfully");
    });

    test("should handle metadata with complex nested objects", async () => {
      const mockResult = { insertId: 123 };
      mockDb.execute.mockResolvedValue([mockResult]);

      const complexMetadata = {
        user: {
          id: 123,
          profile: {
            name: "John Doe",
            preferences: {
              theme: "dark",
              notifications: true,
            },
          },
        },
        request: {
          headers: {
            "user-agent": "Mozilla/5.0...",
            accept: "application/json",
          },
          body: { action: "login" },
        },
      };

      const logEntry = {
        serviceName: "test-service",
        level: "info",
        message: "User action",
        metadata: complexMetadata,
      };

      await request(app).post("/logs").send(logEntry).expect(201);

      expect(mockDb.execute).toHaveBeenCalledWith(
        "INSERT INTO logs (service_name, level, message, metadata) VALUES (?, ?, ?, ?)",
        [
          "test-service",
          "info",
          "User action",
          JSON.stringify(complexMetadata),
        ],
      );
    });
  });

  describe("Integration Scenarios", () => {
    test("should handle end-to-end log lifecycle", async () => {
      // Store a log
      const mockResult = { insertId: 123 };
      mockDb.execute.mockResolvedValueOnce([mockResult]);

      const logEntry = {
        serviceName: "integration-service",
        level: "info",
        message: "Integration test log",
        metadata: { test: true },
      };

      await request(app).post("/logs").send(logEntry).expect(201);

      // Verify it's cached
      expect(mockRedisClient.lPush).toHaveBeenCalled();

      // Retrieve from cache
      const cachedLog = JSON.stringify({
        id: 123,
        level: "info",
        message: "Integration test log",
        metadata: { test: true },
        timestamp: expect.any(String),
      });

      mockRedisClient.lRange.mockResolvedValue([cachedLog]);

      const recentResponse = await request(app)
        .get("/logs/integration-service/recent")
        .expect(200);

      expect(recentResponse.body.logs).toHaveLength(1);
      expect(recentResponse.body.logs[0].message).toBe("Integration test log");
    });

    test("should handle concurrent bulk operations", async () => {
      const mockResult = { insertId: 100 };
      mockDb.execute.mockResolvedValue([mockResult]);

      const bulkRequests = Array(3)
        .fill()
        .map((_, index) => ({
          logs: [
            {
              serviceName: `service-${index}`,
              level: "info",
              message: `Concurrent message ${index}`,
            },
          ],
        }));

      const promises = bulkRequests.map((bulk) =>
        request(app).post("/logs/bulk").send(bulk),
      );

      const responses = await Promise.all(promises);

      responses.forEach((response) => {
        expect(response.status).toBe(201);
        expect(response.body.message).toBe("Bulk logs stored successfully");
      });
    });
  });
});

// Database and infrastructure tests
describe("Log Aggregator Service Infrastructure", () => {
  let app;

  beforeEach(() => {
    delete require.cache[require.resolve("../index.js")];
  });

  test("should handle database initialization failure", async () => {
    mysql.createConnection.mockRejectedValue(new Error("DB connection failed"));

    const mockRedisClient = {
      connect: jest.fn().mockResolvedValue(undefined),
      quit: jest.fn(),
      on: jest.fn(),
    };
    redis.createClient.mockReturnValue(mockRedisClient);

    expect(async () => {
      // App already imported at module level
      await new Promise((resolve) => setTimeout(resolve, 100));
    }).not.toThrow();
  });

  test("should handle Redis connection failure", async () => {
    const mockDb = {
      execute: jest.fn().mockResolvedValue([]),
      end: jest.fn(),
    };
    mysql.createConnection.mockResolvedValue(mockDb);

    const mockRedisClient = {
      connect: jest
        .fn()
        .mockRejectedValue(new Error("Redis connection failed")),
      quit: jest.fn(),
      on: jest.fn(),
    };
    redis.createClient.mockReturnValue(mockRedisClient);

    expect(async () => {
      // App already imported at module level
      await new Promise((resolve) => setTimeout(resolve, 100));
    }).not.toThrow();
  });

  test("should create logs table with correct schema", async () => {
    const mockDb = {
      execute: jest.fn().mockResolvedValue([]),
      end: jest.fn(),
    };
    mysql.createConnection.mockResolvedValue(mockDb);

    const mockRedisClient = {
      connect: jest.fn().mockResolvedValue(undefined),
      quit: jest.fn(),
      on: jest.fn(),
    };
    redis.createClient.mockReturnValue(mockRedisClient);

    // App already imported at module level
    await new Promise((resolve) => setTimeout(resolve, 100));

    expect(mockDb.execute).toHaveBeenCalledWith(
      expect.stringContaining("CREATE TABLE IF NOT EXISTS logs"),
    );
    expect(mockDb.execute).toHaveBeenCalledWith(
      expect.stringContaining("service_name VARCHAR(255) NOT NULL"),
    );
    expect(mockDb.execute).toHaveBeenCalledWith(
      expect.stringContaining("metadata JSON"),
    );
  });

  afterEach(async () => {
    if (app && app.close) {
      await new Promise((resolve) => app.close(resolve));
    }
  });
});
