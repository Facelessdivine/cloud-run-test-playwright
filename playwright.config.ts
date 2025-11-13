// playwright.config.ts
import { defineConfig, devices } from "@playwright/test";

export default defineConfig({
  testDir: "./tests",
  workers: 1, // 🔴 Important: one worker per Cloud Run instance
  outputDir: "test-results",

  // Keep the rest of the scaffold config as you like:
  fullyParallel: false,
  reporter: "list", // local dev; CI will override with --reporter
  use: {
    baseURL: "http://localhost:3000",
    trace: "on-first-retry",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
    },
  ],
});
