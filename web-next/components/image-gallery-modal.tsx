"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { Icon } from "./icons";

export interface GalleryImage {
  url: string;
  alt?: string;
  originalUrl?: string;
  detailUrl?: string;
  thumbUrl?: string;
  sources?: string[];
}

function GalleryThumb({
  img,
  active,
  onClick,
  index,
}: {
  img: GalleryImage;
  active: boolean;
  onClick: () => void;
  index: number;
}) {
  const allThumbCandidates =
    img.sources && img.sources.length > 0
      ? [img.thumbUrl, ...img.sources].filter((s): s is string => Boolean(s && s.trim()))
      : ([img.thumbUrl, img.url, img.detailUrl, img.originalUrl].filter((s): s is string => Boolean(s && s.trim())));
  const previewThumbs = allThumbCandidates.filter((url) => url !== img.originalUrl);
  const thumbCandidates = previewThumbs.length ? previewThumbs : allThumbCandidates;
  const [thumbIdx, setThumbIdx] = useState(0);
  const src = thumbCandidates[thumbIdx] || (img.url ? img.url.trim() : "");
  const isThumbFailed = !src || thumbIdx >= thumbCandidates.length;

  return (
    <button
      type="button"
      className={`gallery-thumb-btn${active ? " active" : ""}`}
      onClick={onClick}
      aria-label={`查看第 ${index + 1} 张`}
    >
      {isThumbFailed ? (
        <span
          className="gallery-thumb-fallback"
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            width: "100%",
            height: "100%",
            background: "rgba(255, 255, 255, 0.1)",
            color: "rgba(255, 255, 255, 0.6)",
          }}
        >
          <Icon name="image" size={16} />
        </span>
      ) : (
        <img
          src={src}
          alt=""
          loading="lazy"
          decoding="async"
          onError={() => {
            if (thumbIdx + 1 < thumbCandidates.length) {
              setThumbIdx((i) => i + 1);
            } else {
              setThumbIdx(thumbCandidates.length);
            }
          }}
        />
      )}
    </button>
  );
}

export function ImageGalleryModal({
  images,
  initialIndex = 0,
  onClose,
}: {
  images: GalleryImage[];
  initialIndex?: number;
  onClose: () => void;
}) {
  const [currentIndex, setCurrentIndex] = useState(initialIndex);
  const [candidateIndex, setCandidateIndex] = useState(0);
  const [mounted, setMounted] = useState(false);
  const [retry, setRetry] = useState(0);
  const [original, setOriginal] = useState(false);
  const [scale, setScale] = useState(1);
  const [pan, setPan] = useState({ x: 0, y: 0 });
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const current = images[currentIndex] || images[0] || { url: "" };

  const rawPreviewCandidates =
    current.sources && current.sources.length > 0
      ? current.sources.filter((s): s is string => Boolean(s && s.trim()))
      : ([current.detailUrl, current.originalUrl, current.url, current.thumbUrl].filter((s): s is string => Boolean(s && s.trim())));
  const compressedCandidates = rawPreviewCandidates.filter((url) => url !== current.originalUrl);
  const previewCandidates = compressedCandidates.length ? compressedCandidates : rawPreviewCandidates;
  const candidates = original && current.originalUrl ? [current.originalUrl] : previewCandidates;
  const candidateKey = candidates.join("\n");
  useEffect(() => { if (scale === 1) setPan({ x: 0, y: 0 }); }, [scale]);

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    setCandidateIndex(0);
    setRetry(0);
    setOriginal(false);
    setScale(1);
    setPan({ x: 0, y: 0 });
    pointers.current.clear();
  }, [currentIndex]);

  useEffect(() => {
    const sources = candidateKey.split("\n").filter(Boolean);
    if (candidateIndex < sources.length || retry >= 5 || !sources.some((url) => url.includes("/api/v1/media-file/"))) return;
    const timer = window.setTimeout(() => { setCandidateIndex(0); setRetry((n) => n + 1); }, 1000 * (retry + 1));
    return () => window.clearTimeout(timer);
  }, [candidateKey, candidateIndex, retry]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        onClose();
      } else if (event.key === "ArrowLeft") {
        setCurrentIndex((idx) => (idx > 0 ? idx - 1 : images.length - 1));
      } else if (event.key === "ArrowRight") {
        setCurrentIndex((idx) => (idx < images.length - 1 ? idx + 1 : 0));
      }
    };

    const originalOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.body.style.overflow = originalOverflow;
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [images.length, onClose]);

  if (!mounted || !images.length) return null;
  const currentSrc = candidates[candidateIndex] || (current.url ? current.url.trim() : "");
  const isFailed = !currentSrc || candidateIndex >= candidates.length;

  const content = (
    <div
      className="gallery-modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-label="图片查看器"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="gallery-modal-header">
        <span className="gallery-counter">
          {currentIndex + 1} / {images.length}
        </span>
        <div className="gallery-actions">
          <button type="button" className="gallery-action-btn" aria-label="缩小图片" disabled={scale <= 1} onClick={() => { setScale((v) => Math.max(1, v - 0.5)); setPan({ x: 0, y: 0 }); }}>−</button>
          <button type="button" className="gallery-action-btn" aria-label="重置缩放" onClick={() => { setScale(1); setPan({ x: 0, y: 0 }); }}>{Math.round(scale * 100)}%</button>
          <button type="button" className="gallery-action-btn" aria-label="放大图片" disabled={scale >= 4} onClick={() => setScale((v) => Math.min(4, v + 0.5))}>+</button>
          {(current.originalUrl || (!isFailed && currentSrc)) && (
            <button type="button"
              onClick={() => { setOriginal((v) => !v); setCandidateIndex(0); setRetry(0); }}
              className="gallery-action-btn"
              title="查看原图"
              aria-label="查看原图"
            >
              <Icon name="arrow-up-right" size={17} />
              <span>{original ? "返回预览" : "原图"}</span>
            </button>
          )}
          <button
            type="button"
            className="gallery-action-btn close-btn"
            onClick={onClose}
            aria-label="关闭查看器"
          >
            <Icon name="close" size={20} />
          </button>
        </div>
      </div>

      <div
        className="gallery-stage"
        onClick={(e) => {
          if (e.target === e.currentTarget) onClose();
        }}
      >
        {images.length > 1 && (
          <button
            type="button"
            className="gallery-nav-btn prev-btn"
            aria-label="上一张"
            onClick={(e) => {
              e.stopPropagation();
              setCurrentIndex((idx) => (idx > 0 ? idx - 1 : images.length - 1));
            }}
          >
            <Icon name="chevron-left" size={28} />
          </button>
        )}

        <div className="gallery-image-container" style={{ overflow: "hidden", touchAction: "none" }}
          onDoubleClick={() => { setScale((v) => v > 1 ? 1 : 2); setPan({ x: 0, y: 0 }); }}
          onPointerDown={(e) => { if (!(e.target instanceof HTMLImageElement)) return; pointers.current.set(e.pointerId, { x: e.clientX, y: e.clientY }); e.currentTarget.setPointerCapture(e.pointerId); }}
          onPointerUp={(e) => pointers.current.delete(e.pointerId)}
          onPointerCancel={(e) => pointers.current.delete(e.pointerId)}
          onPointerMove={(e) => {
            const previous = pointers.current.get(e.pointerId);
            if (!previous) return;
            const next = { x: e.clientX, y: e.clientY };
            const other = [...pointers.current.entries()].find(([id]) => id !== e.pointerId)?.[1];
            if (other) {
              const before = Math.hypot(previous.x - other.x, previous.y - other.y);
              const after = Math.hypot(next.x - other.x, next.y - other.y);
              if (before > 0) setScale((v) => Math.min(4, Math.max(1, v * after / before)));
            } else if (scale > 1) {
              const bounds = e.currentTarget.getBoundingClientRect();
              const maxX = bounds.width * (scale - 1) / 2;
              const maxY = bounds.height * (scale - 1) / 2;
              setPan((v) => ({ x: Math.min(maxX, Math.max(-maxX, v.x + next.x - previous.x)), y: Math.min(maxY, Math.max(-maxY, v.y + next.y - previous.y)) }));
            }
            pointers.current.set(e.pointerId, next);
          }}>
          {isFailed ? (
            <div
              className="gallery-failed-placeholder"
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 12,
                color: "#ffffff",
                textAlign: "center",
                padding: 24,
              }}
            >
              <Icon name="image" size={48} />
              <button type="button" className="gallery-action-btn" onClick={() => { setCandidateIndex(0); setRetry(0); }}>重新加载</button>
              <span>{current.url || (current.sources && current.sources.length > 0) ? "图片加载失败" : "图片不可用或已被设为私密"}</span>
              {current.originalUrl && (
                <a
                  href={current.originalUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="gallery-action-btn"
                  style={{
                    background: "rgba(255,255,255,0.18)",
                    padding: "6px 14px",
                    borderRadius: 6,
                    color: "#ffffff",
                    textDecoration: "none",
                  }}
                >
                  打开原图链接
                </a>
              )}
            </div>
          ) : (
            <img
              key={`${currentIndex}-${currentSrc}`}
              src={currentSrc}
              alt={current.alt || "查看大图"}
              className="gallery-main-image"
              draggable={false}
              decoding="async"
              style={{ transform: `translate(${pan.x}px, ${pan.y}px) scale(${scale})`, cursor: scale > 1 ? "grab" : "zoom-in" }}
              onError={() => {
                if (candidateIndex + 1 < candidates.length) {
                  setCandidateIndex((idx) => idx + 1);
                } else {
                  setCandidateIndex(candidates.length);
                }
              }}
            />
          )}
        </div>

        {images.length > 1 && (
          <button
            type="button"
            className="gallery-nav-btn next-btn"
            aria-label="下一张"
            onClick={(e) => {
              e.stopPropagation();
              setCurrentIndex((idx) => (idx < images.length - 1 ? idx + 1 : 0));
            }}
          >
            <Icon name="chevron-right" size={28} />
          </button>
        )}
      </div>

      {images.length > 1 && (
        <div className="gallery-thumbnails">
          {images.map((img, index) => (
            <GalleryThumb
              key={`${img.url}-${index}`}
              img={img}
              active={index === currentIndex}
              onClick={() => setCurrentIndex(index)}
              index={index}
            />
          ))}
        </div>
      )}
    </div>
  );

  return createPortal(content, document.body);
}
