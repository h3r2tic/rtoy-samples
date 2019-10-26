use rendertoy::*;
use rtoy_rt::*;

#[allow(dead_code)]
#[derive(Clone, Copy)]
struct Constants {
    viewport_constants: ViewportConstants,
    light_dir: Vector4,
}

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

    let rt_constants_buf = init_dynamic!(upload_buffer(0u32));
    let raster_constants_buf = init_dynamic!(upload_buffer(0u32));

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

        let viewport_constants =
            ViewportConstants::build(&camera, tex_key.width, tex_key.height).finish();

        light_angle += 0.01;

        redef_dynamic!(raster_constants_buf, upload_buffer(viewport_constants));

        redef_dynamic!(
            rt_constants_buf,
            upload_buffer(Constants {
                viewport_constants,
                light_dir: Vector4::new(light_angle.cos(), 0.5, light_angle.sin(), 0.0)
            })
        );

        shadowed_tex.clone()
    });
}
