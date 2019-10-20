use rand::{distributions::StandardNormal, rngs::SmallRng, Rng, SeedableRng};
use rendertoy::*;
use rtoy_rt::*;

#[allow(dead_code)]
#[derive(Clone, Copy)]
struct Constants {
    viewport_constants: ViewportConstants,
    frame_idx: u32,
}

fn main() {
    let mut rtoy = Rendertoy::new();
    let tex_key = TextureKey::fullscreen(&rtoy, gl::RGBA32F);

    let scene = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);
    let bvh = build_gpu_bvh(scene);
    let gpu_bvh = upload_bvh(bvh);

    let mut camera =
        CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0)));

    let rt_constants_buf = init_dynamic!(upload_buffer(0u32));
    let raster_constants_buf = init_dynamic!(upload_buffer(0u32));

    let gbuffer_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
        ]),
        shader_uniforms!(
            "constants": raster_constants_buf,
            "": upload_raster_mesh(make_raster_mesh(scene))
        ),
    );

    let ao_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/ssao.glsl")),
        shader_uniforms!(
            "constants": rt_constants_buf,
            "inputTex": gbuffer_tex,
            "": gpu_bvh,
        ),
    );

    let mut temporal_accum = rtoy_samples::accumulate_temporally(ao_tex, tex_key);
    let mut frame_idx = 0;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        // If the camera is moving/rotating, reset image accumulation.
        if !camera.is_converged() {
            frame_idx = 0;
        }

        temporal_accum.prepare_frame(frame_idx);

        /*let viewport_constants =
        ViewportConstants::build(&camera, tex_key.width, tex_key.height).finish();*/

        // Jitter the image in a Gaussian kernel in order to anti-alias the result. This is why we have
        // a post-process sharpen too. The Gaussian kernel eliminates jaggies, and then the post
        // filter perceptually sharpens it whilst keeping the image alias-free.
        let mut rng = SmallRng::seed_from_u64(frame_idx as u64);
        let jitter = Vector2::new(
            0.5 * rng.sample(StandardNormal) as f32,
            0.5 * rng.sample(StandardNormal) as f32,
        );

        // Calculate the new viewport constants from the latest state
        let viewport_constants = ViewportConstants::build(&camera, tex_key.width, tex_key.height)
            .pixel_offset(jitter)
            .finish();

        redef_dynamic!(raster_constants_buf, upload_buffer(viewport_constants));

        redef_dynamic!(
            rt_constants_buf,
            upload_buffer(Constants {
                viewport_constants,
                frame_idx,
            })
        );

        //frame_idx = (frame_idx + 1).min(1024);
        frame_idx += 1;

        temporal_accum.tex
        //ao_tex
    });
}
