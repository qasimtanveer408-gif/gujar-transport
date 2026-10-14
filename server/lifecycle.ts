import {Router} from 'express';
import {z} from 'zod';
import {lifecycleResources} from '../shared/lifecycle.js';
import type {AuthContext} from './session.js';
import type {Client} from './supabase.js';
import {AppError, dbError} from './errors.js';

const resource = z.string().refine(v => Object.hasOwn(lifecycleResources, v), 'Unknown record type');
const id = z.string().uuid();
const actionInput = z.object({
  action: z.enum(['archive', 'restore', 'delete']), version: z.number().int().positive(),
  reason: z.string().trim().min(3).max(300), token: z.string().length(32).nullable().optional(),
  confirmation: z.literal('DELETE').nullable().optional(),
}).strict();
type Job = {id: string; kind: 'storage' | 'auth'; payload: {bucket_id?: string; object_path?: string; user_id?: string}};

// Queue records are committed with the business deletion. Retries never restore
// deleted business data or directly modify Supabase's managed Storage/Auth tables.
export async function drainDeletionJobs(admin: Client): Promise<{pending: boolean}> {
  try {
    for (let batch = 0; batch < 5; batch++) {
      const jobs = await admin.rpc('server_deletion_jobs');
      if (jobs.error || !Array.isArray(jobs.data)) return {pending: true};
      if (!jobs.data.length) return {pending: false};
      let failed = false;
      for (const job of jobs.data as Job[]) {
        let error: {message: string; code?: string; status?: number} | null;
        if (job.kind === 'storage') {
          if (!job.payload.bucket_id || !job.payload.object_path) { failed = true; continue; }
          ({error} = await admin.storage.from(job.payload.bucket_id).remove([job.payload.object_path]));
        } else {
          if (!job.payload.user_id) { failed = true; continue; }
          ({error} = await admin.auth.admin.deleteUser(job.payload.user_id));
          // Idempotent retry after the provider succeeded but queue acknowledgment failed.
          if (error?.code === 'user_not_found' || error?.status === 404) error = null;
        }
        if (error) { failed = true; continue; }
        const finish = await admin.rpc('server_finish_deletion_job', {p_id: job.id});
        if (finish.error) failed = true;
      }
      if (failed) return {pending: true};
    }
    return {pending: true};
  } catch { return {pending: true}; }
}

export function lifecycleRouter(admin: Client) {
  const r = Router();
  r.use('/lifecycle', (_req, res, next) => {
    const a = res.locals.auth as AuthContext;
    if (!a.access.permissions.some(p => ['records.archive', 'records.delete'].includes(p)))
      throw new AppError(403, 'FORBIDDEN', 'Record management permission is required.');
    next();
  });
  r.post('/lifecycle/cleanup/retry', async (_req, res) => {
    if (!(res.locals.auth as AuthContext).access.permissions.includes('records.delete'))
      throw new AppError(403, 'FORBIDDEN', 'Permanent delete permission is required.');
    res.json(await drainDeletionJobs(admin));
  });
  r.get('/lifecycle/:resource', async (req, res) => {
    const q = z.object({state: z.enum(['active', 'archived', 'all']).default('active'),
      page: z.coerce.number().int().min(1).max(100000).default(1), search: z.string().max(100).default('')}).parse(req.query);
    const result = await (res.locals.auth as AuthContext).db.rpc('record_lifecycle_list', {
      p_resource: resource.parse(req.params.resource), p_state: q.state, p_page: q.page, p_search: q.search,
    });
<<<<<<< HEAD
    dbError(result.error, 'record_lifecycle_list'); res.json(result.data);
=======
    dbError(result.error); res.json(result.data);
>>>>>>> c44b1c5f20bc867d0d0ff98c100dd40351076c00
  });
  r.get('/lifecycle/:resource/:id', async (req, res) => {
    const result = await (res.locals.auth as AuthContext).db.rpc('record_lifecycle_preview', {
      p_resource: resource.parse(req.params.resource), p_id: id.parse(req.params.id),
    });
<<<<<<< HEAD
    dbError(result.error, 'record_lifecycle_preview'); res.json(result.data);
=======
    dbError(result.error); res.json(result.data);
>>>>>>> c44b1c5f20bc867d0d0ff98c100dd40351076c00
  });
  r.post('/lifecycle/:resource/:id', async (req, res) => {
    const q = actionInput.parse(req.body), a = res.locals.auth as AuthContext;
    if (!a.access.permissions.includes(q.action === 'delete' ? 'records.delete' : 'records.archive'))
      throw new AppError(403, 'FORBIDDEN', 'You do not have permission for this action.');
    if (q.action === 'delete' && (!q.token || q.confirmation !== 'DELETE'))
      throw new AppError(422, 'CONFIRM_REQUIRED', 'Review the deletion and type DELETE first.');
    const result = await a.db.rpc('record_lifecycle_action', {
      p_resource: resource.parse(req.params.resource), p_id: id.parse(req.params.id), p_action: q.action,
      p_version: q.version, p_reason: q.reason, p_token: q.token ?? null, p_confirmation: q.confirmation ?? null,
    });
<<<<<<< HEAD
    dbError(result.error, 'record_lifecycle_action');
=======
    dbError(result.error);
>>>>>>> c44b1c5f20bc867d0d0ff98c100dd40351076c00
    const cleanup = q.action === 'delete' ? await drainDeletionJobs(admin) : {pending: false};
    res.json({...result.data, cleanup_pending: cleanup.pending});
  });
  return r;
}
