package media

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"image"
	"image/color"
	"image/jpeg"
	"testing"
)

func createTestJPEG(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			img.Set(x, y, color.RGBA{
				R: uint8((x * 255) / w),
				G: uint8((y * 255) / h),
				B: 128,
				A: 255,
			})
		}
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 95})
	return buf.Bytes()
}

func TestProcessImage_2400x1600(t *testing.T) {
	sourceBytes := createTestJPEG(2400, 1600)
	sourceHasher := sha256.New()
	_, _ = sourceHasher.Write(sourceBytes)
	sourceHash := hex.EncodeToString(sourceHasher.Sum(nil))

	res, err := ProcessImage(bytes.NewReader(sourceBytes))
	if err != nil {
		t.Fatalf("ProcessImage failed: %v", err)
	}

	// 验证 Original 变体
	if res.Original.Width != 2400 || res.Original.Height != 1600 {
		t.Errorf("expected original 2400x1600, got %dx%d", res.Original.Width, res.Original.Height)
	}
	// 验证 Detail 变体 (长边 <= 1440)
	if res.Detail.Width != 1440 || res.Detail.Height != 960 {
		t.Errorf("expected detail 1440x960, got %dx%d", res.Detail.Width, res.Detail.Height)
	}
	// 验证 Thumb 变体 (长边 <= 640)
	if res.Thumb.Width != 640 || (res.Thumb.Height != 426 && res.Thumb.Height != 427) {
		t.Errorf("expected thumb 640x427, got %dx%d", res.Thumb.Width, res.Thumb.Height)
	}

	// 断言尺寸递进关系
	if !(res.Thumb.Width < res.Detail.Width && res.Detail.Width <= res.Original.Width) {
		t.Errorf("dimension inequality violated: thumb.w=%d, detail.w=%d, orig.w=%d", res.Thumb.Width, res.Detail.Width, res.Original.Width)
	}

	// 断言体积递进关系
	if res.Thumb.SizeBytes >= res.Detail.SizeBytes {
		t.Errorf("size inequality violated: thumb.size=%d, detail.size=%d", res.Thumb.SizeBytes, res.Detail.SizeBytes)
	}

	// 断言 SHA256 哈希各不相同
	if res.Thumb.SHA256 == sourceHash {
		t.Errorf("thumb SHA256 matches source hash")
	}
	if res.Detail.SHA256 == sourceHash {
		t.Errorf("detail SHA256 matches source hash")
	}
	if res.Thumb.SHA256 == res.Detail.SHA256 {
		t.Errorf("thumb and detail have identical SHA256")
	}

	t.Logf("2400x1600 processed successfully: original=%dx%d (%d B), detail=%dx%d (%d B), thumb=%dx%d (%d B)",
		res.Original.Width, res.Original.Height, res.Original.SizeBytes,
		res.Detail.Width, res.Detail.Height, res.Detail.SizeBytes,
		res.Thumb.Width, res.Thumb.Height, res.Thumb.SizeBytes,
	)
}

func TestProcessImage_4032x3024(t *testing.T) {
	sourceBytes := createTestJPEG(4032, 3024)
	res, err := ProcessImage(bytes.NewReader(sourceBytes))
	if err != nil {
		t.Fatalf("ProcessImage failed: %v", err)
	}

	if res.Original.Width != 4032 || res.Original.Height != 3024 {
		t.Errorf("expected original 4032x3024, got %dx%d", res.Original.Width, res.Original.Height)
	}
	if res.Detail.Width != 1440 || res.Detail.Height != 1080 {
		t.Errorf("expected detail 1440x1080, got %dx%d", res.Detail.Width, res.Detail.Height)
	}
	if res.Thumb.Width != 640 || res.Thumb.Height != 480 {
		t.Errorf("expected thumb 640x480, got %dx%d", res.Thumb.Width, res.Thumb.Height)
	}

	t.Logf("4032x3024 processed successfully: original=%dx%d (%d B), detail=%dx%d (%d B), thumb=%dx%d (%d B)",
		res.Original.Width, res.Original.Height, res.Original.SizeBytes,
		res.Detail.Width, res.Detail.Height, res.Detail.SizeBytes,
		res.Thumb.Width, res.Thumb.Height, res.Thumb.SizeBytes,
	)
}

func TestProcessImage_SmallImage_NoUpscale(t *testing.T) {
	sourceBytes := createTestJPEG(400, 300)
	res, err := ProcessImage(bytes.NewReader(sourceBytes))
	if err != nil {
		t.Fatalf("ProcessImage failed: %v", err)
	}

	// 小图不放大
	if res.Thumb.Width != 400 || res.Thumb.Height != 300 {
		t.Errorf("expected thumb 400x300, got %dx%d", res.Thumb.Width, res.Thumb.Height)
	}
	if res.Detail.Width != 400 || res.Detail.Height != 300 {
		t.Errorf("expected detail 400x300, got %dx%d", res.Detail.Width, res.Detail.Height)
	}
	if res.Original.Width != 400 || res.Original.Height != 300 {
		t.Errorf("expected original 400x300, got %dx%d", res.Original.Width, res.Original.Height)
	}
}
