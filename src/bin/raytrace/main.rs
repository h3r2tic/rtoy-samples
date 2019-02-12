use rand::{distributions::StandardNormal, rngs::SmallRng, Rng, SeedableRng};
use rendertoy::*;
use rtoy_rt::*;

#[derive(Clone, Copy)]
#[repr(C)]
struct Constants {
    frame_idx: u32,
    pad: [u32; 3],
    viewport_constants: ViewportConstants,
}

fn main() {
    let scene_file = "assets/meshes/flying_trabant.obj.gz";
    //let scene_file = "assets/meshes/lighthouse.obj.gz";
    //let scene_file = "assets/meshes/pica.obj.gz";

    let mut camera =
        CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0)));

    let bvh = build_gpu_bvh(load_obj_scene(scene_file.to_string()));

    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    let viewport_constants_buf =
        init_named!("ViewportConstants", upload_buffer(to_byte_vec(vec![0])));

    let rt_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/raytrace.glsl")),
        shader_uniforms!("constants": viewport_constants_buf, "": bvh),
    );

    let accum_rt_tex = init_named!(
        "Accum rt texture",
        load_tex(asset!("rendertoy::images/black.png"))
    );

    let temporal_blend = init_named!("Temporal blend", const_f32(1f32));

    redef_named!(
        accum_rt_tex,
        compute_tex(
            tex_key,
            load_cs(asset!("shaders/blend.glsl")),
            shader_uniforms!(
                "inputTex1": accum_rt_tex,
                "inputTex2": rt_tex,
                "blendAmount": temporal_blend,
            )
        )
    );

    let sharpened_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/adaptive_sharpen.glsl")),
        shader_uniforms!("inputTex": accum_rt_tex),
    );

    let mut gpu_time_ms = 0.0f64;
    let mut frame_idx = 0;

    rtoy.forever(|snapshot, frame_state| {
        camera.update(
            FirstPersonCameraInput::from_frame_state(&frame_state),
            1.0 / 60.0,
        );

        let camera_matrices = camera.calc_matrices();
        if !camera.is_converged() {
            frame_idx = 0;
        }

        redef_named!(temporal_blend, const_f32(1.0 / (frame_idx as f32 + 1.0)));

        let mut rng = SmallRng::seed_from_u64(frame_idx as u64);
        let jitter = Vector2::new(
            0.5 * rng.sample(StandardNormal) as f32,
            0.5 * rng.sample(StandardNormal) as f32,
        );

        let viewport_constants =
            ViewportConstants::build(camera_matrices, tex_key.width, tex_key.height)
                .pixel_offset(jitter)
                .finish();

        redef_named!(
            viewport_constants_buf,
            upload_buffer(to_byte_vec(vec![Constants {
                frame_idx,
                pad: [0; 3],
                viewport_constants,
            },]))
        );

        draw_fullscreen_texture(&*snapshot.get(sharpened_tex));

        let cur = frame_state.gpu_time_ms;
        let prev = gpu_time_ms.max(cur * 0.85).min(cur / 0.85);
        gpu_time_ms = prev * 0.95 + cur * 0.05;
        print!("Frame time: {:.2} ms           \r", gpu_time_ms);

        use std::io::Write;
        let _ = std::io::stdout().flush();

        frame_idx += 1;
    });
}
