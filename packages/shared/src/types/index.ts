// User and Authentication
export interface User {
  id: string;
  email: string;
  username: string;
  roles: Role[];
  guildId?: string;
  createdAt: Date;
  updatedAt: Date;
}

export type Role = 'admin' | 'guild_master' | 'moderator' | 'member';

// Guild Configuration
export interface GuildConfig {
  id: string;
  guildId: string;
  discordGuildId: string;
  name: string;
  settings: GuildSettings;
  featureFlags: Record<string, boolean>;
  createdAt: Date;
  updatedAt: Date;
}

export interface GuildSettings {
  timezone: string;
  weeklyResetDay: number;
  notificationsEnabled: boolean;
  autoReportEnabled: boolean;
  customFields: Record<string, unknown>;
}

// Analytics
export interface AnalyticsEvent {
  id: string;
  eventType: string;
  userId?: string;
  guildId?: string;
  metadata: Record<string, unknown>;
  timestamp: Date;
}

// Battle Simulation
export interface BattleTeam {
  troops: Troop[];
  hero?: Hero;
  class?: string;
}

export interface Troop {
  id: string;
  name: string;
  rarity: string;
  manaColors: string[];
  attack: number;
  armor: number;
  life: number;
  magic: number;
}

export interface Hero {
  level: number;
  class: string;
  weapon: string;
}

export interface BattleResult {
  winner: 'team1' | 'team2';
  turns: number;
  events: BattleEvent[];
}

export interface BattleEvent {
  turn: number;
  action: string;
  details: Record<string, unknown>;
}

// Audit Logs
export interface AuditLog {
  id: string;
  action: string;
  userId: string;
  guildId?: string;
  metadata: Record<string, unknown>;
  ipAddress?: string;
  userAgent?: string;
  timestamp: Date;
}

// Feature Flags
export interface FeatureFlag {
  name: string;
  enabled: boolean;
  rolloutPercentage?: number;
  guildIds?: string[];
}

// Job Scheduler
export interface ScheduledJob {
  id: string;
  name: string;
  schedule: string;
  payload: Record<string, unknown>;
  lastRun?: Date;
  nextRun: Date;
  enabled: boolean;
}

export interface QueueJob {
  id: string;
  type: string;
  payload: Record<string, unknown>;
  priority: number;
  attempts: number;
  maxAttempts: number;
  status: 'pending' | 'processing' | 'completed' | 'failed';
  createdAt: Date;
  processedAt?: Date;
}
