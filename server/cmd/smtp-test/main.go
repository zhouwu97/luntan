// smtp-test 用于从部署服务器向指定邮箱发送一封最小测试邮件。
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/zhouwu97/luntan/server/internal/platform/config"
	"github.com/zhouwu97/luntan/server/internal/platform/mail"
)

func main() {
	to := flag.String("to", "", "测试收件人邮箱")
	subject := flag.String("subject", "论坛邮箱服务测试", "测试邮件主题")
	body := flag.String("body", "如果你收到这封邮件，说明论坛 SMTP 邮件服务配置成功。", "测试邮件正文")
	flag.Parse()
	if *to == "" {
		fmt.Fprintln(os.Stderr, "missing required -to")
		os.Exit(2)
	}

	cfg := config.Load()
	sender, err := mail.NewSender(mail.ConfigFromEnv(cfg.AppEnv))
	if err != nil {
		fmt.Fprintf(os.Stderr, "smtp configuration failed: %v\n", err)
		os.Exit(1)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	if err := sender.Send(ctx, *to, *subject, *body); err != nil {
		fmt.Fprintf(os.Stderr, "smtp smoke test failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("smtp smoke test sent: to=%s subject=%q\n", *to, *subject)
}
