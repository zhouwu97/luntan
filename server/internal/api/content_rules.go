package api

import "regexp"

var suspiciousContentPattern = regexp.MustCompile(`(?i)(微信群|QQ群|加\s*(微信|QQ)|淘宝|taobao\.com|https?://|(^|[^0-9])[0-9]{11}([^0-9]|$))`)

func contentNeedsReview(title, content string) bool {
	return suspiciousContentPattern.MatchString(title) || suspiciousContentPattern.MatchString(content)
}
