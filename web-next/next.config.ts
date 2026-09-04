import type { NextConfig } from "next";

const basePath = process.env.NEXT_PUBLIC_APP_BASE_PATH?.trim() || "";

const nextConfig: NextConfig = {
  basePath,
  output: process.env.OUTPUT_STANDALONE === "true" ? "standalone" : undefined,
  reactStrictMode: true,
};

export default nextConfig;
