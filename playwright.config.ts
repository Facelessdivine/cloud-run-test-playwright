// playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",

  /* 🟢 CAMBIO 1: Activa fullyParallel */
  // Esto permite que Playwright divida tests de un mismo archivo entre diferentes shards.
  fullyParallel: true,

  /* 🔴 CAMBIO 2: Mantén workers en 1 */
  // Cloud Run asigna 1 o 2 CPUs por tarea; poner más workers saturaría la instancia.
  workers: 1,

  /* 🟡 CAMBIO 3: Reporter por defecto */
  // 'blob' es necesario para que el merge funcione después.
  // Tu script de bash ya lo pasa por comando (--reporter=blob),
  // pero dejarlo aquí ayuda a evitar confusiones.
  reporter: process.env.CI ? "blob" : "list",

  outputDir: "test-results",
  use: {
    /* 🔵 OPTIMIZACIÓN: Trace y Video */
    // En Cloud Run, el almacenamiento es efímero.
    // Captura traces solo si fallan para no inflar el tamaño de los blobs.
    trace: "on",
    video: "retain-on-failure",
    screenshot: "only-on-failure",

    // baseURL: process.env.BASE_URL || "http://localhost:3000",
  },

  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
