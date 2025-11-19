-- Seed data for development

-- Insert sample feature flags
INSERT INTO feature_flags (name, enabled, rollout_percentage) VALUES
  ('battle_simulator', true, 100),
  ('recommendations', true, 50),
  ('google_sheets_sync', false, 0),
  ('advanced_analytics', true, 100);

-- Insert sample guild
INSERT INTO guilds (discord_guild_id, name, settings, feature_flags) VALUES
  ('123456789012345678', 'Test Guild', 
   '{"timezone": "UTC", "weeklyResetDay": 1, "notificationsEnabled": true}'::jsonb,
   '{"battle_simulator": true, "recommendations": true}'::jsonb);
