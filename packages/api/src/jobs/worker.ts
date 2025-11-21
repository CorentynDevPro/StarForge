import dotenv from 'dotenv';
import { Pool, PoolClient } from 'pg';
import { supabase } from '../lib/supabaseClient';

dotenv.config();

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL missing for worker');
  process.exit(1);
}

const pool = new Pool({ connectionString: DATABASE_URL, max: 5 });

// Fetch one job using SKIP LOCKED
async function fetchJob(client: PoolClient) {
  await client.query('BEGIN');
  const q = `
    SELECT id, type, payload
    FROM queue_jobs
    WHERE status = 'pending' AND (run_after IS NULL OR run_after <= now())
    ORDER BY priority ASC, created_at ASC
    FOR UPDATE SKIP LOCKED
    LIMIT 1;
  `;
  const res = await client.query(q);
  if (!res.rows || res.rows.length === 0) {
    await client.query('COMMIT');
    return null;
  }
  const job = res.rows[0];
  await client.query(
    'UPDATE queue_jobs SET status=$1, attempts=attempts+1, updated_at=now() WHERE id=$2',
    ['processing', job.id],
  );
  await client.query('COMMIT');
  return job;
}

// process job
async function processJob(job: any) {
  console.log('Processing job', job.id, job.type);
  try {
    if (job.type === 'sheets_sync') {
      const payload = job.payload;
      // TODO: Replace with real Google Sheets export logic
      await supabase.from('sheets_sync_logs').insert([
        {
          guild_id: payload.guild_id,
          sheet_id: payload.sheet_id || null,
          range: payload.range || null,
          rows_sent: 0,
          status: 'completed',
          started_at: new Date().toISOString(),
          finished_at: new Date().toISOString(),
        },
      ]);
    } else {
      console.warn('Unknown job type', job.type);
    }

    await pool.query('UPDATE queue_jobs SET status=$1, updated_at=now() WHERE id=$2', [
      'completed',
      job.id,
    ]);
  } catch (err: any) {
    console.error('Job processing error', err);
    await pool.query(
      'UPDATE queue_jobs SET status=$1, last_error=$2, updated_at=now() WHERE id=$3',
      ['failed', err.message || String(err), job.id],
    );
  }
}

async function loopOnce() {
  const client = await pool.connect();
  try {
    const job = await fetchJob(client);
    if (job) {
      await processJob(job);
    } else {
      await new Promise((r) => setTimeout(r, 2000));
    }
  } catch (err) {
    console.error('Worker loop error', err);
    await new Promise((r) => setTimeout(r, 2000));
  } finally {
    client.release();
  }
}

let keepRunning = true;

// Graceful shutdown
process.on('SIGINT', () => {
  console.log('Worker received SIGINT, shutting down...');
  keepRunning = false;
});
process.on('SIGTERM', () => {
  console.log('Worker received SIGTERM, shutting down...');
  keepRunning = false;
});

async function start() {
  console.log('Worker started');
  while (keepRunning) {
    try {
      await loopOnce();
    } catch (err) {
      console.error('Worker fatal', err);
      // Backoff on unexpected fatal error
      await new Promise((r) => setTimeout(r, 5000));
    }
  }

  console.log('Worker stopping, draining pool...');
  await pool.end();
  console.log('Worker stopped');
}

start().catch((e) => {
  console.error(e);
  process.exit(1);
});
