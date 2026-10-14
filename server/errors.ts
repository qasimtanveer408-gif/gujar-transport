type DatabaseDiagnostic = {databaseCode?: string; operation?: string};
export class AppError extends Error {
 constructor(public status: number, public code: string, message: string, public diagnostic: DatabaseDiagnostic = {}) {super(message);}
}

export function dbError(error: {code?: string; message: string} | null, operation?: string) {
 if (!error) return;
 // Codes identify failures without disclosing SQL, credentials, or row values.
 const databaseCode = /^(?:[0-9A-Z]{5}|PGRST[0-9X]{3})$/.test(error.code ?? '') ? error.code : undefined;
 const diagnostic = {databaseCode, operation: operation && /^[a-z_]+$/.test(operation) ? operation : undefined};
 const fail = (status: number, code: string, message: string): never => {throw new AppError(status, code, message, diagnostic);};
 if (databaseCode === '42501') fail(403, 'FORBIDDEN', 'You do not have permission for this action.');
 if (databaseCode === '40001' || databaseCode === '23505') fail(409, 'CONFLICT', 'This record changed or already exists. Reload and try again.');
 if (databaseCode === '40P01' || databaseCode === '55P03') fail(409, 'DATABASE_BUSY', 'Another operation is using these records. Wait briefly, reload the preview, and try again.');
 if (databaseCode === '57014' || databaseCode === 'PGRST003') fail(504, 'DATABASE_TIMEOUT', 'The database operation timed out. Refresh the records to check their current state before trying again.');
 if (['PGRST200', 'PGRST202', 'PGRST203', 'PGRST204', 'PGRST205', '42P01', '42703', '42883'].includes(databaseCode ?? '')) {
  fail(503, 'DATABASE_SCHEMA_OUTDATED', 'The database schema or API cache does not match this app. Ask an administrator to apply the pending database update and reload the schema cache.');
 }
 if (databaseCode === '23503') fail(422, 'LINKED_RECORDS', 'Other records still reference this record. Reload the deletion preview and review the linked records.');
 if (databaseCode === '23502' || databaseCode === '23514' || databaseCode?.startsWith('22')) fail(422, 'INVALID_DATA', 'The values or linked records are not valid.');
 if (databaseCode === 'P0001') fail(422, 'RULE_VIOLATION', error.message.slice(0, 200));
 if (!databaseCode || databaseCode.startsWith('08') || ['PGRST000', 'PGRST001', 'PGRST002', '53300', '57P01', '57P02', '57P03'].includes(databaseCode)) {
  fail(503, 'DATABASE_UNAVAILABLE', 'The data service is temporarily unavailable. Refresh the records before trying again.');
 }
 fail(500, 'DATABASE_ERROR', `The database could not complete this operation (code ${databaseCode}). Ask an administrator to check the database logs.`);
}
