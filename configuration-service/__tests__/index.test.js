const request = require("supertest");
const mysql = require("mysql2/promise");
const redis = require("redis");

// Mock external dependencies
jest.mock("mysql2/promise");
jest.mock("redis");

describe("Configuration Service", () => {
  let mockDb;
  let mockRedisClient;
  let app;

  beforeAll(() => {
    // Setup environment variables for testing
    process.env.NODE_ENV = "test";
    process.env.PORT = "3001";
    process.env.MYSQL_HOST = "localhost";
    process.env.MYSQL_PORT = "3306";
    process.env.MYSQL_USER = "testuser";
    process.env.MYSQL_PASSWORD = "testpass";
    process.env.MYSQL_DATABASE = "test_db";
    process.env.REDIS_HOST = "localhost";
    process.env.REDIS_PORT = "6379";
  });

  beforeEach(async () => {
    // Clear module cache to ensure fresh imports
    jest.clearAllMocks();
    
    // Delete require cache for the app
    delete require.cache[require.resolve("../index")];

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
      setEx: jest.fn(),
      del: jest.fn(),
      quit: jest.fn().mockResolvedValue(undefined),
    };

    redis.createClient.mockReturnValue(mockRedisClient);

    // Setup default database execute responses
    mockDb.execute
      .mockResolvedValueOnce([]) // CREATE TABLE response
      .mockResolvedValue([[], {}]); // Default response for other queries

    // Import the app after setting up mocks
    const appModule = require("../index");
    app = appModule.app;

    // Wait for initialization
    await new Promise((resolve) => setTimeout(resolve, 100));
  });

  afterEach(async () => {
    // Cleanup
    if (app && app.close) {
      await new Promise((resolve) => app.close(resolve));
    }
  });

  describe("Health Check", () => {
    test("GET /health should return healthy status", async () => {
      const response = await request(app).get("/health").expect(200);

      expect(response.body).toEqual({
        status: "healthy",
        service: "configuration-service",
        timestamp: expect.any(String),
      });
    });
  });

  describe("Configuration Management", () => {
    describe("GET /config/:serviceName", () => {
      test("should return cached configuration when available", async () => {
        const mockConfig = { key1: "value1", key2: "value2" };
        mockRedisClient.get.mockResolvedValue(JSON.stringify(mockConfig));

        const response = await request(app)
          .get("/config/test-service")
          .expect(200);

        expect(response.body).toEqual(mockConfig);
        expect(mockRedisClient.get).toHaveBeenCalledWith("config:test-service");
        expect(mockDb.execute).not.toHaveBeenCalledWith(
          expect.stringContaining("SELECT"),
        );
      });

      test("should fetch from database when cache miss", async () => {
        mockRedisClient.get.mockResolvedValue(null);
        mockDb.execute.mockResolvedValue([
          [
            { config_key: "key1", config_value: "value1" },
            { config_key: "key2", config_value: "value2" },
          ],
        ]);

        const response = await request(app)
          .get("/config/test-service")
          .expect(200);

        expect(response.body).toEqual({
          key1: "value1",
          key2: "value2",
        });

        expect(mockRedisClient.get).toHaveBeenCalledWith("config:test-service");
        expect(mockDb.execute).toHaveBeenCalledWith(
          "SELECT config_key, config_value FROM configurations WHERE service_name = ?",
          ["test-service"],
        );
        expect(mockRedisClient.setEx).toHaveBeenCalledWith(
          "config:test-service",
          300,
          JSON.stringify({ key1: "value1", key2: "value2" }),
        );
      });

      test("should return empty object when no configuration found", async () => {
        mockRedisClient.get.mockResolvedValue(null);
        mockDb.execute.mockResolvedValue([[]]);

        const response = await request(app)
          .get("/config/test-service")
          .expect(200);

        expect(response.body).toEqual({});
      });

      test("should handle database errors gracefully", async () => {
        mockRedisClient.get.mockResolvedValue(null);
        mockDb.execute.mockRejectedValue(
          new Error("Database connection failed"),
        );

        const response = await request(app)
          .get("/config/test-service")
          .expect(500);

        expect(response.body).toEqual({
          error: "Internal server error",
        });
      });
    });

    describe("POST /config/:serviceName", () => {
      test("should set configuration successfully", async () => {
        mockDb.execute.mockResolvedValue([{ insertId: 1, affectedRows: 1 }]);

        const response = await request(app)
          .post("/config/test-service")
          .send({ key: "test-key", value: "test-value" })
          .expect(200);

        expect(response.body).toEqual({
          message: "Configuration updated successfully",
        });

        expect(mockDb.execute).toHaveBeenCalledWith(
          "INSERT INTO configurations (service_name, config_key, config_value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE config_value = VALUES(config_value)",
          ["test-service", "test-key", "test-value"],
        );
        expect(mockRedisClient.del).toHaveBeenCalledWith("config:test-service");
      });

      test("should return 400 when key is missing", async () => {
        const response = await request(app)
          .post("/config/test-service")
          .send({ value: "test-value" })
          .expect(400);

        expect(response.body).toEqual({
          error: "Key and value are required",
        });
      });

      test("should return 400 when value is missing", async () => {
        const response = await request(app)
          .post("/config/test-service")
          .send({ key: "test-key" })
          .expect(400);

        expect(response.body).toEqual({
          error: "Key and value are required",
        });
      });

      test("should handle database errors on insert", async () => {
        mockDb.execute.mockRejectedValue(new Error("Insert failed"));

        const response = await request(app)
          .post("/config/test-service")
          .send({ key: "test-key", value: "test-value" })
          .expect(500);

        expect(response.body).toEqual({
          error: "Internal server error",
        });
      });
    });

    describe("GET /config", () => {
      test("should return all configurations", async () => {
        const mockConfigs = [
          {
            id: 1,
            service_name: "service1",
            config_key: "key1",
            config_value: "value1",
            created_at: "2024-01-01T00:00:00Z",
            updated_at: "2024-01-01T00:00:00Z",
          },
          {
            id: 2,
            service_name: "service2",
            config_key: "key2",
            config_value: "value2",
            created_at: "2024-01-01T00:00:00Z",
            updated_at: "2024-01-01T00:00:00Z",
          },
        ];

        mockDb.execute.mockResolvedValue([mockConfigs]);

        const response = await request(app).get("/config").expect(200);

        expect(response.body).toEqual(mockConfigs);
        expect(mockDb.execute).toHaveBeenCalledWith(
          "SELECT * FROM configurations ORDER BY service_name, config_key",
        );
      });

      test("should handle database errors on fetch all", async () => {
        mockDb.execute.mockRejectedValue(new Error("Query failed"));

        const response = await request(app).get("/config").expect(500);

        expect(response.body).toEqual({
          error: "Internal server error",
        });
      });
    });

    describe("DELETE /config/:serviceName/:key", () => {
      test("should delete configuration successfully", async () => {
        mockDb.execute.mockResolvedValue([{ affectedRows: 1 }]);

        const response = await request(app)
          .delete("/config/test-service/test-key")
          .expect(200);

        expect(response.body).toEqual({
          message: "Configuration deleted successfully",
        });

        expect(mockDb.execute).toHaveBeenCalledWith(
          "DELETE FROM configurations WHERE service_name = ? AND config_key = ?",
          ["test-service", "test-key"],
        );
        expect(mockRedisClient.del).toHaveBeenCalledWith("config:test-service");
      });

      test("should handle delete errors", async () => {
        mockDb.execute.mockRejectedValue(new Error("Delete failed"));

        const response = await request(app)
          .delete("/config/test-service/test-key")
          .expect(500);

        expect(response.body).toEqual({
          error: "Internal server error",
        });
      });
    });
  });

  describe("Error Handling", () => {
    test("should handle invalid JSON payload", async () => {
      const response = await request(app)
        .post("/config/test-service")
        .send("invalid json")
        .set("Content-Type", "application/json")
        .expect(400);
    });

    test("should handle 404 for non-existent routes", async () => {
      const response = await request(app)
        .get("/non-existent-route")
        .expect(404);
    });
  });

  describe("Database Initialization", () => {
    test("should create configurations table on startup", async () => {
      // Verify table creation was called
      expect(mockDb.execute).toHaveBeenCalledWith(
        expect.stringContaining("CREATE TABLE IF NOT EXISTS configurations"),
      );
    });

    test("should establish Redis connection on startup", async () => {
      expect(redis.createClient).toHaveBeenCalledWith({
        host: "localhost",
        port: 6379,
      });
      expect(mockRedisClient.connect).toHaveBeenCalled();
    });
  });

  describe("Cache Management", () => {
    test("should invalidate cache when configuration is updated", async () => {
      mockDb.execute.mockResolvedValue([{ insertId: 1, affectedRows: 1 }]);

      await request(app)
        .post("/config/test-service")
        .send({ key: "test-key", value: "test-value" });

      expect(mockRedisClient.del).toHaveBeenCalledWith("config:test-service");
    });

    test("should invalidate cache when configuration is deleted", async () => {
      mockDb.execute.mockResolvedValue([{ affectedRows: 1 }]);

      await request(app).delete("/config/test-service/test-key");

      expect(mockRedisClient.del).toHaveBeenCalledWith("config:test-service");
    });
  });

  describe("Integration Scenarios", () => {
    test("should handle complete CRUD lifecycle", async () => {
      // Create
      mockDb.execute.mockResolvedValueOnce([{ insertId: 1, affectedRows: 1 }]);

      await request(app)
        .post("/config/test-service")
        .send({ key: "lifecycle-key", value: "initial-value" })
        .expect(200);

      // Update (same endpoint)
      mockDb.execute.mockResolvedValueOnce([{ insertId: 1, affectedRows: 1 }]);

      await request(app)
        .post("/config/test-service")
        .send({ key: "lifecycle-key", value: "updated-value" })
        .expect(200);

      // Read
      mockRedisClient.get.mockResolvedValue(null);
      mockDb.execute.mockResolvedValueOnce([
        [{ config_key: "lifecycle-key", config_value: "updated-value" }],
      ]);

      const getResponse = await request(app)
        .get("/config/test-service")
        .expect(200);

      expect(getResponse.body).toEqual({
        "lifecycle-key": "updated-value",
      });

      // Delete
      mockDb.execute.mockResolvedValueOnce([{ affectedRows: 1 }]);

      await request(app)
        .delete("/config/test-service/lifecycle-key")
        .expect(200);
    });

    test("should handle concurrent requests gracefully", async () => {
      mockRedisClient.get.mockResolvedValue(null);
      mockDb.execute.mockResolvedValue([
        [{ config_key: "key1", config_value: "value1" }],
      ]);

      // Make multiple concurrent requests
      const promises = Array(5)
        .fill()
        .map(() => request(app).get("/config/test-service"));

      const responses = await Promise.all(promises);

      responses.forEach((response) => {
        expect(response.status).toBe(200);
        expect(response.body).toEqual({ key1: "value1" });
      });
    });
  });
});

// Edge cases and error scenarios
describe("Configuration Service Edge Cases", () => {
  let app;

  beforeEach(() => {
    // Import a fresh instance
    delete require.cache[require.resolve("../index.js")];
  });

  test("should handle Redis connection failure gracefully", async () => {
    const mockRedisClient = {
      connect: jest
        .fn()
        .mockRejectedValue(new Error("Redis connection failed")),
      quit: jest.fn(),
    };

    redis.createClient.mockReturnValue(mockRedisClient);

    // The app should still handle the error during initialization
    expect(async () => {
      app = require("../index.js");
      await new Promise((resolve) => setTimeout(resolve, 100));
    }).not.toThrow();
  });

  test("should handle MySQL connection failure", async () => {
    mysql.createConnection.mockRejectedValue(
      new Error("MySQL connection failed"),
    );

    expect(async () => {
      app = require("../index.js");
      await new Promise((resolve) => setTimeout(resolve, 100));
    }).not.toThrow();
  });

  test("should handle large configuration values", async () => {
    const mockDb = {
      execute: jest.fn(),
      end: jest.fn(),
    };

    const mockRedisClient = {
      connect: jest.fn().mockResolvedValue(undefined),
      get: jest.fn(),
      setEx: jest.fn(),
      del: jest.fn(),
      quit: jest.fn(),
    };

    mysql.createConnection.mockResolvedValue(mockDb);
    redis.createClient.mockReturnValue(mockRedisClient);

    mockDb.execute
      .mockResolvedValueOnce([]) // CREATE TABLE
      .mockResolvedValue([{ insertId: 1, affectedRows: 1 }]);

    app = require("../index.js");
    await new Promise((resolve) => setTimeout(resolve, 100));

    const largeValue = "x".repeat(10000); // 10KB value

    const response = await request(app)
      .post("/config/test-service")
      .send({ key: "large-key", value: largeValue })
      .expect(200);

    expect(response.body).toEqual({
      message: "Configuration updated successfully",
    });

    expect(mockDb.execute).toHaveBeenCalledWith(
      "INSERT INTO configurations (service_name, config_key, config_value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE config_value = VALUES(config_value)",
      ["test-service", "large-key", largeValue],
    );
  });

  afterEach(async () => {
    if (app && app.close) {
      await new Promise((resolve) => app.close(resolve));
    }
  });
});
