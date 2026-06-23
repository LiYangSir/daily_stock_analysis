import { readFileSync } from 'node:fs'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'
import path from 'path'

const packageJson = JSON.parse(
  readFileSync(new URL('./package.json', import.meta.url), 'utf-8'),
) as { version?: string }
const buildTime = new Date().toISOString()

const vendorChunkByPackage: Record<string, string> = {
  react: 'vendor-react',
  'react-dom': 'vendor-react',
  scheduler: 'vendor-react',
  'react-router': 'vendor-router',
  'react-router-dom': 'vendor-router',
  motion: 'vendor-motion',
  'framer-motion': 'vendor-motion',
  'motion-dom': 'vendor-motion',
  'motion-utils': 'vendor-motion',
  'lucide-react': 'vendor-icons',
  recharts: 'vendor-charts',
  'victory-vendor': 'vendor-charts',
  '@reduxjs/toolkit': 'vendor-charts',
  'decimal.js-light': 'vendor-charts',
  'es-toolkit': 'vendor-charts',
  eventemitter3: 'vendor-charts',
  immer: 'vendor-charts',
  'react-redux': 'vendor-charts',
  reselect: 'vendor-charts',
  'tiny-invariant': 'vendor-charts',
  'use-sync-external-store': 'vendor-charts',
  // Markdown renderer dependencies that are not covered by prefix rules below.
  'react-markdown': 'vendor-markdown',
  unified: 'vendor-markdown',
  vfile: 'vendor-markdown',
  'remove-markdown': 'vendor-markdown',
  bail: 'vendor-markdown',
  'comma-separated-tokens': 'vendor-markdown',
  'decode-named-character-reference': 'vendor-markdown',
  devlop: 'vendor-markdown',
  'html-url-attributes': 'vendor-markdown',
  'property-information': 'vendor-markdown',
  'space-separated-tokens': 'vendor-markdown',
  'trim-lines': 'vendor-markdown',
  'vfile-message': 'vendor-markdown',
}

const vendorChunkByPackagePrefix: Array<[string, string]> = [
  ['d3-', 'vendor-charts'],
  ['remark-', 'vendor-markdown'],
  ['micromark', 'vendor-markdown'],
  ['mdast-util-', 'vendor-markdown'],
  ['hast-util-', 'vendor-markdown'],
  ['unist-util-', 'vendor-markdown'],
]

const getVendorPackageName = (id: string): string | undefined => {
  const normalizedId = id.replace(/\\/g, '/')
  const marker = '/node_modules/'
  const markerIndex = normalizedId.lastIndexOf(marker)
  if (markerIndex === -1) {
    return undefined
  }

  const packagePath = normalizedId.slice(markerIndex + marker.length)
  const [firstSegment, secondSegment] = packagePath.split('/')
  if (!firstSegment) {
    return undefined
  }

  if (firstSegment.startsWith('@')) {
    return secondSegment ? `${firstSegment}/${secondSegment}` : undefined
  }

  return firstSegment
}

const getVendorChunkName = (id: string): string | undefined => {
  const packageName = getVendorPackageName(id)
  if (!packageName) {
    return undefined
  }

  return (
    vendorChunkByPackage[packageName]
    ?? vendorChunkByPackagePrefix.find(([prefix]) => packageName.startsWith(prefix))?.[1]
    ?? 'vendor'
  )
}

// https://vite.dev/config/
export default defineConfig({
  define: {
    __APP_PACKAGE_VERSION__: JSON.stringify(packageJson.version ?? '0.0.0'),
    __APP_BUILD_TIME__: JSON.stringify(buildTime),
  },
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  plugins: [
    tailwindcss(),
    react({
      babel: {
        plugins: [['babel-plugin-react-compiler']],
      },
    }),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg'],
      manifest: {
        name: 'Daily Stock Analysis',
        short_name: 'DSA',
        description: '股票智能分析工作台 — A 股 / 港股 / 美股自选股 + AI 决策报告。',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        background_color: '#0a0a0a',
        theme_color: '#0a0a0a',
        lang: 'zh-CN',
        icons: [
          {
            src: '/favicon.svg',
            sizes: 'any',
            type: 'image/svg+xml',
            purpose: 'any maskable',
          },
        ],
      },
      workbox: {
        navigateFallback: '/index.html',
        // Don't precache the giant stocks index — served at runtime.
        globIgnores: ['**/stocks.index.json'],
        // Allow vendor-charts (~3 MB before gzip) into the precache.
        maximumFileSizeToCacheInBytes: 5 * 1024 * 1024,
        runtimeCaching: [
          {
            // Live data must always go to the network so reports stay fresh.
            urlPattern: ({ url }) => url.pathname.startsWith('/api/'),
            handler: 'NetworkOnly',
          },
          {
            urlPattern: ({ request }) => request.destination === 'image',
            handler: 'StaleWhileRevalidate',
            options: {
              cacheName: 'dsa-images',
              expiration: { maxEntries: 64, maxAgeSeconds: 7 * 24 * 60 * 60 },
            },
          },
          {
            urlPattern: ({ url }) => url.origin === 'https://fonts.gstatic.com',
            handler: 'CacheFirst',
            options: {
              cacheName: 'dsa-google-fonts',
              expiration: { maxEntries: 16, maxAgeSeconds: 30 * 24 * 60 * 60 },
            },
          },
        ],
      },
      devOptions: {
        // Don't activate the SW in dev — it interferes with HMR.
        enabled: false,
      },
    }),
  ],
  server: {
    host: '0.0.0.0',  // 允许公网访问
    port: 5173,       // 默认端口
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8000',
        changeOrigin: true,
      },
    },
  },
  build: {
    // 打包输出到项目根目录的 static 文件夹
    outDir: path.resolve(__dirname, '../../static'),
    emptyOutDir: true,
    rollupOptions: {
      output: {
        manualChunks: getVendorChunkName,
      },
    },
  },
})
