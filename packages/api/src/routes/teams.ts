import express from 'express';
import { supabase } from '../lib/supabaseClient';
import { authenticate } from '../middleware/auth';

const router = express.Router();

// Save a team (authenticated)
router.post('/', authenticate, async (req, res) => {
  try {
    if (!req.auth || !req.auth.user) return res.status(403).json({ error: 'Authentication required' });
    const payload = req.body;
    const heroId = payload.hero_id;
    if (!heroId) return res.status(400).json({ error: 'hero_id required' });

    const row = {
      hero_id: heroId,
      name: payload.name || 'saved-team',
      description: payload.description || null,
      data: payload.data || {},
      is_public: !!payload.is_public
    };

    const { data, error } = await supabase.from('team_saves').insert([row]).select().limit(1);
    if (error) return res.status(500).json({ error: error.message });
    return res.status(201).json({ team: data?.[0] });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
