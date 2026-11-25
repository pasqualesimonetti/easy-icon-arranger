// Command appicon draws assets/appicon.png (1024x1024): a teal to blue squircle
// with a 3x3 grid of white tiles, one of them lifted in amber as if being
// dragged, rendered at 2x and scaled down for smooth edges.
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

// Brand colours, also used by the website (docs/index.html).
var (
	teal  = color.RGBA{20, 184, 166, 255} // #14B8A6
	blue  = color.RGBA{37, 99, 235, 255}  // #2563EB
	amber = color.RGBA{255, 176, 32, 255} // #FFB020
	white = color.RGBA{255, 255, 255, 255}
	ink   = color.RGBA{10, 30, 80, 255}
)

// rrect returns the coverage of a rounded rectangle at (x, y); soft > 1 blurs
// the edge over that many pixels (used for the shadow).
func rrect(x, y, x0, y0, x1, y1, r, soft float64) float64 {
	cx := math.Max(x0+r, math.Min(x, x1-r))
	cy := math.Max(y0+r, math.Min(y, y1-r))
	d := math.Hypot(x-cx, y-cy) - r
	if soft <= 1 {
		if x < x0 || x > x1 || y < y0 || y > y1 {
			return 0
		}
		return math.Max(0, math.Min(1, 0.5-d))
	}
	return math.Max(0, math.Min(1, 0.5-d/soft))
}

func blend(dst, src color.RGBA, a float64) color.RGBA {
	mix := func(d, s uint8) uint8 { return uint8(float64(d)*(1-a) + float64(s)*a + 0.5) }
	return color.RGBA{mix(dst.R, src.R), mix(dst.G, src.G), mix(dst.B, src.B), uint8(math.Max(float64(dst.A), a*255))}
}

func paint(img *image.RGBA, x0, y0, x1, y1, r, soft float64, c color.RGBA, alpha float64, clip func(x, y int) bool) {
	pad := soft * 2
	for y := int(y0 - pad); y <= int(y1+pad)+1; y++ {
		for x := int(x0 - pad); x <= int(x1+pad)+1; x++ {
			if x < 0 || y < 0 || x >= big || y >= big || (clip != nil && !clip(x, y)) {
				continue
			}
			a := rrect(float64(x)+0.5, float64(y)+0.5, x0, y0, x1, y1, r, soft) * alpha
			if a > 0 {
				img.SetRGBA(x, y, blend(img.RGBAAt(x, y), c, a))
			}
		}
	}
}

func main() {
	img := image.NewRGBA(image.Rect(0, 0, big, big))
	m := 0.1 * big // macOS icon margin
	inner := big - 2*m
	corner := 0.225 * inner
	inside := func(x, y int) bool { return rrect(float64(x)+0.5, float64(y)+0.5, m, m, big-m, big-m, corner, 0) > 0 }

	// background: diagonal teal (top left) to blue (bottom right)
	for y := 0; y < big; y++ {
		for x := 0; x < big; x++ {
			a := rrect(float64(x)+0.5, float64(y)+0.5, m, m, big-m, big-m, corner, 0)
			if a == 0 {
				continue
			}
			t := math.Max(0, math.Min(1, (float64(x)+float64(y)-2*m)/(2*inner)))
			t = t * t * (3 - 2*t)
			bg := color.RGBA{
				uint8(float64(teal.R)*(1-t) + float64(blue.R)*t),
				uint8(float64(teal.G)*(1-t) + float64(blue.G)*t),
				uint8(float64(teal.B)*(1-t) + float64(blue.B)*t), 255}
			img.SetRGBA(x, y, blend(color.RGBA{}, bg, a))
		}
	}

	pad := inner * 0.19
	gap := inner * 0.065
	tile := (inner - 2*pad - 2*gap) / 3
	tr := tile * 0.26
	pos := func(r, c int) (float64, float64) {
		return m + pad + float64(c)*(tile+gap), m + pad + float64(r)*(tile+gap)
	}
	for r := 0; r < 3; r++ {
		for c := 0; c < 3; c++ {
			x0, y0 := pos(r, c)
			if r == 2 && c == 2 {
				// the empty slot the amber tile was lifted from
				paint(img, x0, y0, x0+tile, y0+tile, tr, 0, white, 0.22, inside)
				continue
			}
			paint(img, x0, y0, x0+tile, y0+tile, tr, 0, white, 0.95, inside)
		}
	}
	// lifted amber tile: a little bigger, moved up and left, with a soft shadow
	x0, y0 := pos(2, 2)
	s := tile * 1.12
	cx, cy := x0+tile/2-tile*0.2, y0+tile/2-tile*0.2
	lx0, ly0 := cx-s/2, cy-s/2
	paint(img, lx0+tile*0.06, ly0+tile*0.14, lx0+s+tile*0.06, ly0+s+tile*0.14, tr*1.12, tile*0.16, ink, 0.35, inside)
	paint(img, lx0, ly0, lx0+s, ly0+s, tr*1.12, 0, amber, 1, inside)

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
