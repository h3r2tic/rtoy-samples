use rendertoy::*;

fn main() {
    let rtoy = Rendertoy::new();
    let tex_key = TextureKey::fullscreen(&rtoy, Format::R32G32B32A32_SFLOAT);

    let mesh = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);
    let scene = vec![(mesh.clone(), Vector3::zeros(), UnitQuaternion::identity())];

    let mut camera =
        CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0)));

    let mut raster_constants_buf = upload_buffer(0u32).isolate();

    let gbuffer_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
        ]),
        shader_uniforms!(
            constants: raster_constants_buf.clone(),
            :upload_raster_scene(&scene)
        ),
    );

    let mut ssao = rtoy_samples::ssao::Ssao::new(tex_key, gbuffer_tex);

    let out_tex = compute_tex!(
        "splat red to rgb",
        tex_key.with_format(Format::B10G11R11_UFLOAT_PACK32),
        #ssao: ssao.get_output_tex(),
        .rgb = @ssao.rrr
    );

    let mut frame_idx = 0;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        // Calculate the new viewport constants from the latest state
        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height).finish();

        ssao.prepare_frame(&view_constants, &frame_state, frame_idx);

        raster_constants_buf.rebind(upload_buffer(view_constants));

        frame_idx += 1;
        out_tex.clone()
    });
}
