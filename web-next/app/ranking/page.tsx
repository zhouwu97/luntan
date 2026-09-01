import Link from "next/link";
import { SiteHeader } from "../../components/site-header";
import { Icon } from "../../components/icons";

export default function RankingPage() {
  return <><SiteHeader /><main className="page-frame"><section className="coming-page"><span className="coming-icon"><Icon name="trophy" size={28} /></span><h1>排行榜正在整理中</h1><p>先去首页看看大家最近分享的内容吧。</p><Link href="/" className="primary-link">返回首页</Link></section></main></>;
}
