use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey::new(256, 256, Format::R16G16B16A16_SFLOAT);
    let mut time = const_f32(0f32).isolate();

    let gradients_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/gradients.glsl")),
        shader_uniforms!(time: time.clone()),
    );

    let mut t = 0.0f32;
    rtoy.draw_forever(|_| {
        t += 0.01;
        time.rebind(const_f32(t));
        gradients_tex.clone()
    });
}
