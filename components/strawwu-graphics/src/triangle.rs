//! Software triangle rasterizer for observable DXGI/D3D11→VK / wgl present evidence.
//! Produces real RGB pixels (PPM) without claiming host Mesa GPU pass-through.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy)]
pub struct Vertex2 {
    pub x: f32,
    pub y: f32,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub struct Rgb8 {
    pub r: u8,
    pub g: u8,
    pub b: u8,
}

impl Rgb8 {
    pub const fn new(r: u8, g: u8, b: u8) -> Self {
        Self { r, g, b }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Framebuffer {
    pub width: u32,
    pub height: u32,
    /// Packed RGB8 row-major.
    pub pixels: Vec<u8>,
}

impl Framebuffer {
    pub fn new(width: u32, height: u32, clear: Rgb8) -> Self {
        let n = (width as usize) * (height as usize) * 3;
        let mut pixels = vec![0u8; n];
        for px in pixels.chunks_exact_mut(3) {
            px[0] = clear.r;
            px[1] = clear.g;
            px[2] = clear.b;
        }
        Self {
            width,
            height,
            pixels,
        }
    }

    pub fn set_pixel(&mut self, x: i32, y: i32, color: Rgb8) {
        if x < 0 || y < 0 || x as u32 >= self.width || y as u32 >= self.height {
            return;
        }
        let idx = ((y as u32 * self.width + x as u32) * 3) as usize;
        self.pixels[idx] = color.r;
        self.pixels[idx + 1] = color.g;
        self.pixels[idx + 2] = color.b;
    }

    pub fn to_ppm(&self) -> Vec<u8> {
        let header = format!("P6\n{} {}\n255\n", self.width, self.height);
        let mut out = header.into_bytes();
        out.extend_from_slice(&self.pixels);
        out
    }

    /// Count pixels matching `color` exactly (used as triangle presence evidence).
    pub fn count_color(&self, color: Rgb8) -> u64 {
        let mut n = 0u64;
        for px in self.pixels.chunks_exact(3) {
            if px[0] == color.r && px[1] == color.g && px[2] == color.b {
                n += 1;
            }
        }
        n
    }
}

fn edge(ax: f32, ay: f32, bx: f32, by: f32, cx: f32, cy: f32) -> f32 {
    (cx - ax) * (by - ay) - (cy - ay) * (bx - ax)
}

/// Rasterize a filled triangle into `fb` using barycentric coverage.
pub fn fill_triangle(fb: &mut Framebuffer, a: Vertex2, b: Vertex2, c: Vertex2, color: Rgb8) {
    let min_x = a.x.min(b.x).min(c.x).floor() as i32;
    let max_x = a.x.max(b.x).max(c.x).ceil() as i32;
    let min_y = a.y.min(b.y).min(c.y).floor() as i32;
    let max_y = a.y.max(b.y).max(c.y).ceil() as i32;

    let area = edge(a.x, a.y, b.x, b.y, c.x, c.y);
    if area.abs() < f32::EPSILON {
        return;
    }

    for y in min_y..=max_y {
        for x in min_x..=max_x {
            let px = x as f32 + 0.5;
            let py = y as f32 + 0.5;
            let w0 = edge(b.x, b.y, c.x, c.y, px, py);
            let w1 = edge(c.x, c.y, a.x, a.y, px, py);
            let w2 = edge(a.x, a.y, b.x, b.y, px, py);
            let inside = if area > 0.0 {
                w0 >= 0.0 && w1 >= 0.0 && w2 >= 0.0
            } else {
                w0 <= 0.0 && w1 <= 0.0 && w2 <= 0.0
            };
            if inside {
                fb.set_pixel(x, y, color);
            }
        }
    }
}

/// Canonical GX0 demo triangle (centered-ish, pointing up).
pub fn demo_triangle_vertices(width: u32, height: u32) -> (Vertex2, Vertex2, Vertex2) {
    let w = width as f32;
    let h = height as f32;
    (
        Vertex2 {
            x: w * 0.50,
            y: h * 0.18,
        },
        Vertex2 {
            x: w * 0.18,
            y: h * 0.82,
        },
        Vertex2 {
            x: w * 0.82,
            y: h * 0.82,
        },
    )
}

pub const TRIANGLE_COLOR: Rgb8 = Rgb8::new(0xE6, 0x3B, 0x2E);
pub const CLEAR_COLOR: Rgb8 = Rgb8::new(0x1A, 0x1F, 0x2E);

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rasterizes_nonempty_triangle() {
        let mut fb = Framebuffer::new(64, 64, CLEAR_COLOR);
        let (a, b, c) = demo_triangle_vertices(64, 64);
        fill_triangle(&mut fb, a, b, c, TRIANGLE_COLOR);
        let n = fb.count_color(TRIANGLE_COLOR);
        assert!(n > 100, "expected filled triangle pixels, got {n}");
        let ppm = fb.to_ppm();
        assert!(ppm.starts_with(b"P6"));
    }
}
