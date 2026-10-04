// 2026-10-03 — point d'entree Vue 3 + Pinia + router + design tokens vusine.
import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import './style.css'

createApp(App).use(createPinia()).use(router).mount('#app')
