package media

import (
	"bytes"
	"crypto/sha256"
	"encoding/binary"
	"encoding/hex"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/jpeg"
	"image/png"
	"io"
	"math"

	_ "golang.org/x/image/webp"

	xdraw "golang.org/x/image/draw"
)

type ProcessedVariant struct {
	Variant   string // "thumb", "detail", "original"
	MimeType  string
	Width     int
	Height    int
	SizeBytes int64
	SHA256    string
	Data      []byte
}

type ProcessResult struct {
	OriginalWidth  int
	OriginalHeight int
	SourceMimeType string
	Thumb          ProcessedVariant
	Detail         ProcessedVariant
	Original       ProcessedVariant
}

// ProcessImage 真实解码图像源文件，剔除 EXIF/GPS 元数据并按分辨率生成
// thumb (<= 640px)、detail (<= 1440px) 与 original (原尺寸重新编码) 变体。
func ProcessImage(r io.Reader) (*ProcessResult, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, fmt.Errorf("read source image data: %w", err)
	}
	if len(data) == 0 {
		return nil, fmt.Errorf("empty image data")
	}

	srcImg, format, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("decode image (%s): %w", format, err)
	}

	// 手机横拍/竖拍的照片像素并不旋转，仅靠 EXIF Orientation 标记告知查看器摆正
	// 方向。重编码会剥离全部元数据，若不先按标记旋转像素，这类照片将永久躺倒。
	srcImg = applyEXIFOrientation(srcImg, readEXIFOrientation(data))

	bounds := srcImg.Bounds()
	origW := bounds.Dx()
	origH := bounds.Dy()
	if origW <= 0 || origH <= 0 {
		return nil, fmt.Errorf("invalid image dimensions: %dx%d", origW, origH)
	}

	// 1. 生成 original 变体（保持原分辨率，通过解码->重新编码彻底剥离 EXIF / GPS）
	origVariant, err := encodeVariant(srcImg, origW, origH, "original", 90)
	if err != nil {
		return nil, fmt.Errorf("encode original variant: %w", err)
	}

	// 2. 生成 detail 变体（长边 <= 1440px）
	detailW, detailH := calcScaledDimensions(origW, origH, 1440)
	var detailImg image.Image = srcImg
	if detailW != origW || detailH != origH {
		detailImg = resizeCatmullRom(srcImg, detailW, detailH)
	}
	detailVariant, err := encodeVariant(detailImg, detailW, detailH, "detail", 85)
	if err != nil {
		return nil, fmt.Errorf("encode detail variant: %w", err)
	}

	// 3. 生成 thumb 变体（长边 <= 640px）
	thumbW, thumbH := calcScaledDimensions(origW, origH, 640)
	var thumbImg image.Image = srcImg
	if thumbW != origW || thumbH != origH {
		thumbImg = resizeCatmullRom(srcImg, thumbW, thumbH)
	}
	thumbVariant, err := encodeVariant(thumbImg, thumbW, thumbH, "thumb", 80)
	if err != nil {
		return nil, fmt.Errorf("encode thumb variant: %w", err)
	}

	return &ProcessResult{
		OriginalWidth:  origW,
		OriginalHeight: origH,
		SourceMimeType: "image/" + format,
		Thumb:          thumbVariant,
		Detail:         detailVariant,
		Original:       origVariant,
	}, nil
}

func calcScaledDimensions(w, h, maxDimension int) (int, int) {
	maxSide := w
	if h > maxSide {
		maxSide = h
	}
	if maxSide <= maxDimension {
		return w, h
	}
	scale := float64(maxDimension) / float64(maxSide)
	newW := int(math.Round(float64(w) * scale))
	newH := int(math.Round(float64(h) * scale))
	if newW < 1 {
		newW = 1
	}
	if newH < 1 {
		newH = 1
	}
	return newW, newH
}

func encodeVariant(img image.Image, targetW, targetH int, variantName string, quality int) (ProcessedVariant, error) {
	var buf bytes.Buffer
	// JPEG 没有 alpha 通道。先铺白底再合成，避免 PNG/WebP 的透明区域在
	// 重新编码后变成黑块或未定义颜色。
	err := jpeg.Encode(&buf, flattenAlpha(img), &jpeg.Options{Quality: quality})
	if err != nil {
		return ProcessedVariant{}, err
	}
	bytesData := buf.Bytes()
	hasher := sha256.New()
	_, _ = hasher.Write(bytesData)
	hashStr := hex.EncodeToString(hasher.Sum(nil))

	return ProcessedVariant{
		Variant:   variantName,
		MimeType:  "image/jpeg",
		Width:     targetW,
		Height:    targetH,
		SizeBytes: int64(len(bytesData)),
		SHA256:    hashStr,
		Data:      bytesData,
	}, nil
}

func flattenAlpha(src image.Image) image.Image {
	bounds := src.Bounds()
	dst := image.NewRGBA(image.Rect(0, 0, bounds.Dx(), bounds.Dy()))
	draw.Draw(dst, dst.Bounds(), image.NewUniform(color.White), image.Point{}, draw.Src)
	draw.Draw(dst, dst.Bounds(), src, bounds.Min, draw.Over)
	return dst
}

// resizeCatmullRom 用 x/image 的 CatmullRom 三次卷积插值缩放，画质优于
// 手写双线性插值，且由官方库持续维护。
func resizeCatmullRom(src image.Image, dstW, dstH int) *image.RGBA {
	dst := image.NewRGBA(image.Rect(0, 0, dstW, dstH))
	if dstW <= 0 || dstH <= 0 {
		return dst
	}
	xdraw.CatmullRom.Scale(dst, dst.Bounds(), src, src.Bounds(), xdraw.Src, nil)
	return dst
}

// readEXIFOrientation 从 JPEG APP1 (Exif) 段读取 Orientation(0x0112) 标记，
// 返回 1-8；非 JPEG、缺失或结构异常时一律返回 1（不旋转），绝不因解析失败
// 阻断上传处理。
func readEXIFOrientation(data []byte) int {
	if len(data) < 4 || data[0] != 0xFF || data[1] != 0xD8 {
		return 1
	}
	pos := 2
	for pos+4 <= len(data) {
		if data[pos] != 0xFF {
			return 1
		}
		marker := data[pos+1]
		switch {
		case marker == 0xFF: // 填充字节，前进 1 字节后才是真实 marker
			pos++
			continue
		case marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7): // 无长度的独立 marker
			pos += 2
			continue
		case marker == 0xDA: // SOS 之后是压缩数据，不会再有 EXIF
			return 1
		}
		segLen := int(data[pos+2])<<8 | int(data[pos+3])
		if segLen < 2 || pos+2+segLen > len(data) {
			return 1
		}
		payload := data[pos+4 : pos+2+segLen]
		if marker == 0xE1 && len(payload) >= 8 && string(payload[:6]) == "Exif\x00\x00" {
			return parseTIFFOrientation(payload[6:])
		}
		pos += 2 + segLen
	}
	return 1
}

func parseTIFFOrientation(tiff []byte) int {
	if len(tiff) < 8 {
		return 1
	}
	var order binary.ByteOrder = binary.LittleEndian
	switch string(tiff[:2]) {
	case "MM":
		order = binary.BigEndian
	case "II":
	default:
		return 1
	}
	if order.Uint16(tiff[2:4]) != 42 {
		return 1
	}
	ifd := int(order.Uint32(tiff[4:8]))
	if ifd < 8 || ifd+2 > len(tiff) {
		return 1
	}
	entries := int(order.Uint16(tiff[ifd : ifd+2]))
	for i := 0; i < entries; i++ {
		off := ifd + 2 + i*12
		if off+12 > len(tiff) {
			return 1
		}
		if order.Uint16(tiff[off:off+2]) != 0x0112 { // Orientation tag
			continue
		}
		// 规范上 Orientation 是 SHORT(3) 且 count=1；异常类型不做猜测。
		if order.Uint16(tiff[off+2:off+4]) != 3 || order.Uint32(tiff[off+4:off+8]) != 1 {
			return 1
		}
		// 值不超过 4 字节时按 TIFF 规范内联在条目 value 字段前部。
		value := int(order.Uint16(tiff[off+8 : off+10]))
		if value >= 1 && value <= 8 {
			return value
		}
		return 1
	}
	return 1
}

// applyEXIFOrientation 按 EXIF Orientation(1-8) 旋转/翻转像素，使位图存储
// 即为摆正后的样子；orientation 为 1 或不在 1-8 范围时原样返回。
func applyEXIFOrientation(src image.Image, orientation int) image.Image {
	b := src.Bounds()
	w, h := b.Dx(), b.Dy()
	newW, newH := w, h
	var toDst func(x, y int) (int, int)
	switch orientation {
	case 2: // 水平镜像：第 0 行仍是视觉顶部，左右颠倒
		toDst = func(x, y int) (int, int) { return w - 1 - x, y }
	case 3: // 旋转 180
		toDst = func(x, y int) (int, int) { return w - 1 - x, h - 1 - y }
	case 4: // 垂直镜像：第 0 行是视觉底部
		toDst = func(x, y int) (int, int) { return x, h - 1 - y }
	case 5: // 转置（沿主对角线翻转）：第 0 行是视觉左侧、第 0 列是视觉顶部
		toDst = func(x, y int) (int, int) { return y, x }
		newW, newH = h, w
	case 6: // 顺时针旋转 90：第 0 行是视觉右侧、第 0 列是视觉顶部
		toDst = func(x, y int) (int, int) { return h - 1 - y, x }
		newW, newH = h, w
	case 7: // 反转置（沿反对角线翻转）：第 0 行是视觉右侧、第 0 列是视觉底部
		toDst = func(x, y int) (int, int) { return h - 1 - y, w - 1 - x }
		newW, newH = h, w
	case 8: // 逆时针旋转 90：第 0 行是视觉左侧、第 0 列是视觉底部
		toDst = func(x, y int) (int, int) { return y, w - 1 - x }
		newW, newH = h, w
	default: // 1 或非法值
		return src
	}
	dst := image.NewRGBA(image.Rect(0, 0, newW, newH))
	for y := 0; y < h; y++ {
		for x := 0; x < w; x++ {
			dx, dy := toDst(x, y)
			dst.Set(dx, dy, src.At(b.Min.X+x, b.Min.Y+y))
		}
	}
	return dst
}

// 确保 png 编解码包注册
var _ = png.Decode
var _ = draw.Draw
