use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey::new(rtoy.width(), rtoy.height(), Format::R32G32B32A32_SFLOAT);

    let scene = vec![
        (
            load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0),
            Vec3::new(-300.0, 0.0, 0.0),
            Quat::identity(),
        ),
        (
            load_gltf_scene(asset!("meshes/dredd/scene.gltf"), 5.0),
            Vec3::new(300.0, 0.0, 0.0),
            Quat::identity(),
        ),
    ];

    let mut camera = FirstPersonCamera::new(Vec3::new(0.0, 100.0, 500.0));

    let mut viewport_constants_buf = upload_buffer(0u32).isolate();

    let out_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_simple_ps.glsl")),
        ]),
        shader_uniforms!(
            constants: viewport_constants_buf.clone(),
            :upload_raster_scene(&scene),
        ),
    );

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height).build();

        viewport_constants_buf.rebind(upload_buffer(view_constants));

        out_tex.clone()
    });
}
