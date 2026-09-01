import Link from "next/link";
import { SiteHeader } from "../../components/site-header";
import { Icon } from "../../components/icons";

export default function NotificationsPage() {
  return <><SiteHeader /><main className="page-frame"><section className="coming-page"><span className="coming-icon"><Icon name="bell" size={26} /></span><h1>通知中心正在整理中</h1><p>帖子流和评论提醒会在这里集中出现。</p><Link href="/" className="primary-link">返回首页</Link></section></main></>;
}
