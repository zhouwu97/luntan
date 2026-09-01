import type { SVGProps } from "react";

export type IconName =
  | "trophy"
  | "search"
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
  | "sparkle"
  | "user"
  | "image"
  | "at"
  | "arrow-up-right";

const paths: Record<IconName, React.ReactNode> = {
  trophy: <><path d="M8 4h8v4.5a4 4 0 0 1-8 0V4Z" /><path d="M8 6H5a2 2 0 0 0 2 3M16 6h3a2 2 0 0 1-2 3M12 13v4M9 20h6M10 17h4" /></>,
  search: <><circle cx="11" cy="11" r="6.5" /><path d="m16 16 4 4" /></>,
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
  sparkle: <path d="m12 3 1.5 5.5L19 10l-5.5 1.5L12 17l-1.5-5.5L5 10l5.5-1.5L12 3ZM19 15l.7 2.3L22 18l-2.3.7L19 21l-.7-2.3L16 18l2.3-.7L19 15Z" />,
  user: <><circle cx="12" cy="8" r="3.3" /><path d="M5.5 20a6.5 6.5 0 0 1 13 0" /></>,
  image: <><rect x="3.5" y="4.5" width="17" height="15" rx="2" /><circle cx="8.5" cy="9" r="1.5" /><path d="m4.5 17 4.3-4 3.1 2.7 2.4-2 5.7 4.6" /></>,
  at: <><circle cx="12" cy="12" r="7" /><path d="M15.5 12a3.5 3.5 0 1 1-1.1-2.5v5c0 1.7 3.6 1.9 3.6-2.5" /></>,
  "arrow-up-right": <><path d="M7 17 17 7M8 7h9v9" /></>,
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
