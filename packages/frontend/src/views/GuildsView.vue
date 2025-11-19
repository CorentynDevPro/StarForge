<template>
  <div class="guilds">
    <h1>Guilds</h1>
    <p>This is a stub. Guild list will be fetched from the API.</p>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue';
import { useGuildStore } from '@/stores/guild';

const guildStore = useGuildStore();

onMounted(() => {
  guildStore.fetchGuilds();
});
</script>
