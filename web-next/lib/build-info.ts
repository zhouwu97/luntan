export function webBuildInfo() {
  const commit =
    process.env.NEXT_PUBLIC_RELEASE_SHA ||
    process.env.NEXT_PUBLIC_GIT_SHA ||
    process.env.RELEASE_SHA ||
    process.env.GIT_SHA ||
    "dev";
  const buildTime =
    process.env.NEXT_PUBLIC_BUILD_TIME ||
    process.env.BUILD_TIME ||
    new Date().toISOString();
  return {
    version: "0.1.0",
    commit,
    build_time: buildTime,
  };
}
