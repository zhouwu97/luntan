package api

import (
	"os"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"testing"
)

func TestStickerCatalogRejectsUnknownIDs(t *testing.T) {
	if !isAllowedStickerID("aad70d8d064f9eb79286c1393490716c") {
		t.Fatal("expected bundled sticker to be allowed")
	}
	if isAllowedStickerID("not-a-real-sticker") {
		t.Fatal("expected unknown sticker to be rejected")
	}
}

func TestStickerCatalogMatchesWebAssets(t *testing.T) {
	_, testFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("无法定位 sticker catalog 测试文件")
	}
	repoRoot := filepath.Clean(filepath.Join(filepath.Dir(testFile), "../../.."))
	webCatalogPath := filepath.Join(repoRoot, "web-next", "lib", "sticker-catalog.ts")
	stickersDir := filepath.Join(repoRoot, "web-next", "public", "stickers")

	source, err := os.ReadFile(webCatalogPath)
	if err != nil {
		t.Fatalf("读取前端表情目录失败: %v", err)
	}

	groupIDPattern := regexp.MustCompile(`\bid:\s*"([^"]+)"`)
	stickerPattern := regexp.MustCompile(`\["([^"]+)",\s*"[^"]+"\]`)
	validStickerID := regexp.MustCompile(`^[a-f0-9]{32}$`)

	groups := groupIDPattern.FindAllStringSubmatch(string(source), -1)
	groupIDs := make(map[string]struct{}, len(groups))
	for _, match := range groups {
		id := match[1]
		if _, duplicate := groupIDs[id]; duplicate {
			t.Errorf("前端表情分组 ID 重复: %s", id)
		}
		groupIDs[id] = struct{}{}
	}
	if len(groupIDs) == 0 {
		t.Fatal("前端表情目录没有分组 ID")
	}

	stickers := stickerPattern.FindAllStringSubmatch(string(source), -1)
	stickerIDs := make(map[string]struct{}, len(stickers))
	for _, match := range stickers {
		id := match[1]
		if !validStickerID.MatchString(id) {
			t.Errorf("前端表情 ID 必须是 32 位小写 hex: %s", id)
			continue
		}
		if _, duplicate := stickerIDs[id]; duplicate {
			t.Errorf("前端表情 ID 重复: %s", id)
		}
		stickerIDs[id] = struct{}{}
		if !isAllowedStickerID(id) {
			t.Errorf("服务端 allowlist 缺少前端表情 ID: %s", id)
		}
		if _, err := os.Stat(filepath.Join(stickersDir, id+".png")); err != nil {
			t.Errorf("缺少前端表情资源 %s.png: %v", id, err)
		}
	}
	if len(stickerIDs) == 0 {
		t.Fatal("前端表情目录没有表情项")
	}

	entries, err := os.ReadDir(stickersDir)
	if err != nil {
		t.Fatalf("读取前端表情资源目录失败: %v", err)
	}
	var assetNames []string
	for _, entry := range entries {
		if !entry.IsDir() {
			assetNames = append(assetNames, entry.Name())
		}
	}
	sort.Strings(assetNames)
	for _, name := range assetNames {
		if filepath.Ext(name) != ".png" {
			continue
		}
		id := name[:len(name)-len(filepath.Ext(name))]
		if !validStickerID.MatchString(id) {
			t.Errorf("表情资源文件名必须是 32 位小写 hex: %s", name)
		}
	}
}
