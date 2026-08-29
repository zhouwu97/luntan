package media

import (
	"bytes"
	"crypto/sha256"
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

// 确保 png 编解码包注册
var _ = png.Decode
var _ = draw.Draw
