package api

import (
	"strings"
	"testing"
)

func TestStoreOrderReviewNotificationDescribesActualInvalidation(t *testing.T) {
	tests := []struct {
		name     string
		decision string
		reason   string
		count    int
		points   int64
		want     []string
		notWant  []string
	}{
		{
			name:     "approved without invalidation",
			decision: "approve",
			count:    0,
			points:   0,
			want:     []string{"已通过审核", "已扣除 100 积分"},
			notWant:  []string{"无效", "未通过"},
		},
		{
			name:     "approved with invalidation",
			decision: "approve",
			count:    2,
			points:   30,
			want:     []string{"另认定 2 条奖励记录无效", "30 积分"},
		},
		{
			name:     "rejected without invalidation",
			decision: "reject",
			reason:   "内容重复",
			count:    0,
			want:     []string{"未通过审核", "原因：内容重复", "未对你的历史积分作失效处理"},
			notWant:  []string{"相关积分不计入兑换资格"},
		},
		{
			name:     "rejected with invalidation",
			decision: "reject",
			reason:   "刷屏",
			count:    1,
			points:   15,
			want:     []string{"未通过审核", "1 条奖励记录无效", "15 积分"},
		},
	}

	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			message := storeOrderReviewNotification("校园徽章", test.decision, test.reason, 100, test.count, test.points)
			for _, value := range test.want {
				if !strings.Contains(message, value) {
					t.Fatalf("message %q does not contain %q", message, value)
				}
			}
			for _, value := range test.notWant {
				if strings.Contains(message, value) {
					t.Fatalf("message %q must not contain %q", message, value)
				}
			}
		})
	}
}

func TestValidStoreOrderStatusIncludesAll(t *testing.T) {
	if !validStoreOrderStatus("all") {
		t.Fatal("all must be a valid admin store order status filter")
	}
}
