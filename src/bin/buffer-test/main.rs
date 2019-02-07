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
        load_cs(asset!("shaders/buffer_test.glsl")),
        shader_uniforms!(
            "buf0": upload_buffer(to_byte_vec(vec![0.04f32, 0.3f32, 0.8f32, 0.0f32])),
            "buf1": upload_buffer(to_byte_vec(vec![0.5f32, 0.5f32])),
        ),
    );

    rtoy.forever(|snapshot, _frame_state| {
        draw_fullscreen_texture(&*snapshot.get(gradients_tex));
    });
}
