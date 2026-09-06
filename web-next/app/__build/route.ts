import { NextResponse } from "next/server";
import { webBuildInfo } from "../../lib/build-info";

export const dynamic = "force-dynamic";

export async function GET() {
  const build = webBuildInfo();
  return NextResponse.json({
    status: "ok",
    web_sha: build.commit,
    ...build,
  });
}
