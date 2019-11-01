use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    let mesh0 = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);
    let mesh1 = load_gltf_scene(asset!("meshes/dredd/scene.gltf"), 5.0);

    let scene = vec![
        shader_uniform_bundle!(
            instance_transform: raster_mesh_transform(Vector3::new(-300.0, 0.0, 0.0), UnitQuaternion::identity()),
            :upload_raster_mesh(make_raster_mesh(mesh0))),
        shader_uniform_bundle!(
            instance_transform: raster_mesh_transform(Vector3::new(300.0, 0.0, 0.0), UnitQuaternion::identity()),
            :upload_raster_mesh(make_raster_mesh(mesh1))),
    ];

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0));

    let mut viewport_constants_buf = upload_buffer(0u32).into_named();

    let out_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_simple_ps.glsl")),
        ]),
        shader_uniforms!(
            constants: viewport_constants_buf.clone(),
            :scene,
        ),
    );

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        let viewport_constants =
            ViewportConstants::build(&camera, tex_key.width, tex_key.height).finish();

        viewport_constants_buf.rebind(upload_buffer(viewport_constants));

        out_tex.clone()
    });
}
