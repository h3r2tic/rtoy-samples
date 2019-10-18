use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let mouse_x = init_dynamic!(const_f32(0f32));

    let tex = load_tex(asset!("images/cornell_box_render.jpg"));
    //let tex = load_tex(asset!("images/KodakTestImage28-web.jpg"));

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    let tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/multiply.glsl")),
        shader_uniforms!(
            "inputTex": tex,
            "factor": mouse_x,
        ),
    );

    let tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            "inputTex": tex,
            "constants": init_dynamic!(upload_buffer(0.4f32)),
        ),
    );

    let window_width = rtoy.width();

    rtoy.draw_forever(|frame_state| {
        redef_dynamic!(mouse_x, const_f32(frame_state.mouse.pos.x / window_width as f32 * 10.0));

        tex
    });
}
