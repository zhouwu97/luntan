import React, { CSSProperties } from "react";

// Matches http(s):// or www. followed by domain and optional path/query/fragment.
// Stops before whitespace, HTML/XML delimiters, quotes, control characters, and non-ASCII (including Chinese).
const URL_REGEX = /(?:(?:https?:\/\/)|(?:www\.))([a-zA-Z0-9\-]+(?:\.[a-zA-Z0-9\-]+)*(?::\d+)?)(?:[/?#][a-zA-Z0-9\-._~:/?#[\]@!$&'*+,;%=]*)?/gi;

function trimTrailingPunctuation(url: string): string {
  let cleaned = url;
  while (cleaned.length > 0) {
    const last = cleaned[cleaned.length - 1];
    if (last === "." || last === "," || last === "!" || last === "?" || last === ";" || last === ":") {
      cleaned = cleaned.slice(0, -1);
    } else if (last === ")") {
      const openCount = (cleaned.match(/[(]/g) || []).length;
      const closeCount = (cleaned.match(/[)]/g) || []).length;
      if (closeCount > openCount) {
        cleaned = cleaned.slice(0, -1);
      } else {
        break;
      }
    } else if (last === "]" || last === "}") {
      cleaned = cleaned.slice(0, -1);
    } else {
      break;
    }
  }
  return cleaned;
}

export interface LinkSegment {
  type: "text" | "link";
  content: string;
  href?: string;
}

export function parseContentWithLinks(text: string): LinkSegment[] {
  if (!text) return [];
  const segments: LinkSegment[] = [];
  let lastIndex = 0;

  URL_REGEX.lastIndex = 0;
  let match: RegExpExecArray | null;

  while ((match = URL_REGEX.exec(text)) !== null) {
    const rawUrl = match[0];
    const startIndex = match.index;
    const cleanedUrl = trimTrailingPunctuation(rawUrl);

    if (!cleanedUrl) {
      continue;
    }

    const endIndex = startIndex + cleanedUrl.length;

    if (startIndex > lastIndex) {
      segments.push({
        type: "text",
        content: text.substring(lastIndex, startIndex),
      });
    }

    const href = cleanedUrl.toLowerCase().startsWith("www.") ? `https://${cleanedUrl}` : cleanedUrl;
    segments.push({
      type: "link",
      content: cleanedUrl,
      href,
    });

    lastIndex = endIndex;
    URL_REGEX.lastIndex = endIndex;
  }

  if (lastIndex < text.length) {
    segments.push({
      type: "text",
      content: text.substring(lastIndex),
    });
  }

  return segments;
}

export function LinkText({
  text,
  className,
  style,
  as: Component = "span",
}: {
  text: string;
  className?: string;
  style?: CSSProperties;
  as?: "span" | "p" | "div";
}) {
  if (!text) return null;

  const segments = parseContentWithLinks(text);

  return (
    <Component className={className} style={style}>
      {segments.map((seg, idx) => {
        if (seg.type === "link" && seg.href) {
          return (
            <a
              key={idx}
              href={seg.href}
              target="_blank"
              rel="noopener noreferrer"
              className="content-link"
              onClick={(e) => {
                e.stopPropagation();
              }}
            >
              {seg.content}
            </a>
          );
        }
        return <React.Fragment key={idx}>{seg.content}</React.Fragment>;
      })}
    </Component>
  );
}
