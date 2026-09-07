"use client";

import { useCallback, useEffect, useRef, useState, type ClipboardEvent, type DragEvent } from "react";
import { isPossiblySupportedImageFile } from "./api/forum";

export type LocalImagePreview = {
  id: string;
  file: File;
  url: string;
};

export type LocalImagePreviews = ReturnType<typeof useLocalImagePreviews>;

function newLocalPreview(file: File): LocalImagePreview {
  const suffix = typeof crypto !== "undefined" && "randomUUID" in crypto
    ? crypto.randomUUID()
    : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  return { id: suffix, file, url: URL.createObjectURL(file) };
}

function revokeLocalPreviews(items: LocalImagePreview[]) {
  for (const item of items) URL.revokeObjectURL(item.url);
}

export function useLocalImagePreviews(maxCount = 9) {
  const [items, setItems] = useState<LocalImagePreview[]>([]);
  const itemsRef = useRef(items);

  useEffect(() => {
    itemsRef.current = items;
  }, [items]);

  useEffect(() => () => revokeLocalPreviews(itemsRef.current), []);

  const append = useCallback((files: File[]) => {
    const supported = files.filter(isPossiblySupportedImageFile);
    const skippedUnsupported = files.length - supported.length;
    const slots = Math.max(0, maxCount - itemsRef.current.length);
    const additions = supported.slice(0, slots).map(newLocalPreview);
    const next = [...itemsRef.current, ...additions];
    itemsRef.current = next;
    setItems(next);
    return {
      added: additions.length,
      skippedUnsupported,
      skippedLimit: Math.max(0, supported.length - slots),
    };
  }, [maxCount]);

  const removeAt = useCallback((index: number) => {
    const current = itemsRef.current;
    const removed = current[index];
    if (removed) URL.revokeObjectURL(removed.url);
    const next = current.filter((_, idx) => idx !== index);
    itemsRef.current = next;
    setItems(next);
  }, []);

  const clear = useCallback(() => {
    revokeLocalPreviews(itemsRef.current);
    itemsRef.current = [];
    setItems([]);
  }, []);

  return { items, append, removeAt, clear };
}

export function useComposerImageInput({
  previews,
  onMessage,
  enabled = true,
}: {
  previews: LocalImagePreviews;
  onMessage: (message: string) => void;
  enabled?: boolean;
}) {
  const [dragActive, setDragActive] = useState(false);
  const dragDepth = useRef(0);

  const appendFiles = useCallback((files: File[]) => {
    if (!enabled || files.length === 0) return;
    const result = previews.append(files);
    if (result.skippedLimit > 0) onMessage("最多上传 9 张图片");
    else if (result.skippedUnsupported > 0) onMessage("已跳过不支持的文件");
    else onMessage("");
  }, [enabled, onMessage, previews]);

  const onPaste = useCallback((event: ClipboardEvent<HTMLElement>) => {
    const files = Array.from(event.clipboardData.items)
      .filter((item) => item.kind === "file")
      .map((item) => item.getAsFile())
      .filter((file): file is File => Boolean(file));
    if (files.length === 0) return;
    event.preventDefault();
    appendFiles(files);
  }, [appendFiles]);

  const onDragEnter = useCallback((event: DragEvent<HTMLElement>) => {
    if (!enabled || !Array.from(event.dataTransfer.types).includes("Files")) return;
    event.preventDefault();
    dragDepth.current += 1;
    setDragActive(true);
  }, [enabled]);

  const onDragOver = useCallback((event: DragEvent<HTMLElement>) => {
    if (!enabled || !Array.from(event.dataTransfer.types).includes("Files")) return;
    event.preventDefault();
    event.dataTransfer.dropEffect = "copy";
  }, [enabled]);

  const onDragLeave = useCallback((event: DragEvent<HTMLElement>) => {
    if (!enabled) return;
    event.preventDefault();
    dragDepth.current = Math.max(0, dragDepth.current - 1);
    if (dragDepth.current === 0) setDragActive(false);
  }, [enabled]);

  const onDrop = useCallback((event: DragEvent<HTMLElement>) => {
    if (!enabled) return;
    event.preventDefault();
    dragDepth.current = 0;
    setDragActive(false);
    appendFiles(Array.from(event.dataTransfer.files));
  }, [appendFiles, enabled]);

  return { appendFiles, dragActive, onPaste, onDragEnter, onDragOver, onDragLeave, onDrop };
}
