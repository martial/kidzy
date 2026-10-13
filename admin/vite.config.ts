import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

// The admin is served by the Go binary at /admin/; in dev, Vite proxies the API to it.
export default defineConfig({
  plugins: [react()],
  base: '/admin/',
  build: { outDir: '../server/internal/web/dist', emptyOutDir: true },
  // Semantic UI's CSS has one invalid selector; lightningcss must skip it instead of failing.
  css: { lightningcss: { errorRecovery: true } },
  server: { proxy: { '/api': 'http://127.0.0.1:8800' } },
  test: { environment: 'node' },
})
