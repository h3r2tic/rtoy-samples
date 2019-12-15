use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();

    let mut time = const_f32(0f32).isolate();
    let tex_key = TextureKey::new(256, 256, Format::R16G16B16A16_SFLOAT);

    let gradients_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/gradients.glsl")),
        shader_uniforms!(time: time.clone()),
    );

    let blurred_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/blur.glsl")),
        shader_uniforms!(
            inputImage: gradients_tex,
            blurRadius: 4,
            blurDir: (0i32, 3i32)
        ),
    );

    let mut temporal_tex = load_tex(asset!("rendertoy::images/black.png")).isolate();

    temporal_tex.rebind(compute_tex(
        tex_key,
        load_cs(asset!("shaders/blend.glsl")),
        shader_uniforms!(
            inputTex1: temporal_tex.prev(),
            inputTex2: blurred_tex,
            blendAmount: 0.02f32,
        ),
    ));

    let mut t = 0.0f32;
    rtoy.draw_forever(|_frame_state| {
        t += 0.01;
        time.rebind(const_f32(t));
        temporal_tex.clone()
    });
}
