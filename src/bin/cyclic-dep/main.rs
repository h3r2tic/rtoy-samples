use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();

    let mut time = const_f32(0f32).isolate();
    let tex_key = TextureKey::new(256, 256, Format::R16G16B16A16_SFLOAT);

    let mut tex0 = load_tex(asset!("rendertoy::images/black.png")).isolate();
    let mut tex1 = load_tex(asset!("rendertoy::images/black.png")).isolate();

    tex0.rebind(compute_tex!(
        "fizz",
        tex_key,
        #tex: tex1.prev(),
        .rgb = vec3(float(fract(pix.x / 256.0 + #time)), 1.0 - @tex.y, 0.0)
    ));

    tex1.rebind(compute_tex!(
        "buzz",
        tex_key,
        #tex: tex0.prev(),
        .rgb = vec3(float(fract(pix.x / 256.0 + #time)), 1.0 - @tex.y, 0.0)
    ));

    let tex_diff = compute_tex!(
        "diff",
        tex_key,
        .rgb = vec3(0.0, abs(@tex0 - @tex1).y, 0.0)
    );

    let mut t = 0.0f32;
    rtoy.draw_forever(|_frame_state| {
        t += 0.01;
        time.rebind(const_f32(t));
        tex_diff.clone()
    });
}
