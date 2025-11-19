<template>
  <div id="admin-app">
    <h1>StarForge Admin Panel</h1>
    <nav>
      <button>Users</button>
      <button>Guilds</button>
      <button>Feature Flags</button>
      <button>Audit Logs</button>
      <button>Mod Tools</button>
    </nav>
    <main>
      <p>Admin UI stub - RBAC and moderator tools will be implemented here</p>
    </main>
  </div>
</template>

<script setup lang="ts">
// Admin panel logic
</script>

<style scoped>
#admin-app {
  padding: 2rem;
}

nav {
  display: flex;
  gap: 1rem;
  margin: 2rem 0;
}

button {
  padding: 0.5rem 1rem;
  background: #2c3e50;
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
}

button:hover {
  background: #42b983;
}
</style>
