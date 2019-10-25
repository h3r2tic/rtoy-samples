use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let time_asset = init_dynamic!(const_f32(0f32));

    let tex_key = TextureKey {
        width: 256,
        height: 256,
        format: gl::RGBA16F,
    };

    let gradients_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/gradients.glsl")),
        shader_uniforms!("time": time_asset.clone()),
    );

    let blurred_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/blur.glsl")),
        shader_uniforms!(
            "inputImage": gradients_tex,
            "blurRadius": 4,
            "blurDir": (0i32, 3i32)
        ),
    );

    let temporal_tex = init_dynamic!(load_tex(asset!("rendertoy::images/black.png")));

    redef_dynamic!(
        temporal_tex,
        compute_tex(
            tex_key,
            load_cs(asset!("shaders/blend.glsl")),
            shader_uniforms!(
                "inputTex1": temporal_tex.clone(),
                "inputTex2": blurred_tex,
                "blendAmount": 0.1f32,
            )
        )
    );

    let mut t = 0.0f32;
    rtoy.draw_forever(|_frame_state| {
        t += 0.01;
        redef_dynamic!(time_asset, const_f32(t));
        temporal_tex.clone()
    });
}
