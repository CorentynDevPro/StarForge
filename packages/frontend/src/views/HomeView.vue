<template>
  <div class="home">
    <h1>Welcome to StarForge</h1>
    <p>Next-generation Gems of War community platform</p>
    <div class="features">
      <div class="feature-card">
        <h3>Guild Management</h3>
        <p>Track your guild's progress and manage members</p>
      </div>
      <div class="feature-card">
        <h3>Battle Simulator</h3>
        <p>Test team compositions and strategies</p>
      </div>
      <div class="feature-card">
        <h3>Analytics</h3>
        <p>View detailed statistics and insights</p>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { onMounted } from 'vue';
import { useAuthStore } from '@/stores/auth';

const authStore = useAuthStore();

onMounted(() => {
  authStore.loadAuth();
});
</script>

<style scoped>
.home {
  max-width: 1200px;
  margin: 0 auto;
}

h1 {
  font-size: 3rem;
  margin-bottom: 1rem;
}

.features {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
  gap: 2rem;
  margin-top: 3rem;
}

.feature-card {
  padding: 2rem;
  border: 1px solid #ddd;
  border-radius: 8px;
  background: #f9f9f9;
}

.feature-card h3 {
  margin-bottom: 0.5rem;
  color: #2c3e50;
}
</style>
