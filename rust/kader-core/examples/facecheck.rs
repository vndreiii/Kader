//! Developer check: runs YuNet + SFace on raw RGB files and prints results.
//!   facecheck <yunet.onnx> <sface.onnx> <manifest>
//! manifest lines: "<file.rgb> <width> <height>"; output lines:
//!   "<file> <x> <y> <w> <h> <score> <10 landmarks> <128 embedding values>"
use kader_core::face::{align, Detector, Recognizer, RgbImage};
use std::time::Instant;

fn main() {
    let a: Vec<String> = std::env::args().collect();
    let det = Detector::load(&std::fs::read(&a[1]).unwrap()).unwrap();
    let rec = Recognizer::load(&std::fs::read(&a[2]).unwrap()).unwrap();
    let (mut td, mut te, mut nf) = (0.0, 0.0, 0);
    for line in std::fs::read_to_string(&a[3]).unwrap().lines() {
        let p: Vec<&str> = line.split_whitespace().collect();
        let (w, h): (usize, usize) = (p[1].parse().unwrap(), p[2].parse().unwrap());
        let img = RgbImage::from_strided(&std::fs::read(p[0]).unwrap(), w, h, w * 3).unwrap();
        let t = Instant::now();
        let faces = det.detect(&img, 640, 0.6, 0.3).unwrap();
        td += t.elapsed().as_secs_f64();
        for f in faces {
            let t = Instant::now();
            let e = rec.embed(&align(&img, &f)).unwrap();
            te += t.elapsed().as_secs_f64();
            nf += 1;
            let mut s = format!("{} {} {} {} {} {}", p[0], f.x, f.y, f.w, f.h, f.score);
            for v in f.landmarks.iter().chain(e.iter()) {
                s += &format!(" {v}");
            }
            println!("{s}");
        }
    }
    eprintln!(
        "detect {:.1} ms/img, embed {:.1} ms/face",
        td * 1000.0 / std::fs::read_to_string(&a[3]).unwrap().lines().count() as f64,
        te * 1000.0 / nf.max(1) as f64
    );
}
