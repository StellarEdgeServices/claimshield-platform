import type { Metadata } from "next";
import "./globals.css";
import { SentryInitializer } from "./components/SentryInitializer";

export const metadata: Metadata = {
  title: "OtterQuote App",
  description: "OtterQuote — D-211 React app surface",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <SentryInitializer />
        {children}
      </body>
    </html>
  );
}
