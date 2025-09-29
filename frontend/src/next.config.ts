import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: 'export',                // static HTML export (replaces `next export`)
  distDir: 'out',
  images: { unoptimized: true },   // disable Image Optimization for static export
  eslint: { ignoreDuringBuilds: true }
  // trailingSlash: true,          // optional: if you prefer `/about/` style
};

export default nextConfig;
