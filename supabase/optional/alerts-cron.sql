-- Enable pg_cron in the confirmed live project first. One named job per project.
-- 04:05 UTC is 09:05 Asia/Karachi. Both app installations share this job.
select cron.schedule('gbt-alert-reconciliation','5 4 * * *',$$select public.server_reconcile_alerts();$$);
select jobid,jobname,schedule,active from cron.job where jobname='gbt-alert-reconciliation';
