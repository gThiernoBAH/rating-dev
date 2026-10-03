// 2026-10-02 — Vite : proxy /api -> 8003 (dev). Prod : nginx relaie /api/ -> 8103.
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5176,
    proxy: {
      '/api': { target: 'http://localhost:8003', changeOrigin: true },
    },
  },
})
