import type { SVGProps } from "react";

export type IconName =
  | "trophy"
  | "home"
  | "search"
  | "mail"
  | "lock"
  | "eye-off"
  | "info"
  | "close"
  | "tag"
  | "copy"
  | "bell"
  | "plus"
  | "chevron-right"
  | "chevron-left"
  | "more"
  | "message"
  | "heart"
  | "bookmark"
  | "eye"
  | "filter"
  | "flame"
  | "box"
  | "calendar"
  | "hanger"
  | "sparkle"
  | "user"
  | "image"
  | "at"
  | "arrow-up-right"
  | "refresh";

const paths: Record<IconName, React.ReactNode> = {
  trophy: <><path d="M8 4h8v4.5a4 4 0 0 1-8 0V4Z" /><path d="M8 6H5a2 2 0 0 0 2 3M16 6h3a2 2 0 0 1-2 3M12 13v4M9 20h6M10 17h4" /></>,
  home: <><path d="m4 11 8-7 8 7" /><path d="M6.5 10v9.5h11V10M10 19.5v-5h4v5" /></>,
  search: <><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4 4" /></>,
  mail: <><rect x="3" y="5" width="18" height="14" rx="2" /><path d="m4 7 8 6 8-6" /></>,
  lock: <><rect x="5" y="10" width="14" height="11" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3" /></>,
  "eye-off": <><path d="m3 3 18 18" /><path d="M10.6 6.2A10.7 10.7 0 0 1 12 6c6.2 0 9.5 6 9.5 6a16.3 16.3 0 0 1-3.3 3.8M6.2 6.8C3.8 8.2 2.5 12 2.5 12s3.3 6 9.5 6c1.2 0 2.2-.2 3.1-.6" /><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" /></>,
  info: <><circle cx="12" cy="12" r="9" /><path d="M12 10.5v5M12 7.5h.01" /></>,
  close: <><path d="m6 6 12 12M18 6 6 18" /></>,
  tag: <><path d="M4 5.5V11l8 8 7-7-8-8H5.5A1.5 1.5 0 0 0 4 5.5Z" /><circle cx="8" cy="8" r="1" /></>,
  copy: <><rect x="8" y="8" width="11" height="11" rx="2" /><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" /></>,
  bell: <><path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9ZM10 21h4" /></>,
  plus: <><path d="M12 5v14M5 12h14" /></>,
  "chevron-right": <path d="m9 5 7 7-7 7" />,
  "chevron-left": <path d="m15 5-7 7 7 7" />,
  more: <><circle cx="5" cy="12" r="1" fill="currentColor" stroke="none" /><circle cx="12" cy="12" r="1" fill="currentColor" stroke="none" /><circle cx="19" cy="12" r="1" fill="currentColor" stroke="none" /></>,
  message: <path d="M20 11.5a7.5 7.5 0 0 1-8 7.5 8.8 8.8 0 0 1-3.4-.7L4 20l1.5-3.5A7.2 7.2 0 0 1 4 11.5 7.5 7.5 0 0 1 12 4a7.5 7.5 0 0 1 8 7.5Z" />,
  heart: <path d="M20.8 8.8c0 5.1-8.8 10.2-8.8 10.2S3.2 13.9 3.2 8.8A4.5 4.5 0 0 1 12 6.6a4.5 4.5 0 0 1 8.8 2.2Z" />,
  bookmark: <path d="M6 4.5A1.5 1.5 0 0 1 7.5 3h9A1.5 1.5 0 0 1 18 4.5V21l-6-3.5L6 21V4.5Z" />,
  eye: <><path d="M2.5 12s3.3-5 9.5-5 9.5 5 9.5 5-3.3 5-9.5 5-9.5-5-9.5-5Z" /><circle cx="12" cy="12" r="2.2" /></>,
  filter: <path d="M4 5h16l-6.2 7v5.2L10.2 19v-7L4 5Z" />,
  flame: <path d="M12.5 3.5c1.4 3.2-1 4.6-1 6.5 0 1.2.7 2 1.7 2.6 0-1.5 1-2.5 1.7-3.3 1.9 1.6 3.1 3.7 3.1 6 0 3.8-2.7 6.2-6 6.2s-6-2.4-6-6.2c0-2.7 1.3-4.7 3.5-6.7-.1 2.4.5 3.4 1.4 4 .1-2.7 1.1-5.5 1.6-9.1Z" />,
  box: <><path d="m4 8 8-4 8 4-8 4-8-4Z" /><path d="M4 8v8l8 4 8-4V8M12 12v8" /></>,
  calendar: <><rect x="4" y="5.5" width="16" height="15" rx="2" /><path d="M8 3v5M16 3v5M4 10h16" /></>,
  hanger: <><path d="M12 5.5a2.5 2.5 0 1 1 2.3 3.5c-.8 0-1.3.4-1.7 1l-1.1 1.7L5 15.6c-.7.4-.4 1.4.4 1.4h13.2c.8 0 1.1-1 .4-1.4l-6.5-3.9" /></>,
  sparkle: <path d="m12 3 1.5 5.5L19 10l-5.5 1.5L12 17l-1.5-5.5L5 10l5.5-1.5L12 3ZM19 15l.7 2.3L22 18l-2.3.7L19 21l-.7-2.3L16 18l2.3-.7L19 15Z" />,
  user: <><circle cx="12" cy="8" r="3.3" /><path d="M5.5 20a6.5 6.5 0 0 1 13 0" /></>,
  image: <><rect x="3.5" y="4.5" width="17" height="15" rx="2" /><circle cx="8.5" cy="9" r="1.5" /><path d="m4.5 17 4.3-4 3.1 2.7 2.4-2 5.7 4.6" /></>,
  at: <><circle cx="12" cy="12" r="7" /><path d="M15.5 12a3.5 3.5 0 1 1-1.1-2.5v5c0 1.7 3.6 1.9 3.6-2.5" /></>,
  "arrow-up-right": <><path d="M7 17 17 7M8 7h9v9" /></>,
  refresh: <><path d="M20 11a8 8 0 0 0-14.8-3.8L4 9" /><path d="M4 4v5h5M4 13a8 8 0 0 0 14.8 3.8L20 15" /><path d="M20 20v-5h-5" /></>,
};

export function Icon({ name, size = 20, strokeWidth = 1.8, ...props }: SVGProps<SVGSVGElement> & { name: IconName; size?: number; strokeWidth?: number }) {
  return (
    <svg
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
      {...props}
    >
      {paths[name]}
    </svg>
  );
}
