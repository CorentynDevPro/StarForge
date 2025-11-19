import { createRouter, createWebHistory } from 'vue-router';
import HomeView from '../views/HomeView.vue';
import GuildsView from '../views/GuildsView.vue';
import BattleSimView from '../views/BattleSimView.vue';
import AnalyticsView from '../views/AnalyticsView.vue';

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'home',
      component: HomeView,
    },
    {
      path: '/guilds',
      name: 'guilds',
      component: GuildsView,
    },
    {
      path: '/battle-sim',
      name: 'battle-sim',
      component: BattleSimView,
    },
    {
      path: '/analytics',
      name: 'analytics',
      component: AnalyticsView,
    },
  ],
});

export default router;
