"use client";

import { useEffect, useState } from "react";
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
  const thumbCandidates =
    img.sources && img.sources.length > 0
      ? [img.thumbUrl, ...img.sources].filter((s): s is string => Boolean(s))
      : ([img.thumbUrl, img.url, img.detailUrl, img.originalUrl].filter((s): s is string => Boolean(s)));
  const [thumbIdx, setThumbIdx] = useState(0);
  const src = thumbCandidates[thumbIdx] || img.url;

  return (
    <button
      type="button"
      className={`gallery-thumb-btn${active ? " active" : ""}`}
      onClick={onClick}
      aria-label={`查看第 ${index + 1} 张`}
    >
      <img
        src={src}
        alt=""
        onError={() => {
          if (thumbIdx + 1 < thumbCandidates.length) {
            setThumbIdx((i) => i + 1);
          }
        }}
      />
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

  useEffect(() => {
    setMounted(true);
  }, []);

  useEffect(() => {
    setCandidateIndex(0);
  }, [currentIndex]);

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
  const current = images[currentIndex] || images[0];

  const candidates =
    current.sources && current.sources.length > 0
      ? current.sources
      : ([current.detailUrl, current.originalUrl, current.url, current.thumbUrl].filter((s): s is string => Boolean(s)));
  const currentSrc = candidates[candidateIndex] || current.url;
  const isFailed = candidateIndex >= candidates.length && candidates.length > 0;

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
          {(current.originalUrl || currentSrc) && (
            <a
              href={current.originalUrl || currentSrc}
              target="_blank"
              rel="noreferrer"
              className="gallery-action-btn"
              title="查看原图"
              aria-label="查看原图"
            >
              <Icon name="arrow-up-right" size={17} />
              <span>原图</span>
            </a>
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

        <div className="gallery-image-container">
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
              <span>图片加载失败</span>
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
