import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: "react-app",

  // Capture 100% of transactions in development; tune down in production
  tracesSampleRate: 1.0,

  // Capture Replay for 10% of all sessions, 100% of sessions with errors
  replaysSessionSampleRate: 0.1,
  replaysOnErrorSampleRate: 1.0,

  // Only run in browser
  integrations: [
    Sentry.replayIntegration(),
  ],

  debug: false,
});
