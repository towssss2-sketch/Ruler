module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['<rootDir>/test/database/**/*.integration.ts'],
  testTimeout: 20000,
  verbose: true,
};
