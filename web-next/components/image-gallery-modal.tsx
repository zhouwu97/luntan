"use client";

import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { Icon } from "./icons";

export interface GalleryImage {
  url: string;
  alt?: string;
  originalUrl?: string;
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
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

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
          {current.originalUrl && (
            <a
              href={current.originalUrl}
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

      <div className="gallery-stage" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
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
          <img
            src={current.url}
            alt={current.alt || "查看大图"}
            className="gallery-main-image"
          />
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
            <button
              type="button"
              key={`${img.url}-${index}`}
              className={`gallery-thumb-btn${index === currentIndex ? " active" : ""}`}
              onClick={() => setCurrentIndex(index)}
              aria-label={`查看第 ${index + 1} 张`}
            >
              <img src={img.url} alt="" />
            </button>
          ))}
        </div>
      )}
    </div>
  );

  return createPortal(content, document.body);
}
