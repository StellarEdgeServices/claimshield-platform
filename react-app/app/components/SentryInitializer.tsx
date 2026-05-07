"use client";

import { useEffect } from "react";
import * as Sentry from "@sentry/nextjs";

export function SentryInitializer() {
  useEffect(() => {
    if (process.env.NEXT_PUBLIC_SENTRY_DSN) {
      Sentry.init({
        dsn: process.env.NEXT_PUBLIC_SENTRY_DSN,
        environment: "react-app",
        tracesSampleRate: 1.0,
        replaysSessionSampleRate: 0.1,
        replaysOnErrorSampleRate: 1.0,
        integrations: [Sentry.replayIntegration()],
        debug: false,
      });
    }
  }, []);

  return null;
}
