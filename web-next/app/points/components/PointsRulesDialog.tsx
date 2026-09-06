"use client";

import { Icon } from "../../../components/icons";

interface PointsRulesDialogProps {
  open: boolean;
  onClose: () => void;
}

export function PointsRulesDialog({ open, onClose }: PointsRulesDialogProps) {
  if (!open) return null;

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-label="社区积分规则说明"
        onClick={(e) => e.stopPropagation()}
        style={{ maxWidth: 480 }}
      >
        <div className="modal-head">
          <h3>社区积分规则说明</h3>
          <button type="button" className="modal-close" onClick={onClose}>
            <Icon name="close" size={18} />
          </button>
        </div>
        <div className="modal-body rules-body">
          <h4>如何获取积分？</h4>
          <ul>
            <li>
              <strong>每日登录/签到</strong>：每日首次访问社区获得{" "}
              <strong>+5 积分</strong>。
            </li>
            <li>
              <strong>发布优质内容</strong>：每发布一篇有效帖子获得{" "}
              <strong>+10 积分</strong>（每日上限 30 积分）。
            </li>
            <li>
              <strong>发表互动评论</strong>：发表建设性回复获得{" "}
              <strong>+2 积分</strong>（每日上限 20 积分）。
            </li>
            <li>
              <strong>收获同好点赞</strong>：你的帖子或评论每获得 1 个点赞获得{" "}
              <strong>+1 积分</strong>。
            </li>
          </ul>

          <h4>兑换与履约规则</h4>
          <ul>
            <li>
              提交兑换申请后，所需积分将作为<strong>审核中占用积分</strong>预留。
            </li>
            <li>
              人工审核通过后，系统将正式扣除积分，并通知你填写收件人与收货地址。
            </li>
            <li>
              填写地址后，管理员将安排物流快递寄送并更新运单号。
            </li>
            <li>
              收到周边商品后，请在兑换记录中点击「确认已收到」，完成订单履约。
            </li>
            <li>
              严禁使用脚本或违规刷分，一经核实将扣减违规积分并取消兑换资格。
            </li>
          </ul>
        </div>
        <div className="modal-actions">
          <button type="button" className="primary-button" onClick={onClose}>
            我知道了
          </button>
        </div>
      </div>
    </div>
  );
}
