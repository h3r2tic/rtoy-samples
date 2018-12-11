use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let blurred_tex = load_tex(asset!("images/cornell_box_render.jpg"));

    rtoy.forever(|snapshot| {
        draw_fullscreen_texture(&*snapshot.get(blurred_tex));
    });
}
