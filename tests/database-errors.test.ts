import test from 'node:test';
import assert from 'node:assert/strict';
import {AppError, dbError} from '../server/errors.js';

test('database errors distinguish schema, timeout, contention, and unavailable service', () => {
 const cases: [string, number, string][] = [
  ['PGRST202', 503, 'DATABASE_SCHEMA_OUTDATED'], ['PGRST203', 503, 'DATABASE_SCHEMA_OUTDATED'],
  ['42P01', 503, 'DATABASE_SCHEMA_OUTDATED'], ['42703', 503, 'DATABASE_SCHEMA_OUTDATED'],
  ['42883', 503, 'DATABASE_SCHEMA_OUTDATED'], ['57014', 504, 'DATABASE_TIMEOUT'],
  ['PGRST003', 504, 'DATABASE_TIMEOUT'], ['40P01', 409, 'DATABASE_BUSY'],
  ['55P03', 409, 'DATABASE_BUSY'], ['08006', 503, 'DATABASE_UNAVAILABLE'],
  ['PGRST001', 503, 'DATABASE_UNAVAILABLE'], ['42501', 403, 'FORBIDDEN'],
  ['40001', 409, 'CONFLICT'], ['23503', 422, 'LINKED_RECORDS'],
  ['23502', 422, 'INVALID_DATA'], ['XX000', 500, 'DATABASE_ERROR'],
 ];
 for (const [code, status, appCode] of cases) {
  assert.throws(() => dbError({code, message: 'TEST private row values must not appear'}, 'record_lifecycle_action'), (error: unknown) => {
   assert.ok(error instanceof AppError);assert.equal(error.status, status);assert.equal(error.code, appCode);
   assert.equal(error.diagnostic.databaseCode, code);assert.equal(error.diagnostic.operation, 'record_lifecycle_action');
   assert.doesNotMatch(error.message, /private row values/);
   return true;
  });
 }
});

test('unknown provider failure never exposes arbitrary code/message as diagnostics', () => {
 assert.doesNotThrow(() => dbError(null));
 assert.throws(() => dbError({code: 'TEST-private-key-not-a-code', message: 'TEST password secret'}, 'unsafe operation input'), (error: unknown) => {
  assert.ok(error instanceof AppError);assert.equal(error.code, 'DATABASE_UNAVAILABLE');
  assert.equal(error.diagnostic.databaseCode, undefined);assert.equal(error.diagnostic.operation, undefined);
  assert.doesNotMatch(error.message, /password|private-key/);return true;
 });
});
