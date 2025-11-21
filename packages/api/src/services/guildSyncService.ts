import { supabase } from '../lib/supabaseClient';

export interface SheetsSyncPayload {
  guild_id: string;
  requested_by?: string;
  range?: string;
  sheet_id?: string;
  force?: boolean;
}

export class GuildSyncService {
  constructor() {}

  async enqueueSync(payload: SheetsSyncPayload) {
    const job = {
      type: 'sheets_sync',
      payload,
      priority: 100,
      status: 'pending',
    };
    const { data, error } = await supabase.from('queue_jobs').insert([job]).select().limit(1);
    if (error) throw error;
    return data?.[0];
  }

  async logSync(
    guildId: string,
    sheetId?: string,
    rowsSent?: number,
    status?: string,
    error?: any,
  ) {
    const row = {
      guild_id: guildId,
      sheet_id: sheetId ?? null,
      range: null,
      rows_sent: rowsSent ?? null,
      status: status ?? 'unknown',
      error: error ? JSON.stringify(error) : null,
      started_at: new Date().toISOString(),
      finished_at: new Date().toISOString(),
    };
    await supabase.from('sheets_sync_logs').insert([row]);
  }
}
