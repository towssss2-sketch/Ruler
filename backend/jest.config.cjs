module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['<rootDir>/test/**/*.spec.ts'],
  collectCoverageFrom: ['src/**/*.ts', '!src/main.ts', '!src/app.module.ts'],
  coverageThreshold: { global: { branches: 80, functions: 80, lines: 80, statements: 80 } },
  coverageReporters: ['text', 'lcov'],
};
