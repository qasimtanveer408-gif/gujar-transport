import {createPortal} from 'react-dom';
import {useEffect, useState} from 'react';
import {api, ApiError} from './api';
import {Alert, Badge, Empty, Icon, Loading, Modal, Pagination, Table, type Row} from './components';
import {hasLifecycleAccess, lifecycleResources, type LifecycleAction, type LifecyclePreview} from '../../shared/lifecycle';

const relatedLabels: Record<string,string> = {
  app_users:'Users', app_sessions:'Sign-in sessions', user_roles:'Role assignments', role_permissions:'Role permissions',
  user_vehicle_scopes:'Vehicle access', accounting_periods:'Accounting periods', period_close_snapshots:'Period close snapshots',
  vehicle_driver_assignments:'Vehicle assignments', vehicle_financials:'Vehicle purchase values', driver_identity_details:'Driver identity details',
  trip_financials:'Trip fares', trip_expense_lines:'Trip expense lines', trip_status_history:'Trip status history',
  maintenance_records:'Maintenance records', maintenance_items:'Repair items', oil_changes:'Oil change details',
  office_bookings:'Bookings', driver_payment_allocations:'Payment allocations', settlement_allocations:'Cash allocations',
  custom_field_definitions:'Custom field definitions', custom_field_values:'Custom field values', idempotency_keys:'Transaction references',
  notification_reads:'Read notifications', attachments:'Documents', import_rows:'Imported rows',
};
const labelFor = (name: string) => relatedLabels[name] ?? name.replaceAll('_', ' ');
function lifecycleError(error: unknown): string {
  const message = error instanceof Error ? error.message : 'The operation could not be completed.';
  if (!(error instanceof ApiError)) return message;
  const {requestId, databaseCode} = error.details;
  return message + (databaseCode ? ` Database code: ${databaseCode}.` : '') + (requestId ? ` Reference: ${requestId}.` : '');
}
export function RecordLifecycle({resource, row, permissions, onChanged}: {
  resource: string; row: Row; permissions: string[]; onChanged: () => void;
}) {
  const [action, setAction] = useState<LifecycleAction | null>(null);
  const archived = Boolean(row.archived_at || row.archived || row.status === 'Archived' || row.employment_status === 'Archived');
  if (!hasLifecycleAccess(permissions)) return null;
  return <>
    {permissions.includes('records.archive') && <button type="button" className="button secondary small"
      onClick={() => setAction(archived ? 'restore' : 'archive')}><Icon name={archived ? 'arrow-counterclockwise' : 'archive'}/>{archived ? 'Restore' : 'Archive'}</button>}
    {permissions.includes('records.delete') && <button type="button" className="button danger small" onClick={() => setAction('delete')}><Icon name="trash3"/>Delete</button>}
    {action && createPortal(<LifecycleDialog resource={resource} id={String(row.id)} action={action} permissions={permissions}
      onClose={() => setAction(null)} onChanged={onChanged}/>, document.body)}
  </>;
}

export function LifecycleDialog({resource, id, action, permissions, onClose, onChanged}: {
  resource: string; id: string; action: LifecycleAction; permissions: string[]; onClose: () => void; onChanged: () => void;
}) {
  const [preview, setPreview] = useState<LifecyclePreview | null>(null), [reason, setReason] = useState('');
  const [confirmation, setConfirmation] = useState(''), [acknowledged, setAcknowledged] = useState(false);
  const [error, setError] = useState(''), [busy, setBusy] = useState(false), [finished, setFinished] = useState(false);
  const [cleanupPending, setCleanupPending] = useState(false);
  const path = `/lifecycle/${resource}/${id}`;
  useEffect(() => { let live = true; api<LifecyclePreview>(path).then(p => {if (live) setPreview(p);})
    .catch(e => {if (live) setError(lifecycleError(e));}); return () => {live = false;}; }, [path]);
  const needsArchive = action === 'delete' && preview && !preview.archived_at;
  const actual = needsArchive ? 'archive' : action;
  const title = action === 'delete' ? 'Delete permanently' : action === 'archive' ? 'Archive record' : 'Restore record';
  async function submit() {
    if (!preview || busy || error) return;
    setBusy(true); setError('');
    try {
      const result = await api<{cleanup_pending?: boolean}>(path, 'POST', {
        action: actual, version: preview.version, reason, token: actual === 'delete' ? preview.token : null,
        confirmation: actual === 'delete' ? confirmation : null,
      });
      if (needsArchive) {
        setPreview(null); setConfirmation(''); setAcknowledged(false);
        setPreview(await api<LifecyclePreview>(path));
      } else {
        setCleanupPending(Boolean(result.cleanup_pending)); setFinished(true);
      }
    } catch (e) {
      // A lost response may follow a committed transaction. Never automatically
      // retry a deletion or reuse an old preview after an uncertain outcome.
      setError(lifecycleError(e)); setPreview(null); setConfirmation(''); setAcknowledged(false);
    }
    finally { setBusy(false); }
  }
  const close = () => { if (!busy) { onClose(); onChanged(); window.dispatchEvent(new Event('gbt:changed')); } };
  return <Modal title={title} onClose={close}><form onSubmit={e => {e.preventDefault(); e.stopPropagation(); void submit();}}>
    <div className="dialog-body lifecycle-dialog"><Alert message={error}/>
      {finished ? <><Alert success message={action === 'delete' ? 'The record and confirmed linked database rows have been permanently deleted.' : action === 'archive' ? 'Record archived. You can restore or permanently delete it from Records & archives.' : 'Record restored.'}/>
        {cleanupPending && <p className="notice">File or sign-in account cleanup is pending. It retries automatically while the server is running; you can also use Retry cleanup in Records & archives.</p>}</>
        : !preview ? !error && <Loading/> : <>
          <p><strong>{preview.label}</strong></p><small className="muted lifecycle-id">Record ID: {preview.id}</small>
          {preview.protected && <Alert message="The built-in Super Admin role and the account you are currently signed into are protected. Use another administrator to remove an account."/>}
          {action === 'archive' || needsArchive ? <p>Archive this record first. Its saved values remain in the database. Use Records & archives to restore it or delete it permanently.</p> : action === 'restore' ? <p>Return this record to its active list. Linked parent records must be restored first.</p> : <>
            <p>This permanently removes the following database rows, including linked records and accounting entries. This cannot be undone.</p>
            <Table rows={preview.counts} columns={[{key: 'table', label: 'Records to remove', render: r => labelFor(String(r.table))}, {key: 'count', label: 'Count'}]}/>
            <p><strong>{preview.total} database rows</strong> in this deletion.</p>
            {resource === 'periods' && <p className="notice">Deleting this period removes its dated transactions and close snapshots. You can then create the period again without a date overlap.</p>}
            {preview.cross_period && <Alert message="Linked records extend outside this period. The complete linked documents and payments shown above will also be removed."/>}
            {preview.closed_periods.length > 0 && <p className="notice">Affected closed periods: {preview.closed_periods.join(', ')}. Surviving periods will reopen for review, and their old close snapshots will be cleared.</p>}
            {resource === 'users' && <p>Business records created by this user remain and are assigned to the administrator performing this deletion. The user's sign-in account is removed too.</p>}
            <label className="inline-check lifecycle-ack"><input type="checkbox" required checked={acknowledged} onChange={e => setAcknowledged(e.target.checked)}/>I reviewed the linked records and want to delete them.</label>
            <label>Type DELETE to confirm<input required autoComplete="off" value={confirmation} onChange={e => setConfirmation(e.target.value)} pattern="DELETE"/></label>
          </>}
          <label>Reason<textarea required minLength={3} maxLength={300} value={reason} onChange={e => setReason(e.target.value)}/></label>
          {needsArchive && !permissions.includes('records.archive') && <Alert message="Ask someone with archive permission to archive this record first."/>}
        </>}
      {error && !finished && <><p>Reload the preview before retrying. If the record is no longer found, close this dialog and refresh the list to check whether the operation completed.</p>
        <button type="button" className="button secondary small" disabled={busy} onClick={async () => {
          setBusy(true);
          try { setPreview(await api<LifecyclePreview>(path)); setConfirmation(''); setAcknowledged(false); setError(''); }
          catch (e) {setPreview(null); setError(lifecycleError(e));}
          finally {setBusy(false);}
        }}>Reload deletion preview</button></>}
    </div><footer><button type="button" className="button secondary" onClick={close} disabled={busy}>{finished ? 'Done' : 'Cancel'}</button>
      {!finished && <button className={'button ' + (actual === 'delete' ? 'danger' : 'primary')}
        disabled={busy || Boolean(error) || !preview || preview.protected || Boolean(needsArchive && !permissions.includes('records.archive')) || actual === 'delete' && (!acknowledged || confirmation !== 'DELETE')}>
        {busy ? 'Working…' : needsArchive ? 'Archive and continue' : title}</button>}
    </footer></form></Modal>;
}

export function RecordsArchivePage({permissions}: {permissions: string[]}) {
  const [resource, setResource] = useState('vehicles'), [state, setState] = useState('archived'), [search, setSearch] = useState('');
  const [page, setPage] = useState(1), [tick, setTick] = useState(0), [error, setError] = useState(''), [message, setMessage] = useState('');
  const [data, setData] = useState<{rows: Row[]; count: number} | null>(null), [busy, setBusy] = useState(false);
  const refresh = () => setTick(t => t + 1);
  useEffect(() => { let live = true; setData(null); const timer = setTimeout(() => {
    api<{rows: Row[]; count: number}>(`/lifecycle/${resource}?${new URLSearchParams({state, search, page: String(page)})}`)
      .then(r => {if (live) {setData(r); setError('');}}).catch(e => {if (live) setError(e.message);});
  }, 150); return () => {live = false; clearTimeout(timer);}; }, [resource, state, search, page, tick]);
  return <><div className="page-heading"><div><h1>Records & archives</h1><p>Archive, restore, or permanently delete records and review linked data.</p></div>
    {permissions.includes('records.delete') && <button className="button secondary" disabled={busy} onClick={async () => {
      setBusy(true); setError(''); try {const r = await api<{pending: boolean}>('/lifecycle/cleanup/retry', 'POST');
        setMessage(r.pending ? 'Some file or account cleanup is still pending. Retry shortly.' : 'File and account cleanup is complete.');
      } catch (e) {setError((e as Error).message);} finally {setBusy(false);}
    }}>Retry cleanup</button>}</div><Alert message={error}/><Alert message={message} success/>
    <div className="card"><div className="toolbar"><label>Record type<select value={resource} onChange={e => {setResource(e.target.value); setPage(1);}}>
      {Object.entries(lifecycleResources).map(([key, label]) => <option key={key} value={key}>{label}</option>)}</select></label>
      <label>Show<select value={state} onChange={e => {setState(e.target.value); setPage(1);}}><option value="active">Active</option><option value="archived">Archived</option><option value="all">All records</option></select></label>
      <label className="grow">Search<input maxLength={100} value={search} onChange={e => {setSearch(e.target.value); setPage(1);}}/></label></div>
      {!data ? !error && <Loading/> : data.rows.length ? <Table rows={data.rows} columns={[{key: 'label', label: 'Record'},
        {key: 'archived_at', label: 'Status', render: r => <Badge value={r.archived_at ? 'Archived' : 'Active'}/>}]} actions={r => <RecordLifecycle resource={resource} row={r} permissions={permissions} onChanged={refresh}/>}/>
        : <Empty title="No matching records" text="Choose another record type or show all records."/>}
      <Pagination page={page} count={data?.count ?? 0} onChange={setPage}/></div></>;
}
