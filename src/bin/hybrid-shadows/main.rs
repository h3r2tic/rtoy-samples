use rendertoy::*;
use rtoy_rt::*;

#[allow(dead_code)]
#[derive(Clone, Copy)]
struct Constants {
    view_constants: ViewConstants,
    light_dir: Vector4,
}

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey::fullscreen(&rtoy, Format::R32G32B32A32_SFLOAT);

    //let scene_file = "assets/meshes/lighthouse.obj.gz";
    let scene = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);
    let bvh = vec![(
        scene.clone(),
        Vector3::new(0.0, 0.0, 0.0),
        UnitQuaternion::identity(),
    )];
    let gpu_bvh = upload_bvh(bvh);

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0));

    let mut rt_constants_buf = upload_buffer(0u32).isolate();
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
            :upload_raster_mesh(make_raster_mesh(scene))
        ),
    );

    let shadowed_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/rt_hybrid_shadows.glsl")),
        shader_uniforms!(
            constants: rt_constants_buf.clone(),
            inputTex: gbuffer_tex,
            :gpu_bvh,
        ),
    );

    let mut light_angle = 1.0f32;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height).finish();

        light_angle += 0.01;

        raster_constants_buf.rebind(upload_buffer(view_constants));

        rt_constants_buf.rebind(upload_buffer(Constants {
            view_constants,
            light_dir: Vector4::new(light_angle.cos(), 0.5, light_angle.sin(), 0.0),
        }));

        shadowed_tex.clone()
    });
}
