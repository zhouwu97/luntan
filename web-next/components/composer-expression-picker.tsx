"use client";

import { useState } from "react";
import { stickerGroups, stickerUrl } from "../lib/sticker-catalog";

const emojis = ["😀", "😂", "😭", "🥹", "😊", "😍", "🥳", "🤔", "😮", "😡", "👍", "👎", "👏", "🙏", "💪", "❤️", "🔥", "🎉", "✨", "👀", "🤝", "✅", "❌", "💯"];

export function ComposerExpressionPicker({
  onEmoji,
  onSticker,
  stickerDisabled = false,
}: {
  onEmoji: (emoji: string) => void;
  onSticker: (stickerId: string) => void;
  stickerDisabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [tab, setTab] = useState<"emoji" | "sticker">("emoji");
  const [groupIndex, setGroupIndex] = useState(0);
  const group = stickerGroups[groupIndex] || stickerGroups[0];

  return (
    <div className="expression-picker-wrap">
      <button type="button" className="expression-trigger" aria-label="添加表情" aria-expanded={open} onClick={() => setOpen((value) => !value)}>
        ☺
      </button>
      {open && (
        <section className="expression-panel" aria-label="表情选择">
          <div className="expression-tabs">
            <button type="button" className={tab === "emoji" ? "active" : ""} onClick={() => setTab("emoji")}>Emoji</button>
            <button type="button" className={tab === "sticker" ? "active" : ""} onClick={() => setTab("sticker")}>表情包</button>
          </div>
          {tab === "emoji" ? (
            <div className="emoji-grid">
              {emojis.map((emoji) => <button type="button" key={emoji} aria-label={`插入 ${emoji}`} onClick={() => onEmoji(emoji)}>{emoji}</button>)}
            </div>
          ) : (
            <>
              <div className="sticker-groups">
                {stickerGroups.map((item, index) => <button type="button" key={item.id} className={index === groupIndex ? "active" : ""} onClick={() => setGroupIndex(index)}>{item.name}</button>)}
              </div>
              {stickerDisabled && <div className="expression-note">图片与表情包不能同时发送</div>}
              <div className="sticker-grid">
                {group.items.map((sticker) => (
                  <button type="button" key={sticker.id} aria-label={`选择表情包：${sticker.label}`} disabled={stickerDisabled} onClick={() => { onSticker(sticker.id); setOpen(false); }}>
                    <img src={stickerUrl(sticker.id)} alt={sticker.label} />
                  </button>
                ))}
              </div>
            </>
          )}
        </section>
      )}
    </div>
  );
}

export function CommentSticker({ stickerId, onClick }: { stickerId: string; onClick?: () => void }) {
  const url = stickerUrl(stickerId);
  if (!url) return null;
  return <img className="comment-sticker" src={url} alt="表情包" onClick={onClick} />;
}
