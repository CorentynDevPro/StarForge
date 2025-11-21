import express from 'express';
import { supabase } from '../lib/supabaseClient';
import { authenticate, requireService } from '../middleware/auth';
import { guildSyncService } from '../services';

const router = express.Router();

// Public: get guild by external id or uuid
router.get('/:id', async (req, res) => {
  try {
    const id = req.params.id;
    const { data, error } = await supabase
      .from('guilds')
      .select('*')
      .or(`external_id.eq.${id},id.eq.${id}`)
      .limit(1);
    if (error) return res.status(500).json({ error: error.message });
    if (!data || data.length === 0) return res.status(404).json({ error: 'Guild not found' });
    const guild = data[0];

    const { data: members } = await supabase.from('guild_members').select('*, app_users(email,username,display_name)').eq('guild_id', guild.id);
    return res.json({ guild, members });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// Enqueue sync job (service-only)
router.post('/:id/refresh-sheets', authenticate, requireService, async (req, res) => {
  const id = req.params.id;
  try {
    const payload = {
      guild_id: id,
      requested_by: req.auth?.isService ? 'service' : req.auth?.user?.id,
      sheet_id: req.body.sheet_id,
      range: req.body.range,
      force: !!req.body.force
    };
    const job = await guildSyncService.enqueueSync(payload);
    return res.json({ ok: true, job });
  } catch (err: any) {
    console.error('enqueueSync error', err);
    return res.status(500).json({ error: err.message || 'server_error' });
  }
});

export default router;
