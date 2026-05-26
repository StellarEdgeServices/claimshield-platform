import * as Sentry from "@sentry/nextjs";

Sentry.init({
  dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
  environment: "react-app",

  // Capture 100% of transactions in development; tune down in production
  tracesSampleRate: 1.0,

  // Error-context-only replay per D-233: no ambient recording, capture on error only
  replaysSessionSampleRate: 0,
  replaysOnErrorSampleRate: 1.0,

  // Only run in browser
  integrations: [
    Sentry.replayIntegration({ maskAllInputs: true }),
  ],

  debug: false,
});
