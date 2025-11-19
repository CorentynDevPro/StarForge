import { FeatureFlag } from '../types';

const featureFlags = new Map<string, FeatureFlag>();

export function initializeFeatureFlags(flags: FeatureFlag[]): void {
  flags.forEach((flag) => {
    featureFlags.set(flag.name, flag);
  });
}

export function isFeatureEnabled(featureName: string, guildId?: string, userId?: string): boolean {
  const flag = featureFlags.get(featureName);

  if (!flag) {
    return false;
  }

  if (!flag.enabled) {
    return false;
  }

  // Check guild-specific override
  if (guildId && flag.guildIds) {
    return flag.guildIds.includes(guildId);
  }

  // Check rollout percentage
  if (flag.rolloutPercentage !== undefined) {
    const hash = userId ? simpleHash(userId) : Math.random();
    return hash % 100 < flag.rolloutPercentage;
  }

  return true;
}

export function getFeatureFlag(featureName: string): FeatureFlag | undefined {
  return featureFlags.get(featureName);
}

export function getAllFeatureFlags(): FeatureFlag[] {
  return Array.from(featureFlags.values());
}

// Simple hash function for consistent rollout
function simpleHash(str: string): number {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = (hash << 5) - hash + char;
    hash = hash & hash;
  }
  return Math.abs(hash);
}
