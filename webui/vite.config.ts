import tailwindcss from "@tailwindcss/vite";
import { defineConfig } from "vitest/config"
import { svelte } from '@sveltejs/vite-plugin-svelte'
import Icons from 'unplugin-icons/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [tailwindcss(), svelte(), Icons({
    compiler: 'svelte',
  }),
  ],
  build: {
    chunkSizeWarningLimit: 1500 // Set the limit to 1000 kB
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    css: true,
    include: ["src/**/*.test.ts", "src/**/*.test.svelte"],
    exclude: ["node_modules", "dist"]
  }
})
