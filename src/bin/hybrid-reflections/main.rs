use rendertoy::*;
use rtoy_rt::*;

#[derive(Clone, Copy)]
#[repr(C)]
struct Constants {
    viewport_constants: ViewportConstants,
    frame_idx: u32,
}

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    //let scene_file = "assets/meshes/lighthouse.obj.gz";
    let scene_file = "assets/meshes/flying_trabant.obj.gz";

    let scene = load_obj_scene(scene_file.to_string());
    let bvh = build_gpu_bvh(scene);

    let mut camera =
        CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0)));

    let constants_buf = init_dynamic!(upload_buffer(0u32));

    let gbuffer_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
        ]),
        shader_uniforms!(
            "constants": constants_buf,
            "": upload_raster_mesh(make_raster_mesh(scene))
        ),
    );

    let shadowed_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/rt_hybrid_reflections.glsl")),
        shader_uniforms!(
            "constants": constants_buf,
            "inputTex": gbuffer_tex,
            "": upload_raster_mesh(make_raster_mesh(scene)),
            "": upload_bvh(bvh),
        ),
    );

    let mut frame_idx = 0u32;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state, 1.0 / 60.0);

        let viewport_constants =
            ViewportConstants::build(&camera, tex_key.width, tex_key.height).finish();

        redef_dynamic!(
            constants_buf,
            upload_buffer(Constants {
                viewport_constants,
                frame_idx
            })
        );

        frame_idx += 1;
        shadowed_tex
    });
}
