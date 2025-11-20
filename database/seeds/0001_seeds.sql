-- Seed Data for StarForge Database
-- This file contains idempotent INSERT statements that can be run multiple times.
-- Uses ON CONFLICT DO NOTHING to ensure idempotence.

-- Insert sample feature flags
INSERT INTO feature_flags (name, enabled, rollout_percentage, guild_ids) VALUES
  ('battle_simulator', true, 100, '[]'::jsonb),
  ('recommendations', true, 50, '[]'::jsonb),
  ('google_sheets_sync', false, 0, '[]'::jsonb),
  ('advanced_analytics', true, 100, '[]'::jsonb)
ON CONFLICT (name) DO NOTHING;

-- Insert sample guild for development/testing
INSERT INTO guilds (discord_guild_id, name, settings, feature_flags) VALUES
  ('123456789012345678', 'Test Guild', 
   '{"timezone": "UTC", "weeklyResetDay": 1, "notificationsEnabled": true}'::jsonb,
   '{"battle_simulator": true, "recommendations": true}'::jsonb)
ON CONFLICT (discord_guild_id) DO NOTHING;
