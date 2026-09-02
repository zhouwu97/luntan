import type { NextConfig } from "next";

const basePath = process.env.NEXT_PUBLIC_APP_BASE_PATH?.trim() || "";

const nextConfig: NextConfig = {
  basePath,
  output: "standalone",
  reactStrictMode: true,
};

export default nextConfig;
