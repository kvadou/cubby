/// <reference types="vitest/config" />
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// The API is proxied so the app and API share an origin, which keeps the session cookie
// SameSite=Lax and lets the API's Sec-Fetch-Site check pass (docs/prior-art/2026-10-19-phase3-auth.md).
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    proxy: { "/api": { target: process.env.API_URL ?? "http://localhost:3000", changeOrigin: true } },
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test/setup.ts"],
  },
});
