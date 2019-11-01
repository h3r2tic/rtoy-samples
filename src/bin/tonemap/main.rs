use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let mut mouse_x = const_f32(0f32).into_named();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    let tex = compute_tex!(
        "EV shift",
        tex_key,
        #tex: load_tex(asset!("images/cornell_box_render.jpg")),
        .rgb = @tex.rgb * exp((#mouse_x - 0.5) * 8.0)
    );

    let tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: tex,
            sharpen_amount: 0.4f32,
        ),
    );

    let window_width = rtoy.width();

    rtoy.draw_forever(|frame_state| {
        mouse_x.rebind(const_f32(frame_state.mouse.pos.x / window_width as f32));
        tex.clone()
    });
}
