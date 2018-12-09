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
        load_cs("gradients.glsl".into()),
        shader_uniforms!(),
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

    rtoy.forever(|snapshot| {
        draw_fullscreen_texture(&*snapshot.get(blurred_tex));
    });
}
