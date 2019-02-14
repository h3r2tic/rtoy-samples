use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex = load_tex(asset!("images/cornell_box_render.jpg"));

    rtoy.forever(|snapshot, frame_state| {
        draw_fullscreen_texture(&*snapshot.get(tex), frame_state.window_size_pixels);
    });
}
