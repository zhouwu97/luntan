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
		detailImg = ResizeBilinear(srcImg, detailW, detailH)
	}
	detailVariant, err := encodeVariant(detailImg, detailW, detailH, "detail", 85)
	if err != nil {
		return nil, fmt.Errorf("encode detail variant: %w", err)
	}

	// 3. 生成 thumb 变体（长边 <= 640px）
	thumbW, thumbH := calcScaledDimensions(origW, origH, 640)
	var thumbImg image.Image = srcImg
	if thumbW != origW || thumbH != origH {
		thumbImg = ResizeBilinear(srcImg, thumbW, thumbH)
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

// ResizeBilinear 纯 Go 高质量双线性插值缩放算法，无 CGo 依赖
func ResizeBilinear(src image.Image, dstW, dstH int) *image.RGBA {
	srcBounds := src.Bounds()
	srcW := srcBounds.Dx()
	srcH := srcBounds.Dy()
	dst := image.NewRGBA(image.Rect(0, 0, dstW, dstH))

	if dstW <= 0 || dstH <= 0 || srcW <= 0 || srcH <= 0 {
		return dst
	}

	xRatio := float64(srcW) / float64(dstW)
	yRatio := float64(srcH) / float64(dstH)

	for y := 0; y < dstH; y++ {
		srcY := (float64(y)+0.5)*yRatio - 0.5
		y0 := int(math.Floor(srcY))
		y1 := y0 + 1
		yWeight := srcY - float64(y0)

		if y0 < 0 {
			y0 = 0
		}
		if y1 >= srcH {
			y1 = srcH - 1
		}

		for x := 0; x < dstW; x++ {
			srcX := (float64(x)+0.5)*xRatio - 0.5
			x0 := int(math.Floor(srcX))
			x1 := x0 + 1
			xWeight := srcX - float64(x0)

			if x0 < 0 {
				x0 = 0
			}
			if x1 >= srcW {
				x1 = srcW - 1
			}

			c00 := toRGBA(src.At(srcBounds.Min.X+x0, srcBounds.Min.Y+y0))
			c10 := toRGBA(src.At(srcBounds.Min.X+x1, srcBounds.Min.Y+y0))
			c01 := toRGBA(src.At(srcBounds.Min.X+x0, srcBounds.Min.Y+y1))
			c11 := toRGBA(src.At(srcBounds.Min.X+x1, srcBounds.Min.Y+y1))

			// 插值顶部与底部
			topR := float64(c00.R)*(1-xWeight) + float64(c10.R)*xWeight
			topG := float64(c00.G)*(1-xWeight) + float64(c10.G)*xWeight
			topB := float64(c00.B)*(1-xWeight) + float64(c10.B)*xWeight
			topA := float64(c00.A)*(1-xWeight) + float64(c10.A)*xWeight

			botR := float64(c01.R)*(1-xWeight) + float64(c11.R)*xWeight
			botG := float64(c01.G)*(1-xWeight) + float64(c11.G)*xWeight
			botB := float64(c01.B)*(1-xWeight) + float64(c11.B)*xWeight
			botA := float64(c01.A)*(1-xWeight) + float64(c11.A)*xWeight

			r := clamp(topR*(1-yWeight) + botR*yWeight)
			g := clamp(topG*(1-yWeight) + botG*yWeight)
			b := clamp(topB*(1-yWeight) + botB*yWeight)
			a := clamp(topA*(1-yWeight) + botA*yWeight)

			offset := (y*dstW + x) * 4
			dst.Pix[offset] = r
			dst.Pix[offset+1] = g
			dst.Pix[offset+2] = b
			dst.Pix[offset+3] = a
		}
	}
	return dst
}

func toRGBA(c color.Color) color.RGBA {
	r, g, b, a := c.RGBA()
	return color.RGBA{
		R: uint8(r >> 8),
		G: uint8(g >> 8),
		B: uint8(b >> 8),
		A: uint8(a >> 8),
	}
}

func clamp(v float64) uint8 {
	if v < 0 {
		return 0
	}
	if v > 255 {
		return 255
	}
	return uint8(v + 0.5)
}

// 确保 png 编解码包注册
var _ = png.Decode
var _ = draw.Draw
