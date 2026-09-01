package api

import (
	"bytes"
	"embed"
	"net/http"
	"time"
)

// 商品图随 API 二进制发布，避免依赖服务器额外挂载目录或外部图床。
//
//go:embed store_assets/badge.jpg store_assets/standee.jpg
var storeProductImages embed.FS

var storeProductImageFiles = map[string]string{
	"badge":   "store_assets/badge.jpg",
	"standee": "store_assets/standee.jpg",
}

func storeProductImageURL(productID string) string {
	if _, ok := storeProductImageFiles[productID]; !ok {
		return ""
	}
	return "/api/v1/store/products/" + productID + "/image"
}

func (s *Server) serveStoreProductImage(w http.ResponseWriter, r *http.Request, productID string) {
	assetPath, ok := storeProductImageFiles[productID]
	if !ok {
		http.NotFound(w, r)
		return
	}
	data, err := storeProductImages.ReadFile(assetPath)
	if err != nil {
		writeInternalError(w, r, err)
		return
	}

	// 商品图是随版本发布的固定资源，可安全使用长期缓存。
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	w.Header().Set("Content-Type", "image/jpeg")
	http.ServeContent(w, r, assetPath, time.Time{}, bytes.NewReader(data))
}
