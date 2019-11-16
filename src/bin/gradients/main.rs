use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();

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

    rtoy.draw_forever(|_| gradients_tex.clone());
}
