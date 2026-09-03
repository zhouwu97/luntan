"use client";

import { FormEvent, useEffect, useState } from "react";
import { Icon } from "./icons";
import { useToast } from "./toast-context";
import { createReport } from "../lib/api/forum";
import { formatError } from "../lib/format";

const REPORT_REASONS = [
  { code: "spam", label: "垃圾广告、恶意刷屏" },
  { code: "porn", label: "色情低俗、不雅内容" },
  { code: "abuse", label: "人身攻击、辱骂侵权" },
  { code: "illegal", label: "违法违规、诈骗欺凌" },
  { code: "other", label: "其他违反社区规范的行为" },
];

export function ReportModal({
  targetType,
  targetId,
  targetTitle,
  onClose,
  onSuccess,
}: {
  targetType: "post" | "comment" | "user" | "community";
  targetId: string;
  targetTitle?: string;
  onClose: () => void;
  onSuccess?: () => void;
}) {
  const { showToast } = useToast();
  const [reasonCode, setReasonCode] = useState("spam");
  const [description, setDescription] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [onClose]);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (submitting) return;
    setSubmitting(true);
    setError("");
    try {
      await createReport({
        targetType,
        targetId,
        reasonCode,
        description: description.trim(),
      });
      showToast("举报已提交，我们会尽快核实处理");
      if (onSuccess) onSuccess();
      onClose();
    } catch (err) {
      setError(formatError(err, "举报提交失败，请稍后重试"));
    } finally {
      setSubmitting(false);
    }
  }

  const typeName =
    targetType === "post" ? "帖子" : targetType === "comment" ? "评论" : targetType === "user" ? "用户" : "社区";

  return (
    <div
      className="report-modal-overlay"
      role="dialog"
      aria-modal="true"
      aria-label={`举报${typeName}`}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="report-modal-container">
        <div className="report-modal-head">
          <h3>举报{typeName}</h3>
          <button type="button" className="report-close-btn" onClick={onClose} aria-label="关闭">
            <Icon name="close" size={18} />
          </button>
        </div>

        {targetTitle && (
          <p className="report-target-preview">
            目标：<span>{targetTitle}</span>
          </p>
        )}

        <form onSubmit={handleSubmit} className="report-form">
          <div className="report-reasons-list">
            <label className="report-label">请选择违规原因：</label>
            {REPORT_REASONS.map((reason) => (
              <label key={reason.code} className="report-reason-item">
                <input
                  type="radio"
                  name="report_reason"
                  value={reason.code}
                  checked={reasonCode === reason.code}
                  onChange={() => setReasonCode(reason.code)}
                />
                <span>{reason.label}</span>
              </label>
            ))}
          </div>

          <div className="report-desc-wrap">
            <label className="report-label" htmlFor="report-description">
              补充说明（选填）：
            </label>
            <textarea
              id="report-description"
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              placeholder="请提供更多背景信息，以便管理员更快核实…"
              rows={3}
              maxLength={500}
            />
            <span className="report-count">{description.length}/500</span>
          </div>

          {error && <div className="report-error">{error}</div>}

          <div className="report-modal-actions">
            <button type="button" className="outline-button" onClick={onClose} disabled={submitting}>
              取消
            </button>
            <button type="submit" className="primary-button danger" disabled={submitting}>
              {submitting ? "正在提交…" : "确认提交举报"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
