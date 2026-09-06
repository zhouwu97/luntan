import type { MetadataRoute } from "next";
import { getPublicRecentPosts } from "../lib/server-post";
import { publicSiteUrl } from "../lib/public-site";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const staticRoutes: MetadataRoute.Sitemap = [
    { url: publicSiteUrl("/"), changeFrequency: "daily", priority: 1 },
    { url: publicSiteUrl("/ranking"), changeFrequency: "daily", priority: 0.7 },
    { url: publicSiteUrl("/communities"), changeFrequency: "weekly", priority: 0.6 },
    { url: publicSiteUrl("/activities"), changeFrequency: "weekly", priority: 0.5 },
  ];
  const posts = await getPublicRecentPosts();
  const postRoutes = posts.map((post) => ({
    url: publicSiteUrl(`/post/${encodeURIComponent(post.id)}`),
    lastModified: post.updatedAt || post.publishedAt || post.createdAt || undefined,
    changeFrequency: "weekly" as const,
    priority: 0.6,
  }));
  return [...staticRoutes, ...postRoutes];
}
