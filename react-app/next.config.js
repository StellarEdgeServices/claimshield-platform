/** @type {import('next').NextConfig} */
// build-stamp: main 2026-05-07
// typescript.ignoreBuildErrors: true — TS cleanup tracked in ClickUp (see D-211 post-launch task)
const nextConfig = {
  reactStrictMode: true,
  typescript: { ignoreBuildErrors: true },
  eslint: { ignoreDuringBuilds: true },
};

module.exports = nextConfig;
