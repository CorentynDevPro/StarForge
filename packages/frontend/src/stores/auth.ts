import { defineStore } from 'pinia';
import { ref } from 'vue';
import type { User } from '@starforge/shared';

export const useAuthStore = defineStore('auth', () => {
  const user = ref<User | null>(null);
  const token = ref<string | null>(null);

  function setAuth(userData: User, authToken: string) {
    user.value = userData;
    token.value = authToken;
    localStorage.setItem('auth_token', authToken);
  }

  function clearAuth() {
    user.value = null;
    token.value = null;
    localStorage.removeItem('auth_token');
  }

  function loadAuth() {
    const storedToken = localStorage.getItem('auth_token');
    if (storedToken) {
      token.value = storedToken;
      // TODO: Fetch user data with token
    }
  }

  return { user, token, setAuth, clearAuth, loadAuth };
});
