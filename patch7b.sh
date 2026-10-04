#!/usr/bin/env bash
# ============================================================================
# PATCH 7b — EVALPOINT (rating-dev) — 04/10/2026
# 1. Login copié À L'IDENTIQUE du Login.vue de vusine-dev (carte 400px,
#    champs/bouton 48px, icône 48px, placeholders) — seul le branding change.
#    Remplace la version « compacte » du patch 7 qui ne correspondait pas.
# 2. MOBILE (1er volet) — App.vue responsive : sidebar en tiroir (hamburger)
#    sous 768px, overlay de fermeture, paddings réduits.
#
# Usage : à la racine de rating-dev/ :
#   bash patch7b.sh
# ============================================================================
set -euo pipefail

if [ ! -d backend/app ] || [ ! -d frontend/src ]; then
  echo "ERREUR : lancez ce script depuis la racine de rating-dev/."
  exit 1
fi

for f in frontend/src/views/LoginView.vue frontend/src/App.vue; do
  cp "$f" "$f.bak-patch7b"
done

python3 - <<'PYEOF'
# -*- coding: utf-8 -*-
import re, sys, pathlib

def write_full(path, content):
    pathlib.Path(path).write_text(content, encoding="utf-8")
    print("  -", path)

# ---------------------------------------------------------------- LOGIN identique
LOGIN = '''<!-- 2026-10-04 PATCH 7b — M1 : copie conforme du Login.vue vusine-dev
     (carte 400px, champs/bouton 48px, placeholders, oeil afficher/masquer).
     Seule difference : branding EVALPOINT (cible a point dore) et champs
     Matricule. Conserve le parcours 1ere connexion (patch 6c). -->
<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { User, Lock, Eye, EyeOff } from 'lucide-vue-next'
import { useAuth } from '../stores/auth'
import api from '../api/client'

const auth = useAuth()
const router = useRouter()
const matricule = ref('')
const password = ref('')
const showPassword = ref(false)
const erreur = ref('')
const chargement = ref(false)
// 1re connexion : mot de passe jamais defini -> creation obligatoire
const premiereConnexion = ref(false)
const nouveauMdp = ref('')
const confirmationMdp = ref('')

async function definirMotDePasse() {
  erreur.value = ''
  if (nouveauMdp.value.trim().length < 6) {
    erreur.value = 'Le mot de passe doit contenir au moins 6 caracteres.'
    return
  }
  if (nouveauMdp.value !== confirmationMdp.value) {
    erreur.value = 'Les deux mots de passe ne correspondent pas.'
    return
  }
  chargement.value = true
  try {
    await api.post('/auth/definir-mot-de-passe', { nouveau: nouveauMdp.value.trim() })
    premiereConnexion.value = false
    nouveauMdp.value = ''
    confirmationMdp.value = ''
    await auth.fetchMe()
    router.push('/')
  } catch (e) {
    erreur.value = e.response?.data?.detail || 'Impossible de creer le mot de passe.'
  } finally { chargement.value = false }
}

async function seConnecter() {
  if (chargement.value) return
  erreur.value = ''
  chargement.value = true
  try {
    const rep = await auth.login(matricule.value.trim(), password.value)
    if (rep && rep.must_change_password) {
      premiereConnexion.value = true
      erreur.value = ''
      return
    }
    router.push('/')
  } catch (e) {
    erreur.value = e.response?.data?.detail || 'Connexion impossible.'
  } finally { chargement.value = false }
}
</script>

<template>
  <div class="login-page">
    <div v-if="!premiereConnexion" class="login-card">
      <div class="brand">
        <div class="brand-icon">
          <svg viewBox="0 0 32 32" width="28" height="28">
            <circle cx="16" cy="16" r="13" fill="none" stroke="currentColor" stroke-width="2.5"/>
            <circle cx="16" cy="16" r="7" fill="none" stroke="currentColor" stroke-width="2.5"/>
            <circle cx="16" cy="16" r="2.4" fill="#f59e0b"/>
          </svg>
        </div>
        <div>
          <div class="brand-name">EVALPOINT</div>
          <div class="brand-sub">SIVOP — Evaluation et notation du personnel</div>
        </div>
      </div>

      <form @submit.prevent="seConnecter" class="login-form">
        <label class="field">
          <span class="field-label">Matricule</span>
          <div class="input-group">
            <User :size="18" class="input-icon" />
            <input v-model="matricule" type="text" placeholder="Matricule" autofocus required />
          </div>
        </label>

        <label class="field">
          <span class="field-label">Mot de passe</span>
          <div class="input-group">
            <Lock :size="18" class="input-icon" />
            <input v-model="password" :type="showPassword ? 'text' : 'password'" placeholder="Mot de passe" required />
            <button type="button" class="toggle-pwd" @click="showPassword = !showPassword">
              <component :is="showPassword ? EyeOff : Eye" :size="18" />
            </button>
          </div>
        </label>

        <p v-if="erreur" class="error-message">{{ erreur }}</p>

        <button type="submit" class="submit-btn" :disabled="chargement">
          {{ chargement ? 'Connexion…' : 'Se connecter' }}
        </button>
      </form>
    </div>

    <!-- 1re connexion : creer SON mot de passe (min 6) -->
    <div v-if="premiereConnexion" class="login-card">
      <h2 class="mdp-titre">Creer votre mot de passe</h2>
      <p class="mdp-texte">Votre compte n'a pas encore de mot de passe.
        Choisissez-en un (6 caracteres minimum) — il vous servira a chaque connexion.</p>
      <form @submit.prevent="definirMotDePasse" class="login-form">
        <label class="field">
          <span class="field-label">Nouveau mot de passe</span>
          <div class="input-group">
            <Lock :size="18" class="input-icon" />
            <input :type="showPassword ? 'text' : 'password'" v-model="nouveauMdp"
              placeholder="6 caracteres minimum" autofocus />
          </div>
        </label>
        <label class="field">
          <span class="field-label">Confirmer le mot de passe</span>
          <div class="input-group">
            <Lock :size="18" class="input-icon" />
            <input :type="showPassword ? 'text' : 'password'" v-model="confirmationMdp"
              placeholder="Retapez le meme mot de passe" />
          </div>
        </label>
        <p v-if="erreur" class="error-message">{{ erreur }}</p>
        <button type="submit" class="submit-btn" :disabled="chargement">
          {{ chargement ? 'Creation…' : 'Creer mon mot de passe' }}
        </button>
      </form>
    </div>
  </div>
</template>

<style scoped>
.login-page {
  height: 100%;
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--color-bg);
  padding: var(--space-4);
}

.login-card {
  width: 100%;
  max-width: 400px;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  box-shadow: var(--shadow-card);
  padding: var(--space-8) var(--space-6);
}

.brand {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  margin-bottom: var(--space-8);
}

.brand-icon {
  width: 48px;
  height: 48px;
  border-radius: var(--radius-md);
  background: var(--color-brand);
  color: var(--color-text-inverse);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.brand-name {
  font-size: var(--font-size-lg);
  font-weight: 800;
  letter-spacing: 1px;
  color: var(--color-brand-dark);
}

.brand-sub {
  font-size: var(--font-size-sm);
  color: var(--color-text-muted);
}

.login-form {
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.field {
  display: flex;
  flex-direction: column;
  gap: var(--space-1);
}

.field-label {
  font-size: var(--font-size-sm);
  font-weight: 600;
  color: var(--color-text-muted);
}

.input-group {
  position: relative;
  display: flex;
  align-items: center;
}

.input-icon {
  position: absolute;
  left: 14px;
  color: var(--color-text-muted);
  pointer-events: none;
}

.input-group input {
  width: 100%;
  height: var(--touch-target-min);
  padding: 0 var(--space-3) 0 44px;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-md);
  font-size: var(--font-size-base);
  color: var(--color-text);
  background: var(--color-surface);
  outline: none;
  transition: border-color 0.15s;
}

.input-group input:focus {
  border-color: var(--color-brand);
}

.toggle-pwd {
  position: absolute;
  right: 12px;
  background: none;
  border: none;
  color: var(--color-text-muted);
  cursor: pointer;
  display: flex;
  padding: var(--space-1);
}

.error-message {
  color: var(--color-rouge);
  font-size: var(--font-size-sm);
  margin: 0;
}

.submit-btn {
  height: var(--touch-target-min);
  border: none;
  border-radius: var(--radius-md);
  background: var(--color-brand);
  color: var(--color-text-inverse);
  font-size: var(--font-size-base);
  font-weight: 700;
  cursor: pointer;
  transition: background 0.15s;
}

.submit-btn:hover:not(:disabled) {
  background: var(--color-brand-dark);
}

.submit-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.mdp-titre {
  margin: 0 0 var(--space-2);
  font-size: var(--font-size-lg);
  color: var(--color-brand-dark);
}
.mdp-texte {
  font-size: var(--font-size-sm);
  color: var(--color-text-muted);
  margin: 0 0 var(--space-6);
  line-height: 1.5;
}
</style>
'''
write_full("frontend/src/views/LoginView.vue", LOGIN)

# ------------------------------------------------- MOBILE : App.vue responsive
p = pathlib.Path("frontend/src/App.vue")
src = p.read_text(encoding="utf-8")

repls = [
    # import de l'icone Menu
    (r"import \{ LogOut, LayoutGrid, Compass, ClipboardList, Settings, CalendarCheck, BarChart3 \} from 'lucide-vue-next'",
     "import { LogOut, LayoutGrid, Compass, ClipboardList, Settings, CalendarCheck, BarChart3, Menu, X } from 'lucide-vue-next'"),
    # etat tiroir
    (r"const nonLues = ref\(0\)",
     "const nonLues = ref(0)\nconst menuOuvert = ref(false)\n\n// mobile : fermer le tiroir apres navigation\nfunction naviguer() { menuOuvert.value = false }"),
    # overlay + hamburger dans le template
    (r'  <div class="app">\n    <aside class="sidebar" v-if="showSidebar">',
     '''  <div class="app">
    <div v-if="menuOuvert && showSidebar" class="overlay" @click="menuOuvert = false"></div>
    <header v-if="showSidebar" class="topbar">
      <button class="hamburger" title="Ouvrir le menu" @click="menuOuvert = true">
        <Menu :size="22" />
      </button>
      <div class="topbar-brand">EVALPOINT</div>
    </header>
    <aside class="sidebar" v-if="showSidebar" :class="{ ouvert: menuOuvert }">'''),
    # fermeture du tiroir au clic sur un lien
    (r'<router-link v-for="l in liens" :key="l.to" :to="l.to" class="nav-item"\n          :class="\{ active: route.path === l.to \}" :title="l.label">',
     '<router-link v-for="l in liens" :key="l.to" :to="l.to" class="nav-item"\n          :class="{ active: route.path === l.to }" :title="l.label" @click="naviguer">'),
    # bouton fermer dans la sidebar (mobile)
    (r'''      <div class="sidebar-footer">''',
     '''      <button class="sidebar-close" title="Fermer le menu" @click="menuOuvert = false">
        <X :size="20" />
      </button>
      <div class="sidebar-footer">'''),
]
for pat, rep in repls:
    src, n = re.subn(pat, rep, src, count=1, flags=re.S)
    if n != 1:
        print(f"ERREUR : motif introuvable dans App.vue :\n  {pat[:80]}")
        sys.exit(1)

# styles responsive ajoutes a la fin du bloc <style>
MOBILE_CSS = '''
/* ---------- PATCH 7b : mobile ---------- */
.topbar { display: none; }
.hamburger, .sidebar-close { display: none; }

@media (max-width: 768px) {
  .app { flex-direction: column; }
  .topbar {
    display: flex; align-items: center; gap: var(--space-3);
    position: sticky; top: 0; z-index: 500;
    background: var(--color-surface);
    border-bottom: 1px solid var(--color-border);
    padding: var(--space-2) var(--space-4);
    min-height: 52px;
  }
  .hamburger {
    display: inline-flex; align-items: center; justify-content: center;
    width: 42px; height: 42px; border: 1px solid var(--color-border);
    border-radius: var(--radius-md); background: var(--color-surface);
    color: var(--color-text); cursor: pointer;
  }
  .topbar-brand { font-weight: 800; letter-spacing: 1px; color: var(--color-brand-dark); }
  .sidebar {
    position: fixed; left: 0; top: 0; bottom: 0;
    width: 250px; z-index: 1000;
    transform: translateX(-100%);
    transition: transform .2s ease;
    box-shadow: var(--shadow-card);
  }
  .sidebar.ouvert { transform: translateX(0); }
  .sidebar-close {
    display: inline-flex; align-items: center; justify-content: center;
    position: absolute; top: var(--space-3); right: var(--space-3);
    width: 36px; height: 36px; border: none; border-radius: var(--radius-md);
    background: var(--color-bg); color: var(--color-text-muted); cursor: pointer;
  }
  .overlay {
    position: fixed; inset: 0; background: rgba(15, 23, 42, .45);
    z-index: 900;
  }
  .main-area { padding: var(--space-3); width: 100%; }
}
'''
if not src.rstrip().endswith("</style>"):
    print("ERREUR : fin de App.vue inattendue (</style> attendu).")
    sys.exit(1)
src = src.rstrip()[: -len("</style>")] + MOBILE_CSS + "</style>\n"
p.write_text(src, encoding="utf-8")
print("  - frontend/src/App.vue")

print("OK")
PYEOF

echo ""
echo "✅ PATCH 7b appliqué."
echo "Login : compare a la capture vusine — doit etre identique (400px, 48px, placeholders)."
echo "Mobile : tester en mode responsive navigateur (<768px) — hamburger, tiroir, overlay."
echo "Sauvegardes : *.bak-patch7b."