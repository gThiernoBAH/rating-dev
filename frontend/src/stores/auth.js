// 2026-10-02 — store d'authentification (matricule, rôles relationnels N/N+1/N+2).
import { defineStore } from 'pinia'
import api from '../api/client'

export const useAuth = defineStore('auth', {
  state: () => ({
    token: localStorage.getItem('token') || '',
    me: null,
  }),
  getters: {
    isConnected: (s) => !!s.token,
    isAdmin: (s) => !!(s.me && s.me.is_admin),
    estN1: (s) => !!(s.me && s.me.est_n1),
    estN2: (s) => !!(s.me && s.me.est_n2),
  },
  actions: {
    async login(matricule, password) {
      const { data } = await api.post('/auth/login', { matricule, password })
      this.token = data.access_token
      localStorage.setItem('token', data.access_token)
      await this.fetchMe()
    },
    async fetchMe() {
      const { data } = await api.get('/auth/me')
      this.me = data
    },
    logout() {
      this.token = ''
      this.me = null
      localStorage.removeItem('token')
    },
  },
})
