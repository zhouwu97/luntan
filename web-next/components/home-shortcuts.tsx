import Link from "next/link";
import { Icon, type IconName } from "./icons";

const shortcuts: Array<{ label: string; href: string; icon: IconName; tone: string }> = [
  { label: "玩具排行榜", href: "/ranking", icon: "trophy", tone: "blue" },
  { label: "热门帖子", href: "/?sort=hot", icon: "flame", tone: "orange" },
  { label: "穿搭分享", href: "/?topic=outfit", icon: "hanger", tone: "pink" },
  { label: "活动", href: "/activities", icon: "calendar", tone: "mint" },
];

export function HomeShortcuts() {
  return (
    <nav className="home-shortcuts" aria-label="快捷入口">
      {shortcuts.map((item) => <Link className="home-shortcut" href={item.href} key={item.label}><span className={`shortcut-icon ${item.tone}`}><Icon name={item.icon} size={19} /></span><span>{item.label}</span></Link>)}
    </nav>
  );
}

