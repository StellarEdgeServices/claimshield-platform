/** @type {import('next').NextConfig} */
// build-stamp: main 2026-05-07
// D-211: typescript.ignoreBuildErrors removed — all TS errors resolved (wm-86e1b0dzh-a7c2)
const nextConfig = {
  reactStrictMode: true,
  eslint: { ignoreDuringBuilds: true },
};

module.exports = nextConfig;
