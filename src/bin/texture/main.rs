use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();

    let tex = load_tex(asset!("images/cornell_box_render.jpg"));
    rtoy.draw_forever(|_| tex.clone());
}
