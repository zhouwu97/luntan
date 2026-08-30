package media

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"image"
	"image/color"
	"image/jpeg"
	"os"
	"path/filepath"
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

func TestProcessImage_WebP(t *testing.T) {
	fixturePath := filepath.Join("..", "..", "..", "assets", "ranking", "hero.webp")
	sourceBytes, err := os.ReadFile(fixturePath)
	if err != nil {
		t.Fatalf("read WebP fixture: %v", err)
	}

	res, err := ProcessImage(bytes.NewReader(sourceBytes))
	if err != nil {
		t.Fatalf("ProcessImage WebP failed: %v", err)
	}
	if res.SourceMimeType != "image/webp" {
		t.Fatalf("source mime type = %q, want image/webp", res.SourceMimeType)
	}
	if res.Original.Width <= 0 || res.Original.Height <= 0 {
		t.Fatalf("invalid WebP dimensions: %dx%d", res.Original.Width, res.Original.Height)
	}
}

// buildTIFF 构造仅含一个 IFD0 条目的最小 TIFF 载荷。
func buildTIFF(order binary.ByteOrder, tag, typ uint16, orientation int) []byte {
	var tiff []byte
	append16 := func(v uint16) {
		tiff = append(tiff, 0, 0)
		order.PutUint16(tiff[len(tiff)-2:], v)
	}
	append32 := func(v uint32) {
		tiff = append(tiff, 0, 0, 0, 0)
		order.PutUint32(tiff[len(tiff)-4:], v)
	}
	if order == binary.BigEndian {
		tiff = append(tiff, 'M', 'M')
	} else {
		tiff = append(tiff, 'I', 'I')
	}
	append16(42)  // 魔数
	append32(8)   // IFD0 偏移
	append16(1)   // 条目数
	append16(tag) // tag
	append16(typ) // 类型
	append32(1)   // count
	append16(uint16(orientation))
	append16(0)
	append32(0) // 下一 IFD
	return tiff
}

// injectAPP1 在 JPEG SOI 之后插入一个 APP1 段（"Exif\0\0" + tiff）。
func injectAPP1(jpegBytes, tiff []byte) []byte {
	payload := append([]byte("Exif\x00\x00"), tiff...)
	seg := make([]byte, 4, 4+len(payload))
	seg[0], seg[1] = 0xFF, 0xE1
	binary.BigEndian.PutUint16(seg[2:4], uint16(len(payload)+2))
	seg = append(seg, payload...)
	out := make([]byte, 0, len(jpegBytes)+len(seg))
	out = append(out, jpegBytes[:2]...)
	out = append(out, seg...)
	out = append(out, jpegBytes[2:]...)
	return out
}

// createLeftRightJPEG 左半红右半蓝的测试图，用色块方向验证像素旋转。
func createLeftRightJPEG(w, h int) []byte {
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			if x < w/2 {
				img.Set(x, y, color.RGBA{R: 220, G: 30, B: 30, A: 255})
			} else {
				img.Set(x, y, color.RGBA{R: 30, G: 30, B: 220, A: 255})
			}
		}
	}
	var buf bytes.Buffer
	_ = jpeg.Encode(&buf, img, &jpeg.Options{Quality: 95})
	return buf.Bytes()
}

func mustDecodeImage(t *testing.T, data []byte) image.Image {
	t.Helper()
	img, _, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		t.Fatalf("decode variant image: %v", err)
	}
	return img
}

func avgRegion(img image.Image, rect image.Rectangle) (r, g, b float64) {
	var sumR, sumG, sumB, n float64
	for y := rect.Min.Y; y < rect.Max.Y; y++ {
		for x := rect.Min.X; x < rect.Max.X; x++ {
			c := color.RGBAModel.Convert(img.At(x, y)).(color.RGBA)
			sumR += float64(c.R)
			sumG += float64(c.G)
			sumB += float64(c.B)
			n++
		}
	}
	return sumR / n, sumG / n, sumB / n
}

func TestProcessImage_AppliesEXIFOrientation(t *testing.T) {
	// 800x400 左半红右半蓝。横拍照片（Orientation=6/8）摆正后尺寸应交换为
	// 400x800，且像素方向随标记旋转，而不是重编码后永久躺倒。
	base := createLeftRightJPEG(800, 400)

	t.Run("orientation 6 顺时针 90", func(t *testing.T) {
		res, err := ProcessImage(bytes.NewReader(injectAPP1(base, buildTIFF(binary.LittleEndian, 0x0112, 3, 6))))
		if err != nil {
			t.Fatalf("ProcessImage failed: %v", err)
		}
		if res.Original.Width != 400 || res.Original.Height != 800 {
			t.Errorf("expected original 400x800, got %dx%d", res.Original.Width, res.Original.Height)
		}
		if res.Detail.Width != 400 || res.Detail.Height != 800 {
			t.Errorf("expected detail 400x800, got %dx%d", res.Detail.Width, res.Detail.Height)
		}
		// thumb 长边压到 640：320x640
		if res.Thumb.Width != 320 || res.Thumb.Height != 640 {
			t.Errorf("expected thumb 320x640, got %dx%d", res.Thumb.Width, res.Thumb.Height)
		}
		orig := mustDecodeImage(t, res.Original.Data)
		rTop, _, bTop := avgRegion(orig, image.Rect(150, 10, 250, 70))
		rBot, _, bBot := avgRegion(orig, image.Rect(150, 730, 250, 790))
		if rTop <= bTop {
			t.Errorf("expected top region red after rotate 90 CW, got r=%.0f b=%.0f", rTop, bTop)
		}
		if rBot >= bBot {
			t.Errorf("expected bottom region blue after rotate 90 CW, got r=%.0f b=%.0f", rBot, bBot)
		}
	})

	t.Run("orientation 8 逆时针 90", func(t *testing.T) {
		res, err := ProcessImage(bytes.NewReader(injectAPP1(base, buildTIFF(binary.LittleEndian, 0x0112, 3, 8))))
		if err != nil {
			t.Fatalf("ProcessImage failed: %v", err)
		}
		if res.Original.Width != 400 || res.Original.Height != 800 {
			t.Errorf("expected original 400x800, got %dx%d", res.Original.Width, res.Original.Height)
		}
		orig := mustDecodeImage(t, res.Original.Data)
		rTop, _, bTop := avgRegion(orig, image.Rect(150, 10, 250, 70))
		rBot, _, bBot := avgRegion(orig, image.Rect(150, 730, 250, 790))
		if bTop <= rTop {
			t.Errorf("expected top region blue after rotate 90 CCW, got r=%.0f b=%.0f", rTop, bTop)
		}
		if bBot >= rBot {
			t.Errorf("expected bottom region red after rotate 90 CCW, got r=%.0f b=%.0f", rBot, bBot)
		}
	})

	t.Run("orientation 1 尺寸保持原样", func(t *testing.T) {
		res, err := ProcessImage(bytes.NewReader(injectAPP1(base, buildTIFF(binary.LittleEndian, 0x0112, 3, 1))))
		if err != nil {
			t.Fatalf("ProcessImage failed: %v", err)
		}
		if res.Original.Width != 800 || res.Original.Height != 400 {
			t.Errorf("expected original 800x400, got %dx%d", res.Original.Width, res.Original.Height)
		}
	})
}

func TestProcessImage_ToleratesBrokenEXIF(t *testing.T) {
	base := createTestJPEG(320, 240)
	cases := map[string][]byte{
		"截断的 TIFF 头":      injectAPP1(base, []byte{'I', 'I', 0x2A}),
		"非法 TIFF 字节序":     injectAPP1(base, []byte("XX0123456789")),
		"orientation 越界":  injectAPP1(base, buildTIFF(binary.LittleEndian, 0x0112, 3, 9)),
		"orientation 为 0": injectAPP1(base, buildTIFF(binary.LittleEndian, 0x0112, 3, 0)),
		"条目类型异常":          injectAPP1(base, buildTIFF(binary.LittleEndian, 0x0112, 1, 6)),
	}
	for name, data := range cases {
		t.Run(name, func(t *testing.T) {
			res, err := ProcessImage(bytes.NewReader(data))
			if err != nil {
				t.Fatalf("ProcessImage with %s failed: %v", name, err)
			}
			if res.Original.Width != 320 || res.Original.Height != 240 {
				t.Errorf("expected untouched 320x240, got %dx%d", res.Original.Width, res.Original.Height)
			}
		})
	}
}

func jpegWithSegments(segs ...[]byte) []byte {
	out := []byte{0xFF, 0xD8}
	for _, s := range segs {
		out = append(out, s...)
	}
	return out
}

func plainSegment(marker byte, payload []byte) []byte {
	seg := make([]byte, 4, 4+len(payload))
	seg[0], seg[1] = 0xFF, marker
	binary.BigEndian.PutUint16(seg[2:4], uint16(len(payload)+2))
	return append(seg, payload...)
}

func TestReadEXIFOrientation(t *testing.T) {
	exifSeg := func(order binary.ByteOrder, orientation int) []byte {
		return plainSegment(0xE1, append([]byte("Exif\x00\x00"), buildTIFF(order, 0x0112, 3, orientation)...))
	}

	cases := []struct {
		name string
		data []byte
		want int
	}{
		{"非 JPEG", []byte{0x00, 0x01, 0x02}, 1},
		{"无 marker 的裸数据", []byte{0xFF, 0xD8, 0x12, 0x34}, 1},
		{"小端 Orientation 6", jpegWithSegments(exifSeg(binary.LittleEndian, 6)), 6},
		{"大端 Orientation 8", jpegWithSegments(exifSeg(binary.BigEndian, 8)), 8},
		{"填充字节后仍可解析", jpegWithSegments([]byte{0xFF, 0xFF, 0xFF}, exifSeg(binary.LittleEndian, 3)), 3},
		{"跳过 JFIF APP0", jpegWithSegments(plainSegment(0xE0, []byte("JFIF0000")), exifSeg(binary.LittleEndian, 5)), 5},
		{"SOS 前无 EXIF", jpegWithSegments(plainSegment(0xDA, []byte{0x00})), 1},
		{"段长越界", jpegWithSegments(plainSegment(0xE1, []byte("Exif\x00\x00short"))[:6]), 1},
		{"无 Orientation 条目", jpegWithSegments(plainSegment(0xE1, append([]byte("Exif\x00\x00"), buildTIFF(binary.LittleEndian, 0x010F, 3, 6)...))), 1},
		{"XMP APP1 不误读", jpegWithSegments(plainSegment(0xE1, []byte("http://ns.adobe.com/xap/1.0/"))), 1},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := readEXIFOrientation(tc.data); got != tc.want {
				t.Errorf("readEXIFOrientation = %d, want %d", got, tc.want)
			}
		})
	}
}
