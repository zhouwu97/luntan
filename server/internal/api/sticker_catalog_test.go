package api

import "testing"

func TestStickerCatalogRejectsUnknownIDs(t *testing.T) {
	if !isAllowedStickerID("aad70d8d064f9eb79286c1393490716c") {
		t.Fatal("expected bundled sticker to be allowed")
	}
	if isAllowedStickerID("not-a-real-sticker") {
		t.Fatal("expected unknown sticker to be rejected")
	}
}
