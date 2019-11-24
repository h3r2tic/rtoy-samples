use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey::new(256, 256, Format::R16G16B16A16_SFLOAT);

    let gradients_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/gradients.glsl")),
        shader_uniforms!(),
    );

    rtoy.draw_forever(|_| gradients_tex.clone());
}
