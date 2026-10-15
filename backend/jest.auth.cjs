module.exports = {
  ...require('./jest.config.cjs'),
  testMatch: ['<rootDir>/test/**/*.spec.ts', '<rootDir>/test/auth/**/*.e2e.ts', '<rootDir>/test/case/**/*.e2e.ts', '<rootDir>/test/storage/**/*.e2e.ts', '<rootDir>/test/document/**/*.e2e.ts'],
  testTimeout: 30000,
  collectCoverage: true,
};
