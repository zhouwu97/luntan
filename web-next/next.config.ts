import type { NextConfig } from "next";
import { execSync } from "child_process";

const basePath = process.env.NEXT_PUBLIC_APP_BASE_PATH?.trim() || "";

function getGitSha(): string {
  const envSha =
    process.env.NEXT_PUBLIC_GIT_SHA ||
    process.env.GIT_SHA ||
    process.env.RELEASE_SHA ||
    process.env.VERCEL_GIT_COMMIT_SHA;
  if (envSha?.trim()) return envSha.trim();
  try {
    return execSync("git rev-parse HEAD", { encoding: "utf8" }).trim();
  } catch {
    return "dev";
  }
}

const gitSha = getGitSha();
const buildTime = process.env.NEXT_PUBLIC_BUILD_TIME || new Date().toISOString();

const nextConfig: NextConfig = {
  basePath,
  output: process.env.OUTPUT_STANDALONE === "true" ? "standalone" : undefined,
  reactStrictMode: true,
  allowedDevOrigins: ["127.0.0.1", "localhost"],
  env: {
    NEXT_PUBLIC_GIT_SHA: gitSha,
    NEXT_PUBLIC_BUILD_TIME: buildTime,
  },
};

export default nextConfig;

