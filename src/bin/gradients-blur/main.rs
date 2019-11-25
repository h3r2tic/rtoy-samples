use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey::new(256, 256, Format::R16G16B16A16_SFLOAT);

    let gradients_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/gradients.glsl")),
        shader_uniforms!(),
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

    rtoy.draw_forever(|_| blurred_tex.clone());
}
