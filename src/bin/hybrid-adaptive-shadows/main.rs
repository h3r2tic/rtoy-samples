use rendertoy::*;
use rtoy_rt::*;
use rtoy_samples::rt_shadows::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    //let scene_file = "assets/meshes/lighthouse.obj.gz";
    let scene = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);
    let bvh = vec![(
        scene.clone(),
        Vector3::new(0.0, 0.0, 0.0),
        UnitQuaternion::identity(),
    )];
    let gpu_bvh = upload_bvh(bvh);

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0));

    let mut raster_constants_buf = upload_buffer(0u32).isolate();

    let gbuffer_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
        ]),
        shader_uniforms!(
            constants: raster_constants_buf.clone(),
            instance_transform: raster_mesh_transform(Vector3::zeros(), UnitQuaternion::identity()),
            :upload_raster_mesh(make_raster_mesh(scene.clone()))
        ),
    );

    let light_controller = Rc::new(Cell::new(DirectionalLightState::new(*Vector3::x_axis())));
    let mut rt_shadows = RtShadows::new(tex_key, gbuffer_tex, gpu_bvh, light_controller.clone());

    let out_tex = compute_tex!(
        "splat red to rgb",
        tex_key.with_format(gl::R11F_G11F_B10F),
        #input: rt_shadows.get_output_tex(),
        .rgb = @input.rrr
    );

    let mut light_angle = 1.0f32;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height).finish();

        raster_constants_buf.rebind(upload_buffer(view_constants));

        light_controller.set(DirectionalLightState::new(
            Vector3::new(light_angle.cos(), 0.5, light_angle.sin()).normalize(),
        ));
        rt_shadows.prepare_frame(&view_constants, frame_state, 0);

        light_angle += 0.01;

        out_tex.clone()
    });
}
