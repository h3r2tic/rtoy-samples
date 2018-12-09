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

    rtoy.forever(|snapshot| {
        draw_fullscreen_texture(&*snapshot.get(gradients_tex));
    });
}
