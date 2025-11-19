import { defineStore } from 'pinia';
import { ref } from 'vue';
import type { GuildConfig } from '@starforge/shared';

export const useGuildStore = defineStore('guild', () => {
  const guilds = ref<GuildConfig[]>([]);
  const currentGuild = ref<GuildConfig | null>(null);
  const loading = ref(false);

  async function fetchGuilds() {
    loading.value = true;
    try {
      // TODO: Fetch from API
      guilds.value = [];
    } catch (error) {
      console.error('Failed to fetch guilds:', error);
    } finally {
      loading.value = false;
    }
  }

  async function selectGuild(guildId: string) {
    const guild = guilds.value.find((g) => g.id === guildId);
    if (guild) {
      currentGuild.value = guild;
      localStorage.setItem('selected_guild', guildId);
    }
  }

  return { guilds, currentGuild, loading, fetchGuilds, selectGuild };
});
