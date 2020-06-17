use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();

    let mut mouse_x = const_f32(0f32).isolate();

    let tex_key = TextureKey::fullscreen(&rtoy, Format::R32G32B32A32_SFLOAT);

    let tex = compute_tex!(
        "EV shift",
        tex_key,
        #tex: load_tex(asset!("images/cornell_box_render.jpg")),
        //#tex: load_tex(asset!("images/living_room.hdr")),
        .rgb = @tex.rgb * exp((#mouse_x - 0.5) * 20.0)
    );

    let orig_lum_tex = compute_tex(
        tex_key.with_format(Format::R32G32_SFLOAT),
        load_cs(asset!("shaders/extract_log_luminance.glsl")),
        shader_uniforms!(inputTex: tex.clone(),),
    );

    let mut lum_tex = orig_lum_tex.clone();

    for i in 0..7 {
        lum_tex = compute_tex(
            tex_key.with_format(Format::R32G32_SFLOAT),
            load_cs(asset!("shaders/luminance-a-trous.glsl")),
            shader_uniforms!(
                inputTex: lum_tex,
                origInputTex: orig_lum_tex.clone(),
                px_skip: 1 << (6-i),
            ),
        );
    }

    let tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/local_tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: tex,
            filteredLogLumTex: lum_tex,
            sharpen_amount: 0.4f32,
        ),
    );

    let window_width = rtoy.width();

    rtoy.draw_forever(|frame_state| {
        mouse_x.rebind(const_f32(frame_state.mouse.pos.x / window_width as f32));
        tex.clone()
    });
}
