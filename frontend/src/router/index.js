// 2026-10-02 — routes M1 à M8 + gardes (sections Evaluations selon le rôle).
import { createRouter, createWebHistory } from 'vue-router'
import { useAuth } from '../stores/auth'

const routes = [
  { path: '/login', name: 'login', component: () => import('../views/LoginView.vue') },
  { path: '/', name: 'espace', component: () => import('../views/EspaceView.vue') },
  { path: '/evaluations/:campagneId', name: 'evaluations', component: () => import('../views/EvaluationsView.vue') },
  { path: '/fiche/:evaluationId', name: 'fiche', component: () => import('../views/FicheEvaluationView.vue') },
  { path: '/notations/:evaluationId', name: 'notations', component: () => import('../views/NotationsView.vue') },
  { path: '/navigation', name: 'navigation', component: () => import('../views/NavigationView.vue') },
  { path: '/referentiel', name: 'referentiel', component: () => import('../views/ReferentielView.vue') },
  { path: '/campagnes', name: 'campagnes', component: () => import('../views/CampagnesView.vue') },
  { path: '/dashboard', name: 'dashboard', component: () => import('../views/DashboardView.vue') },
]

const router = createRouter({ history: createWebHistory(), routes })

router.beforeEach((to) => {
  const auth = useAuth()
  if (to.name !== 'login' && !auth.isConnected) return { name: 'login' }
  if (to.name === 'referentiel' || to.name === 'campagnes') {
    if (!auth.isAdmin) return { name: 'espace' }
  }
})

export default router
