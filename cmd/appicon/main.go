// Command appicon draws build/appicon.png (1024x1024): a 3x3 grid of rounded
// tiles on a gradient squircle, rendered at 2x and scaled down for smooth edges.
package main

import (
	"image"
	"image/color"
	"image/png"
	"log"
	"math"
	"os"

	"golang.org/x/image/draw"
)

const big = 2048

func roundedRectAlpha(x, y, x0, y0, x1, y1, r float64) float64 {
	cx := math.Max(x0+r, math.Min(x, x1-r))
	cy := math.Max(y0+r, math.Min(y, y1-r))
	d := math.Hypot(x-cx, y-cy)
	if x < x0 || x > x1 || y < y0 || y > y1 {
		return 0
	}
	return math.Max(0, math.Min(1, r-d+0.5))
}

func blend(dst color.RGBA, src color.RGBA, a float64) color.RGBA {
	mix := func(d, s uint8) uint8 { return uint8(float64(d)*(1-a) + float64(s)*a) }
	return color.RGBA{mix(dst.R, src.R), mix(dst.G, src.G), mix(dst.B, src.B), uint8(math.Max(float64(dst.A), a*255))}
}

func main() {
	img := image.NewRGBA(image.Rect(0, 0, big, big))
	m := 0.1 * big // macOS icon margin
	top := color.RGBA{56, 132, 255, 255}
	bottom := color.RGBA{94, 64, 214, 255}
	for y := 0; y < big; y++ {
		t := float64(y) / big
		bg := color.RGBA{
			uint8(float64(top.R)*(1-t) + float64(bottom.R)*t),
			uint8(float64(top.G)*(1-t) + float64(bottom.G)*t),
			uint8(float64(top.B)*(1-t) + float64(bottom.B)*t), 255}
		for x := 0; x < big; x++ {
			a := roundedRectAlpha(float64(x), float64(y), m, m, big-m, big-m, 0.225*(big-2*m))
			if a > 0 {
				img.SetRGBA(x, y, blend(color.RGBA{}, bg, a))
			}
		}
	}
	// 3x3 tiles, like a folder on the iPhone
	inner := big - 2*m
	pad := inner * 0.2
	gap := inner * 0.06
	tile := (inner - 2*pad - 2*gap) / 3
	white := color.RGBA{255, 255, 255, 255}
	for r := 0; r < 3; r++ {
		for c := 0; c < 3; c++ {
			x0 := m + pad + float64(c)*(tile+gap)
			y0 := m + pad + float64(r)*(tile+gap)
			alpha := 0.92
			if (r+c)%2 == 1 {
				alpha = 0.62
			}
			for y := int(y0); y < int(y0+tile)+1; y++ {
				for x := int(x0); x < int(x0+tile)+1; x++ {
					a := roundedRectAlpha(float64(x), float64(y), x0, y0, x0+tile, y0+tile, tile*0.24)
					if a > 0 {
						img.SetRGBA(x, y, blend(img.RGBAAt(x, y), white, a*alpha))
					}
				}
			}
		}
	}
	out := image.NewRGBA(image.Rect(0, 0, 1024, 1024))
	draw.CatmullRom.Scale(out, out.Bounds(), img, img.Bounds(), draw.Src, nil)
	f, err := os.Create("assets/appicon.png")
	if err != nil {
		log.Fatal(err)
	}
	defer f.Close()
	if err := png.Encode(f, out); err != nil {
		log.Fatal(err)
	}
}
