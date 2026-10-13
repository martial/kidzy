import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

// The admin is served by the Go binary at /admin/; in dev, Vite proxies the API to it.
export default defineConfig({
  plugins: [react()],
  base: '/admin/',
  // preserveSymlinks: a source plugin linked into src/sources/ imports ../../api relative to the link
  resolve: { preserveSymlinks: true },
  build: { outDir: '../server/internal/web/dist', emptyOutDir: false },
  // Semantic UI's CSS has one invalid selector; lightningcss must skip it instead of failing.
  css: { lightningcss: { errorRecovery: true } },
  // fs.allow: a source plugin linked into src/sources/ lives outside admin/
  server: { proxy: { '/api': 'http://127.0.0.1:8800' }, fs: { allow: ['..', '../../..'] } },
  test: { environment: 'node' },
})
