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

type MaskRegion struct {
	X      float64 `json:"x"`      // 0.0 ~ 1.0 比例坐标
	Y      float64 `json:"y"`      // 0.0 ~ 1.0
	Width  float64 `json:"width"`  // 0.0 ~ 1.0
	Height float64 `json:"height"` // 0.0 ~ 1.0
	Type   string  `json:"type"`   // "mosaic" (默认) 或 "blur"
	// Points 非空时表示涂抹轨迹；X/Y/Width/Height 仍保留用于兼容旧版矩形打码。
	Points    []MaskPoint `json:"points,omitempty"`
	BrushSize float64     `json:"brush_size,omitempty"` // 相对于短边的笔刷直径
}

type MaskPoint struct {
	X float64 `json:"x"`
	Y float64 `json:"y"`
}

type ProcessedVariant struct {
	Variant   string // "thumb", "feed", "detail", "original", "censored_*"
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
	AppliedRegions int
	Thumb          ProcessedVariant
	Feed           ProcessedVariant
	Detail         ProcessedVariant
	Original       ProcessedVariant
}

// ProcessImage 真实解码图像源文件，剔除 EXIF/GPS 元数据并按分辨率生成
// thumb (<= 640px)、feed (宽 <= 1080px 且高 <= 1920px)、detail (<= 1440px) 与 original 变体。
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
	origVariant, err := encodeVariant(srcImg, origW, origH, "original", 92)
	if err != nil {
		return nil, fmt.Errorf("encode original variant: %w", err)
	}

	// 2. 生成 feed 变体：以 1080px 宽为目标，同时限制超长竖图高度，保持比例且不放大。
	feedW, feedH := calcFeedDimensions(origW, origH)
	var feedImg image.Image = srcImg
	if feedW != origW || feedH != origH {
		feedImg = resizeCatmullRom(srcImg, feedW, feedH)
	}
	feedVariant, err := encodeVariant(feedImg, feedW, feedH, "feed", 85)
	if err != nil {
		return nil, fmt.Errorf("encode feed variant: %w", err)
	}

	// 3. 生成 detail 变体（长边 <= 1440px）
	detailW, detailH := calcScaledDimensions(origW, origH, 1440)
	var detailImg image.Image = srcImg
	if detailW != origW || detailH != origH {
		detailImg = resizeCatmullRom(srcImg, detailW, detailH)
	}
	detailVariant, err := encodeVariant(detailImg, detailW, detailH, "detail", 90)
	if err != nil {
		return nil, fmt.Errorf("encode detail variant: %w", err)
	}

	// 4. 生成 thumb 变体（长边 <= 640px）
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
		Feed:           feedVariant,
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

func calcFeedDimensions(w, h int) (int, int) {
	const maxWidth = 1080
	const maxHeight = 1920
	if w <= maxWidth && h <= maxHeight {
		return w, h
	}
	scale := math.Min(float64(maxWidth)/float64(w), float64(maxHeight)/float64(h))
	if scale > 1 {
		scale = 1
	}
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

// ApplyMaskRegions 在图像上对指定的归一化比例区域应用马赛克或模糊效果。
func ApplyMaskRegions(src image.Image, regions []MaskRegion) image.Image {
	result, _ := applyMaskRegionsWithCount(src, regions)
	return result
}

func brushRadiusPixels(region MaskRegion, width, height int) float64 {
	size := region.BrushSize
	if size <= 0 {
		// 兼容没有 brush_size 的旧客户端，仍按可见且可处理的默认笔刷宽度执行。
		size = 0.04
	}
	return math.Max(2, size*float64(minInt(width, height))/2)
}

func minInt(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func brushBounds(region MaskRegion, width, height int) (int, int, int, int, float64, bool) {
	if len(region.Points) == 0 || width <= 0 || height <= 0 {
		return 0, 0, 0, 0, 0, false
	}
	radius := brushRadiusPixels(region, width, height)
	minX, minY := float64(width), float64(height)
	maxX, maxY := 0.0, 0.0
	for _, point := range region.Points {
		if point.X < minX {
			minX = point.X
		}
		if point.Y < minY {
			minY = point.Y
		}
		if point.X > maxX {
			maxX = point.X
		}
		if point.Y > maxY {
			maxY = point.Y
		}
	}
	minX = minX*float64(width) - radius
	minY = minY*float64(height) - radius
	maxX = maxX*float64(width) + radius
	maxY = maxY*float64(height) + radius
	left := int(math.Floor(math.Max(0, minX)))
	top := int(math.Floor(math.Max(0, minY)))
	right := int(math.Ceil(math.Min(float64(width), maxX)))
	bottom := int(math.Ceil(math.Min(float64(height), maxY)))
	if left >= right || top >= bottom {
		return 0, 0, 0, 0, radius, false
	}
	return left, top, right, bottom, radius, true
}

func pointDistanceSquared(px, py, ax, ay, bx, by float64) float64 {
	dx, dy := bx-ax, by-ay
	if dx == 0 && dy == 0 {
		dx, dy = px-ax, py-ay
		return dx*dx + dy*dy
	}
	t := ((px-ax)*dx + (py-ay)*dy) / (dx*dx + dy*dy)
	if t < 0 {
		t = 0
	} else if t > 1 {
		t = 1
	}
	x, y := ax+t*dx, ay+t*dy
	dx, dy = px-x, py-y
	return dx*dx + dy*dy
}

func pointInBrush(region MaskRegion, x, y, width, height int, radius float64) bool {
	px, py := float64(x)+0.5, float64(y)+0.5
	for i, point := range region.Points {
		ax, ay := point.X*float64(width), point.Y*float64(height)
		if i == 0 {
			if pointDistanceSquared(px, py, ax, ay, ax, ay) <= radius*radius {
				return true
			}
			continue
		}
		previous := region.Points[i-1]
		bx, by := previous.X*float64(width), previous.Y*float64(height)
		if pointDistanceSquared(px, py, ax, ay, bx, by) <= radius*radius {
			return true
		}
	}
	return false
}

func applyBrushRegion(dst *image.RGBA, region MaskRegion, width, height int) bool {
	minX, minY, maxX, maxY, radius, ok := brushBounds(region, width, height)
	if !ok {
		return false
	}
	if region.Type == "blur" {
		return applyBlurRegion(dst, region, minX, minY, maxX, maxY, radius)
	}
	return applyMosaicBrushRegion(dst, region, minX, minY, maxX, maxY, radius)
}

func applyMosaicBrushRegion(dst *image.RGBA, region MaskRegion, minX, minY, maxX, maxY int, radius float64) bool {
	width, height := dst.Bounds().Dx(), dst.Bounds().Dy()
	blockSize := int(math.Max(8, float64(width+height)/100.0))
	applied := false
	for by := minY; by < maxY; by += blockSize {
		for bx := minX; bx < maxX; bx += blockSize {
			bMaxX := minInt(bx+blockSize, maxX)
			bMaxY := minInt(by+blockSize, maxY)
			var rSum, gSum, bSum, aSum, count uint32
			for py := by; py < bMaxY; py++ {
				for px := bx; px < bMaxX; px++ {
					r, g, b, a := dst.RGBAAt(px, py).RGBA()
					rSum += r >> 8
					gSum += g >> 8
					bSum += b >> 8
					aSum += a >> 8
					count++
				}
			}
			if count == 0 {
				continue
			}
			avgColor := color.RGBA{
				R: uint8(rSum / count), G: uint8(gSum / count),
				B: uint8(bSum / count), A: uint8(aSum / count),
			}
			for py := by; py < bMaxY; py++ {
				for px := bx; px < bMaxX; px++ {
					if pointInBrush(region, px, py, width, height, radius) {
						dst.SetRGBA(px, py, avgColor)
						applied = true
					}
				}
			}
		}
	}
	return applied
}

func applyBlurRegion(dst *image.RGBA, region MaskRegion, minX, minY, maxX, maxY int, radius float64) bool {
	width, height := dst.Bounds().Dx(), dst.Bounds().Dy()
	kernel := int(math.Max(4, radius))
	temp := image.NewRGBA(image.Rect(minX, minY, maxX, maxY))
	for y := minY; y < maxY; y++ {
		for x := minX; x < maxX; x++ {
			var rSum, gSum, bSum, aSum, count uint32
			for kx := x - kernel; kx <= x+kernel; kx++ {
				sampleX := kx
				if sampleX < 0 {
					sampleX = 0
				} else if sampleX >= width {
					sampleX = width - 1
				}
				r, g, b, a := dst.RGBAAt(sampleX, y).RGBA()
				rSum += r >> 8
				gSum += g >> 8
				bSum += b >> 8
				aSum += a >> 8
				count++
			}
			temp.SetRGBA(x, y, color.RGBA{R: uint8(rSum / count), G: uint8(gSum / count), B: uint8(bSum / count), A: uint8(aSum / count)})
		}
	}
	applied := false
	for y := minY; y < maxY; y++ {
		for x := minX; x < maxX; x++ {
			if !pointInBrush(region, x, y, width, height, radius) {
				continue
			}
			var rSum, gSum, bSum, aSum, count uint32
			for ky := y - kernel; ky <= y+kernel; ky++ {
				sampleY := ky
				if sampleY < 0 {
					sampleY = 0
				} else if sampleY >= height {
					sampleY = height - 1
				}
				var r, g, b, a uint32
				if sampleY >= minY && sampleY < maxY {
					c := temp.RGBAAt(x, sampleY)
					r, g, b, a = uint32(c.R), uint32(c.G), uint32(c.B), uint32(c.A)
				} else {
					c := dst.RGBAAt(x, sampleY)
					r, g, b, a = uint32(c.R), uint32(c.G), uint32(c.B), uint32(c.A)
				}
				rSum += r
				gSum += g
				bSum += b
				aSum += a
				count++
			}
			dst.SetRGBA(x, y, color.RGBA{R: uint8(rSum / count), G: uint8(gSum / count), B: uint8(bSum / count), A: uint8(aSum / count)})
			applied = true
		}
	}
	return applied
}

// applyMaskRegionsWithCount 同时返回真正落到像素上的区域数量。
// 坐标合法并不代表在极小图片上一定能形成一个像素宽高的区域，因此审核
// 流程不能只依赖请求中的 regions 数量判断“已经打码”。
func applyMaskRegionsWithCount(src image.Image, regions []MaskRegion) (image.Image, int) {
	if len(regions) == 0 {
		return src, 0
	}
	bounds := src.Bounds()
	w, h := bounds.Dx(), bounds.Dy()
	if w <= 0 || h <= 0 {
		return src, 0
	}
	appliedRegions := 0

	// 复制到 RGBA 画布进行像素级处理
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	draw.Draw(dst, dst.Bounds(), src, bounds.Min, draw.Src)

	for _, region := range regions {
		if len(region.Points) > 0 {
			if applyBrushRegion(dst, region, w, h) {
				appliedRegions++
			}
			continue
		}
		// 校验并限制归一化坐标范围 [0.0, 1.0]
		rx := math.Max(0.0, math.Min(1.0, region.X))
		ry := math.Max(0.0, math.Min(1.0, region.Y))
		rw := math.Max(0.0, math.Min(1.0-rx, region.Width))
		rh := math.Max(0.0, math.Min(1.0-ry, region.Height))
		if rw <= 0 || rh <= 0 {
			continue
		}

		minX := int(math.Round(rx * float64(w)))
		minY := int(math.Round(ry * float64(h)))
		maxX := int(math.Round((rx + rw) * float64(w)))
		maxY := int(math.Round((ry + rh) * float64(h)))

		if minX >= maxX || minY >= maxY {
			continue
		}
		if minX < 0 {
			minX = 0
		}
		if minY < 0 {
			minY = 0
		}
		if maxX > w {
			maxX = w
		}
		if maxY > h {
			maxY = h
		}
		if minX >= maxX || minY >= maxY {
			continue
		}
		appliedRegions++

		if region.Type == "blur" {
			// 区域高斯/盒式模糊：根据图像分辨率动态计算模糊核半宽
			radius := int(math.Max(4, float64(w+h)/160.0))
			temp := image.NewRGBA(image.Rect(minX, minY, maxX, maxY))
			// 水平模糊
			for y := minY; y < maxY; y++ {
				for x := minX; x < maxX; x++ {
					var rSum, gSum, bSum, aSum, count uint32
					for kx := x - radius; kx <= x+radius; kx++ {
						sampleX := kx
						if sampleX < 0 {
							sampleX = 0
						}
						if sampleX >= w {
							sampleX = w - 1
						}
						r, g, b, a := dst.RGBAAt(sampleX, y).RGBA()
						rSum += r >> 8
						gSum += g >> 8
						bSum += b >> 8
						aSum += a >> 8
						count++
					}
					temp.SetRGBA(x, y, color.RGBA{
						R: uint8(rSum / count),
						G: uint8(gSum / count),
						B: uint8(bSum / count),
						A: uint8(aSum / count),
					})
				}
			}
			// 垂直模糊写回
			for y := minY; y < maxY; y++ {
				for x := minX; x < maxX; x++ {
					var rSum, gSum, bSum, aSum, count uint32
					for ky := y - radius; ky <= y+radius; ky++ {
						sampleY := ky
						if sampleY < 0 {
							sampleY = 0
						}
						if sampleY >= h {
							sampleY = h - 1
						}
						var r, g, b, a uint32
						if sampleY >= minY && sampleY < maxY {
							c := temp.RGBAAt(x, sampleY)
							r, g, b, a = uint32(c.R), uint32(c.G), uint32(c.B), uint32(c.A)
						} else {
							c := dst.RGBAAt(x, sampleY)
							r, g, b, a = uint32(c.R), uint32(c.G), uint32(c.B), uint32(c.A)
						}
						rSum += r
						gSum += g
						bSum += b
						aSum += a
						count++
					}
					dst.SetRGBA(x, y, color.RGBA{
						R: uint8(rSum / count),
						G: uint8(gSum / count),
						B: uint8(bSum / count),
						A: uint8(aSum / count),
					})
				}
			}
		} else {
			// 默认马赛克效果：根据图像尺寸自适应马赛克方块大小
			blockSize := int(math.Max(8, float64(w+h)/100.0))
			for by := minY; by < maxY; by += blockSize {
				for bx := minX; bx < maxX; bx += blockSize {
					bMaxX := bx + blockSize
					if bMaxX > maxX {
						bMaxX = maxX
					}
					bMaxY := by + blockSize
					if bMaxY > maxY {
						bMaxY = maxY
					}

					var rSum, gSum, bSum, aSum, count uint32
					for py := by; py < bMaxY; py++ {
						for px := bx; px < bMaxX; px++ {
							r, g, b, a := dst.RGBAAt(px, py).RGBA()
							rSum += r >> 8
							gSum += g >> 8
							bSum += b >> 8
							aSum += a >> 8
							count++
						}
					}
					if count == 0 {
						continue
					}
					avgColor := color.RGBA{
						R: uint8(rSum / count),
						G: uint8(gSum / count),
						B: uint8(bSum / count),
						A: uint8(aSum / count),
					}
					for py := by; py < bMaxY; py++ {
						for px := bx; px < bMaxX; px++ {
							dst.SetRGBA(px, py, avgColor)
						}
					}
				}
			}
		}
	}
	return dst, appliedRegions
}

// maxCensoredImagePixels 限制打码处理的像素总量。全量解码一张 40MP 图片的
// RGBA 缓冲峰值约 160MB，超过阈值直接拒绝，避免审核接口被超大图拖垮。
const maxCensoredImagePixels = 40_000_000

// ProcessCensoredImage 对原图源数据应用打码区域后，重新生成打码版 thumb、detail、original 衍生图
func ProcessCensoredImage(r io.Reader, regions []MaskRegion) (*ProcessResult, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, fmt.Errorf("read source image data: %w", err)
	}
	return ProcessCensoredImageBytes(data, regions)
}

// ProcessCensoredImageBytes 对已读取的图片字节数据应用打码区域，避免重复复制
func ProcessCensoredImageBytes(data []byte, regions []MaskRegion) (*ProcessResult, error) {
	if len(data) == 0 {
		return nil, fmt.Errorf("empty image data")
	}

	// 只解码图片头拿声明尺寸，在全量解码前拦下超大图。
	cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("decode image config: %w", err)
	}
	if cfg.Width <= 0 || cfg.Height <= 0 {
		return nil, fmt.Errorf("invalid image dimensions: %dx%d", cfg.Width, cfg.Height)
	}
	if int64(cfg.Width)*int64(cfg.Height) > maxCensoredImagePixels {
		return nil, fmt.Errorf("image dimensions %dx%d exceed censored processing limit (%d pixels)", cfg.Width, cfg.Height, maxCensoredImagePixels)
	}

	srcImg, format, err := image.Decode(bytes.NewReader(data))
	if err != nil {
		return nil, fmt.Errorf("decode image (%s): %w", format, err)
	}
	srcImg = applyEXIFOrientation(srcImg, readEXIFOrientation(data))

	// 对原尺寸图像应用打码区域
	censoredImg, appliedRegions := applyMaskRegionsWithCount(srcImg, regions)
	if appliedRegions == 0 {
		return nil, fmt.Errorf("mask regions did not cover any pixels")
	}

	bounds := censoredImg.Bounds()
	origW := bounds.Dx()
	origH := bounds.Dy()
	if origW <= 0 || origH <= 0 {
		return nil, fmt.Errorf("invalid image dimensions: %dx%d", origW, origH)
	}

	// 1. 生成 censored_original
	origVariant, err := encodeVariant(censoredImg, origW, origH, "censored_original", 92)
	if err != nil {
		return nil, fmt.Errorf("encode censored original variant: %w", err)
	}

	// 2. 生成 censored_feed，使用与普通 feed 相同的宽度/高度约束。
	feedW, feedH := calcFeedDimensions(origW, origH)
	var feedImg image.Image = censoredImg
	if feedW != origW || feedH != origH {
		feedImg = resizeCatmullRom(censoredImg, feedW, feedH)
	}
	feedVariant, err := encodeVariant(feedImg, feedW, feedH, "censored_feed", 85)
	if err != nil {
		return nil, fmt.Errorf("encode censored feed variant: %w", err)
	}

	// 3. 生成 censored_detail (长边 <= 1440px)
	detailW, detailH := calcScaledDimensions(origW, origH, 1440)
	var detailImg image.Image = censoredImg
	if detailW != origW || detailH != origH {
		detailImg = resizeCatmullRom(censoredImg, detailW, detailH)
	}
	detailVariant, err := encodeVariant(detailImg, detailW, detailH, "censored_detail", 90)
	if err != nil {
		return nil, fmt.Errorf("encode censored detail variant: %w", err)
	}

	// 4. 生成 censored_thumb (长边 <= 640px)
	thumbW, thumbH := calcScaledDimensions(origW, origH, 640)
	var thumbImg image.Image = censoredImg
	if thumbW != origW || thumbH != origH {
		thumbImg = resizeCatmullRom(censoredImg, thumbW, thumbH)
	}
	thumbVariant, err := encodeVariant(thumbImg, thumbW, thumbH, "censored_thumb", 80)
	if err != nil {
		return nil, fmt.Errorf("encode censored thumb variant: %w", err)
	}

	return &ProcessResult{
		OriginalWidth:  origW,
		OriginalHeight: origH,
		SourceMimeType: "image/" + format,
		AppliedRegions: appliedRegions,
		Thumb:          thumbVariant,
		Feed:           feedVariant,
		Detail:         detailVariant,
		Original:       origVariant,
	}, nil
}

// 确保 png 编解码包注册
var _ = png.Decode
var _ = draw.Draw
