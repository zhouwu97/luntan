import Link from "next/link";
import { SiteHeader } from "../../../components/site-header";
import { Icon } from "../../../components/icons";

export default async function UserPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <><SiteHeader /><main className="page-frame"><section className="coming-page"><span className="coming-icon"><Icon name="user" size={28} /></span><h1>个人主页</h1><p>用户 {decodeURIComponent(id)} 的内容页将在下一阶段开放。</p><Link href="/" className="primary-link">返回首页</Link></section></main></>;
}
