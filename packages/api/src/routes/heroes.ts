import express from 'express';
import { supabase } from '../lib/supabaseClient';
import { authenticate } from '../middleware/auth';

const router = express.Router();

// GET /api/heroes?page=1&per=50
router.get('/', async (req, res) => {
  try {
    const page = Math.max(1, parseInt((req.query.page as string) || '1', 10));
    const per = Math.min(Math.max(1, parseInt((req.query.per as string) || '50', 10)), 200);
    const from = (page - 1) * per;
    const to = from + per - 1;

    const { data, error } = await supabase
      .from('heroes')
      .select('id, external_id, name, level, guild_name, created_at')
      .order('created_at', { ascending: false })
      .range(from, to);

    if (error) return res.status(500).json({ error: error.message });
    return res.json({ data });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// GET /api/heroes/:id (authenticated/service)
router.get('/:id', authenticate, async (req, res) => {
  try {
    const id = req.params.id;
    let { data, error } = await supabase.from('heroes').select('*').eq('external_id', id).limit(1);

    if ((!data || data.length === 0) && !error) {
      ({ data, error } = await supabase.from('heroes').select('*').eq('id', id).limit(1));
    }

    if (error) return res.status(500).json({ error: error.message });
    if (!data || data.length === 0) return res.status(404).json({ error: 'Hero not found' });

    const hero = data[0];
    const [{ data: troops }, { data: pets }] = await Promise.all([
      supabase.from('hero_troops').select('*').eq('hero_id', hero.id),
      supabase.from('hero_pets').select('*').eq('hero_id', hero.id),
    ]);

    return res.json({ hero, troops, pets });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
