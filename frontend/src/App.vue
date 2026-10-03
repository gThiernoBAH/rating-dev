<!-- 2026-10-02 PATCH2 — layout sidebar EVALPOINT : nav a gauche, matricule - nom
     court + deconnexion en bas, onglets centrees dans la zone contenu. -->
<script setup>
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Bell, LogOut } from 'lucide-vue-next'
import api from './api/client'
import { useAuth } from './stores/auth'

const auth = useAuth()
const router = useRouter()
const route = useRoute()
const nonLues = ref(0)

async function refreshNonLues() {
  if (!auth.isConnected) return
  try { nonLues.value = (await api.get('/notifications/non-lues')).data.non_lues } catch { /* silencieux */ }
}

onMounted(async () => {
  if (auth.isConnected) {
    try { await auth.fetchMe() } catch { auth.logout() }
    refreshNonLues()
  }
})

const liens = computed(() => {
  const l = [{ to: '/', label: 'MON ESPACE' }]
  l.push({ to: '/navigation', label: 'NAVIGATION' })
  if (auth.estN1 || auth.estN2 || auth.isAdmin) {
    const camp = localStorage.getItem('campagneActive')
    if (camp) l.push({ to: '/evaluations/' + camp, label: 'EVALUATIONS' })
  }
  if (auth.isAdmin) {
    l.push({ to: '/referentiel', label: 'PARAMETRAGE' })
    l.push({ to: '/campagnes', label: 'CAMPAGNES' })
    l.push({ to: '/dashboard', label: 'TABLEAUX DE BORD' })
  }
  return l
})

const identite = computed(() => {
  const me = auth.me
  if (!me) return ''
  if (me.is_admin) return me.nom || 'Admin'
  return (me.matricule || '') + ' — ' + ((me.nom || '').split(' ')[0])
})

function deconnexion() {
  auth.logout()
  router.push('/login')
}
</script>

<template>
  <div class="app">
    <aside class="sidebar" v-if="auth.isConnected">
      <div class="brand">
        <svg class="logo" viewBox="0 0 32 32" width="30" height="30">
          <circle cx="16" cy="16" r="13" fill="none" stroke="#7cc4ff" stroke-width="2.5"/>
          <circle cx="16" cy="16" r="7" fill="none" stroke="#ffffff" stroke-width="2.5"/>
          <circle cx="16" cy="16" r="2.4" fill="#ffd166"/>
        </svg>
        <span class="brand-name">EVALPOINT</span>
      </div>
      <nav class="nav">
        <router-link v-for="l in liens" :key="l.to" :to="l.to" class="nav-item"
          :class="{ active: route.path === l.to }">{{ l.label }}</router-link>
      </nav>
      <div class="sidebar-bottom">
        <span class="notif"><Bell :size="16" /><span v-if="nonLues" class="badge">{{ nonLues }}</span></span>
        <span class="user" :title="auth.me?.nom">{{ identite }}</span>
        <button class="btn-logout" @click="deconnexion"><LogOut :size="14" /> DECONNEXION</button>
      </div>
    </aside>
    <main :class="{ padded: auth.isConnected }">
      <router-view @notif="refreshNonLues" />
    </main>
  </div>
</template>

<style>
* { box-sizing: border-box; margin: 0; }
body { font-family: 'Segoe UI', Arial, sans-serif; background: #f4f6f9; color: #1f2937; }
.app { display: flex; min-height: 100vh; }
.sidebar { width: 230px; background: #0f3b66; color: #fff; display: flex; flex-direction: column;
  position: sticky; top: 0; height: 100vh; }
.brand { display: flex; align-items: center; gap: 10px; padding: 18px 16px; border-bottom: 1px solid #1d4e85; }
.brand-name { font-weight: 700; letter-spacing: 1.5px; font-size: 16px; }
.nav { flex: 1; padding: 12px 10px; display: flex; flex-direction: column; gap: 2px; }
.nav-item { color: #cbd5e1; text-decoration: none; font-size: 12.5px; font-weight: 600;
  padding: 10px 12px; border-radius: 5px; letter-spacing: .3px; }
.nav-item.active, .nav-item:hover { color: #fff; background: #1d4e85; }
.sidebar-bottom { padding: 14px 16px; border-top: 1px solid #1d4e85; display: flex;
  flex-direction: column; gap: 10px; font-size: 12.5px; }
.notif { position: relative; cursor: pointer; display: flex; align-items: center; gap: 6px; }
.badge { background: #e11d48; border-radius: 8px; font-size: 10px; padding: 1px 5px; }
.user { font-weight: 700; color: #fff; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.btn-logout { display: flex; align-items: center; gap: 6px; justify-content: center;
  background: none; border: 1px solid #4b6f95; color: #cbd5e1; border-radius: 5px;
  padding: 6px; cursor: pointer; font-size: 11.5px; }
.btn-logout:hover { background: #b91c1c; border-color: #b91c1c; color: #fff; }
.padded { flex: 1; padding: 20px; min-width: 0; }
table.data { width: 100%; border-collapse: collapse; background: #fff; font-size: 13px; }
table.data th { background: #e8eef5; text-align: left; padding: 8px; border-bottom: 2px solid #cbd5e1; font-size: 11px; }
table.data td { padding: 8px; border-bottom: 1px solid #e5e7eb; }
.btn { background: #0f3b66; color: #fff; border: none; border-radius: 4px; padding: 8px 14px; cursor: pointer; font-size: 13px; }
.btn.danger { background: #b91c1c; }
.btn.ghost { background: #fff; color: #0f3b66; border: 1px solid #0f3b66; }
.btn.small { padding: 4px 10px; font-size: 11.5px; }
.btn:disabled { opacity: .5; cursor: not-allowed; }
.tabs { display: flex; gap: 2px; margin: 12px 0; flex-wrap: wrap; justify-content: center; }
.tab { padding: 8px 16px; background: #e2e8f0; cursor: pointer; font-size: 12px; border-radius: 4px 4px 0 0; font-weight: 600; }
.tab.active { background: #0f3b66; color: #fff; }
.muted { color: #6b7280; }
.badge-warn { background: #fef3c7; color: #92400e; border-radius: 4px; padding: 2px 8px; font-size: 11px; }
.locked { color: #b45309; }
.modal-bg { position: fixed; inset: 0; background: rgba(0,0,0,.45); display: flex; align-items: center; justify-content: center; }
.modal { background: #fff; border-radius: 8px; padding: 24px; width: min(640px, 92vw); max-height: 86vh; overflow: auto; }
input, select, textarea { border: 1px solid #cbd5e1; border-radius: 4px; padding: 7px; font-size: 13px; width: 100%; }
.field { margin-bottom: 10px; }
label { font-size: 12px; font-weight: 600; display: block; margin-bottom: 4px; }
.error { background: #fee2e2; color: #991b1b; padding: 10px; border-radius: 4px; margin: 8px 0; font-size: 13px; }
.ok { background: #dcfce7; color: #166534; padding: 10px; border-radius: 4px; margin: 8px 0; font-size: 13px; }
.cell-locked { background: #f1f3f5; color: #9ca3af; }
.barre-outils { display: flex; justify-content: space-between; align-items: center; margin: 8px 0; }
.lignes-edit { border: 1px solid #e5e7eb; border-radius: 4px; padding: 8px; margin-bottom: 10px; }
.ligne-edit { display: flex; gap: 6px; align-items: center; margin-bottom: 6px; }
.ligne-edit input, .ligne-edit select { padding: 5px; }
</style>
