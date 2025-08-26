// Jest setup file for Configuration Service tests

// Extend Jest with custom matchers
expect.extend({
  toBeValidConfiguration(received) {
    const pass =
      received && typeof received === "object" && !Array.isArray(received);

    if (pass) {
      return {
        message: () =>
          `expected ${JSON.stringify(received)} not to be a valid configuration`,
        pass: true,
      };
    }
    return {
      message: () =>
        `expected ${JSON.stringify(received)} to be a valid configuration`,
      pass: false,
    };
  },

  toBeHealthyResponse(received) {
    const pass =
      received &&
      received.status === "healthy" &&
      received.service === "configuration-service" &&
      typeof received.timestamp === "string";

    if (pass) {
      return {
        message: () =>
          `expected ${JSON.stringify(received)} not to be a healthy response`,
        pass: true,
      };
    }
    return {
      message: () =>
        `expected ${JSON.stringify(received)} to be a healthy response`,
      pass: false,
    };
  },
});

// Global test timeout
jest.setTimeout(10000);

// Console warn/error suppression for cleaner test output
const originalConsole = { ...console };

beforeAll(() => {
  console.warn = jest.fn();
  console.error = jest.fn();
});

afterAll(() => {
  console.warn = originalConsole.warn;
  console.error = originalConsole.error;
});

// Mock process.exit to prevent tests from actually exiting
const mockExit = jest.spyOn(process, "exit").mockImplementation(() => {});
afterEach(() => {
  mockExit.mockClear();
});

// Global test data
global.testData = {
  validConfiguration: {
    "database.host": "localhost",
    "database.port": "3306",
    "cache.enabled": "true",
    "logging.level": "info",
  },

  mockConfigRows: [
    { config_key: "database.host", config_value: "localhost" },
    { config_key: "database.port", config_value: "3306" },
    { config_key: "cache.enabled", config_value: "true" },
    { config_key: "logging.level", config_value: "info" },
  ],

  healthResponse: {
    status: "healthy",
    service: "configuration-service",
    timestamp: "2024-01-01T00:00:00.000Z",
  },
};

// Helper functions
global.testHelpers = {
  delay: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),

  createMockRequest: (body = {}) => ({
    body,
    params: {},
    query: {},
  }),

  createMockResponse: () => {
    const res = {};
    res.status = jest.fn().mockReturnValue(res);
    res.json = jest.fn().mockReturnValue(res);
    res.send = jest.fn().mockReturnValue(res);
    return res;
  },
};
