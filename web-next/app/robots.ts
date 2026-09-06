import type { MetadataRoute } from "next";
import { publicSiteUrl } from "../lib/public-site";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/", disallow: ["/admin/", "/api/", "/me", "/points"] },
    sitemap: publicSiteUrl("/sitemap.xml"),
  };
}
