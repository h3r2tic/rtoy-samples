use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let time_asset = init_named!("Time", const_f32(0f32));

    let tex_key = TextureKey {
        width: 256,
        height: 256,
        format: gl::RGBA16F,
    };

    let gradients_tex = compute_tex(
        tex_key,
        load_cs("gradients.glsl".into()),
        shader_uniforms!("time": time_asset),
    );

    let blurred_tex = compute_tex(
        tex_key,
        load_cs("blur.glsl".into()),
        shader_uniforms!(
            "inputImage": gradients_tex,
            "blurRadius": 4,
            "blurDir": (0i32, 3i32)
        ),
    );

    let temporal_tex = init_named!("Temporal texture", load_tex("black.png".into()));
    redef_named!(
        temporal_tex,
        compute_tex(
            tex_key,
            load_cs("blend.glsl".into()),
            shader_uniforms!(
                "inputTex1": temporal_tex,
                "inputTex2": blurred_tex,
                "blendAmount": 0.1f32,
            )
        )
    );

    let mut t = 0.0f32;
    rtoy.forever(|snapshot| {
        draw_fullscreen_texture(&*snapshot.get(temporal_tex));
        t += 0.01;
        redef_named!(time_asset, const_f32(t));
    });
}
