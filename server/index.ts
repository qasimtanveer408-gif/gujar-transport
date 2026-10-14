import {drainDeletionJobs} from './lifecycle.js';
import {privilegedClient} from './supabase.js';
import {readConfig} from './config.js';
import {createApp} from './app.js';

try {
  const config = readConfig();

  // Allow retained setup credentials for local development only.
  if (
    config.APP_ENV !== 'development' &&
    (config.ADMIN_PASSWORD || config.ADMIN_BOOTSTRAP_ENABLED)
  ) {
    throw new Error(
      'Remove ADMIN_PASSWORD and disable bootstrap before running a live environment.'
    );
  }

  const cleanupClient = privilegedClient(config);
  let cleaning = false;
  const cleanup = async () => { if (cleaning) return; cleaning = true; try { await drainDeletionJobs(cleanupClient); } finally { cleaning = false; } };
  const cleanupTimer = setInterval(() => { void cleanup(); }, 60_000);
  cleanupTimer.unref();
  void cleanup();
  const server = createApp(config).listen(
    config.PORT,
    '0.0.0.0',
    () => {
      console.info(
        `Gujjar Brother Transport API listening on port ${config.PORT} (${config.APP_ENV})`
      );
    }
  );

  for (const signal of ['SIGTERM', 'SIGINT']) {
    process.on(signal, () => {
      clearInterval(cleanupTimer);
      server.close(() => process.exit(0));
    });
  }
} catch (error) {
  console.error(
    error instanceof Error ? error.message : 'Startup failed'
  );
  process.exit(1);
}