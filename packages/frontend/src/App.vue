<template>
  <div id="app">
    <nav>
      <RouterLink to="/">Home</RouterLink>
      <RouterLink to="/guilds">Guilds</RouterLink>
      <RouterLink to="/battle-sim">Battle Sim</RouterLink>
      <RouterLink to="/analytics">Analytics</RouterLink>
    </nav>
    <main>
      <RouterView />
    </main>
  </div>
</template>

<script setup lang="ts">
import { RouterLink, RouterView } from 'vue-router';
</script>

<style scoped>
nav {
  display: flex;
  gap: 1rem;
  padding: 1rem;
  background: #2c3e50;
}

nav a {
  color: white;
  text-decoration: none;
  padding: 0.5rem 1rem;
  border-radius: 4px;
}

nav a:hover,
nav a.router-link-active {
  background: #42b983;
}

main {
  padding: 2rem;
}
</style>
