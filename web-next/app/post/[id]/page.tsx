import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { PostDetailShell } from "../../../components/post-detail-shell";
import { getPublicPost } from "../../../lib/server-post";
import { publicSiteUrl } from "../../../lib/public-site";

type PostPageProps = { params: Promise<{ id: string }> };

function decodePostId(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function excerpt(value: string): string {
  const normalized = value.replace(/\s+/g, " ").trim();
  return normalized.length > 160 ? `${normalized.slice(0, 157)}…` : normalized;
}

export async function generateMetadata({ params }: PostPageProps): Promise<Metadata> {
  const { id } = await params;
  const postId = decodePostId(id);
  const result = await getPublicPost(postId);
  // 在元数据阶段立即终止响应，避免流式渲染先写出 200 后才进入 not-found 边界。
  if (result.status === "not_found") notFound();
  if (result.status === "unavailable") {
    return {
      title: "帖子暂时无法加载 - 圣杯酱",
      robots: { index: false, follow: false },
    };
  }
  const post = result.post;

  const canonical = publicSiteUrl(`/post/${encodeURIComponent(post.id)}`);
  const description = excerpt(post.content) || `${post.author.nickname} 发布于 ${post.community.name} 的分享`;
  const image = post.media[0]?.detailUrl || post.media[0]?.url || post.media[0]?.originalUrl;
  const images = image ? [publicSiteUrl(image)] : [publicSiteUrl("/apple-icon.png")];

  return {
    title: { absolute: `${post.title} - 圣杯酱` },
    description,
    alternates: { canonical },
    openGraph: {
      title: post.title,
      description,
      url: canonical,
      siteName: "圣杯酱",
      type: "article",
      publishedTime: post.publishedAt || post.createdAt || undefined,
      authors: [post.author.nickname],
      images,
    },
    twitter: {
      card: "summary_large_image",
      title: post.title,
      description,
      images,
    },
  };
}

export default async function PostPage({ params }: PostPageProps) {
  const { id } = await params;
  const postId = decodePostId(id);
  const result = await getPublicPost(postId);
  if (result.status === "not_found") notFound();
  const initialPost = result.status === "ok" ? result.post : null;
  return <PostDetailShell id={postId} initialPost={initialPost} />;
}
