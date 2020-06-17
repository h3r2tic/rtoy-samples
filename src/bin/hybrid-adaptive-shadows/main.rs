use rendertoy::*;
use rtoy_rt::*;
use rtoy_samples::rt_shadows::*;

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey::fullscreen(&rtoy, Format::R32G32B32A32_SFLOAT);

    //let scene_file = "assets/meshes/lighthouse.obj.gz";
    let scene = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);
    let bvh = vec![(scene.clone(), Vec3::zero(), Quat::identity())];
    let gpu_bvh = upload_bvh(bvh);

    let mut camera = FirstPersonCamera::new(Vec3::new(0.0, 200.0, 800.0));

    let mut raster_constants_buf = upload_buffer(0u32).isolate();

    let gbuffer_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
        ]),
        shader_uniforms!(
            constants: raster_constants_buf.clone(),
            instance_transform: raster_mesh_transform(Vec3::zero(), Quat::identity()),
            :upload_raster_mesh(make_raster_mesh(scene.clone()))
        ),
    );

    let light_controller = Rc::new(Cell::new(DirectionalLightState::new(Vec3::unit_x())));
    let mut rt_shadows = RtShadows::new(tex_key, gbuffer_tex, gpu_bvh, light_controller.clone());

    let out_tex = compute_tex!(
        "splat red to rgb",
        tex_key.with_format(Format::B10G11R11_UFLOAT_PACK32),
        #shadows: rt_shadows.get_output_tex(),
        .rgb = @shadows.rrr
    );

    let mut light_angle = 1.0f32;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height).build();

        raster_constants_buf.rebind(upload_buffer(view_constants));

        light_controller.set(DirectionalLightState::new(
            Vec3::new(light_angle.cos(), 0.5, light_angle.sin()).normalize(),
        ));
        rt_shadows.prepare_frame(&view_constants, frame_state, 0);

        light_angle += 0.01;

        out_tex.clone()
    });
}
