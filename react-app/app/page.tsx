"use client";

import * as Sentry from "@sentry/nextjs";

export default function Home() {
  function throwTestError() {
    Sentry.captureException(new Error("[D-211-SENTRY-TEST] OtterQuote React app Sentry instrumentation verified"));
  }

  return (
    <main style={{ padding: "2rem" }}>
      <h1 style={{ fontSize: "2rem", fontWeight: "bold", marginBottom: "1rem" }}>
        OtterQuote App
      </h1>
      <p style={{ fontSize: "1rem", marginBottom: "1rem" }}>
        D-211 scaffold — Phase 0 in progress
      </p>
      <p style={{ fontSize: "0.875rem", color: "var(--slate)", marginBottom: "2rem" }}>
        Next.js 15 + React 19 + TypeScript + Tailwind CSS
      </p>
      {/* SENTRY-TEST: remove after verification — task 86e17u1w9 */}
      <button
        onClick={throwTestError}
        style={{
          padding: "0.5rem 1rem",
          background: "#e11d48",
          color: "white",
          border: "none",
          borderRadius: "4px",
          cursor: "pointer",
          fontSize: "0.875rem",
        }}
      >
        Send Sentry test error
      </button>
    </main>
  );
}
