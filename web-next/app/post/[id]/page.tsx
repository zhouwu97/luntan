import { PostDetailShell } from "../../../components/post-detail-shell";

export default async function PostPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <PostDetailShell id={decodeURIComponent(id)} />;
}
