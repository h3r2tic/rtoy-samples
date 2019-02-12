use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: 256,
        height: 256,
        format: gl::RGBA16F,
    };

    let gradients_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/gradients.glsl")),
        shader_uniforms!(),
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

    rtoy.forever(|snapshot, _frame_state| {
        draw_fullscreen_texture(&*snapshot.get(blurred_tex));
    });
}
