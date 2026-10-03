<!-- 2026-10-02 PATCH2 — M1 : connexion EVALPOINT, matricule + mot de passe. -->
<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useAuth } from '../stores/auth'

const auth = useAuth()
const router = useRouter()
const matricule = ref('')
const password = ref('')
const erreur = ref('')
const chargement = ref(false)

async function seConnecter() {
  erreur.value = ''
  chargement.value = true
  try {
    await auth.login(matricule.value.trim(), password.value)
    router.push('/')
  } catch (e) {
    erreur.value = e.response?.data?.detail || 'Connexion impossible.'
  } finally { chargement.value = false }
}
</script>

<template>
  <div class="login-page">
    <form class="card" @submit.prevent="seConnecter">
      <div class="entete">
        <svg viewBox="0 0 32 32" width="44" height="44">
          <circle cx="16" cy="16" r="13" fill="none" stroke="#0f3b66" stroke-width="2.5"/>
          <circle cx="16" cy="16" r="7" fill="none" stroke="#0f3b66" stroke-width="2.5"/>
          <circle cx="16" cy="16" r="2.4" fill="#f59e0b"/>
        </svg>
        <div>
          <h1>EVALPOINT</h1>
          <p class="muted">Évaluation et notation du personnel</p>
        </div>
      </div>
      <div class="field"><label>MATRICULE</label><input v-model="matricule" autofocus /></div>
      <div class="field"><label>MOT DE PASSE</label><input type="password" v-model="password" /></div>
      <div v-if="erreur" class="error">{{ erreur }}</div>
      <button class="btn" type="submit" :disabled="chargement">SE CONNECTER</button>
    </form>
  </div>
</template>

<style scoped>
.login-page { display: flex; align-items: center; justify-content: center; min-height: 100vh; background: #0f3b66; }
.card { background: #fff; border-radius: 10px; padding: 40px; width: 380px; }
.entete { display: flex; align-items: center; gap: 14px; margin-bottom: 26px; }
h1 { color: #0f3b66; font-size: 22px; margin-bottom: 2px; letter-spacing: 1px; }
.card .muted { font-size: 12px; }
.btn { width: 100%; margin-top: 8px; }
</style>
