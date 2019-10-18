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
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    let scene = load_gltf_scene(asset!("meshes/dredd/scene.gltf"), 5.0);

    // Wrap a first person camera in a utility which enforces movement/rotation convergence by stopping it upon small deltas.
    // This comes in handy because the raytracer resets accumulation upon movement,
    // and the camera uses exponential smoothing.
    let mut camera =
        CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0)));

    // Build a BVH and acquire a bundle of GPU buffers.
    let bvh = upload_bvh(build_gpu_bvh(scene));

    // Make a named slot for viewport constants. By giving it a unique name,
    // we can re-define it at runtime, and keep the lazy evaluation graph structure.
    let viewport_constants_buf = init_dynamic!(upload_buffer(0.0f32));

    // Define the raytrace output texture. Since it depends on viewport constants,
    // it will get re-generated whenever they change.
    let rt_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/raytrace.glsl")),
        shader_uniforms!("constants": viewport_constants_buf, "": bvh),
    );

    // We temporally accumulate raytraced images. The blend factor gets re-defined every frame.
    let temporal_blend = init_dynamic!(const_f32(1f32));

    // Need a valid value for the accumulation history. Black will do.
    let accum_rt_tex = init_dynamic!(load_tex(asset!("rendertoy::images/black.png")));

    // Re-define the resource with a cycle upon itself -- every time it gets evaluated,
    // it will use its previous value for "history", and produce a new value.
    redef_dynamic!(
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

    let sharpen_constants_buf = init_dynamic!(upload_buffer(0.0f32));

    // Finally, chain a post-process sharpening effect to the output.
    let sharpened_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!("inputTex": accum_rt_tex, "constants": sharpen_constants_buf),
    );

    let mut frame_idx = 0;

    // Start the main loop
    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state, 1.0 / 60.0);

        // If the camera is moving/rotating, reset image accumulation.
        if !camera.is_converged() {
            frame_idx = 0;
        }

        // Set the new blend factor such that we calculate a uniform average of all the traced frames.
        redef_dynamic!(temporal_blend, const_f32(1.0 / (frame_idx as f32 + 1.0)));

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

        let sharpen_amount = (frame_idx as f32 / 1024.0).min(0.5);
        redef_dynamic!(sharpen_constants_buf, upload_buffer(sharpen_amount));

        // Redefine the viewport constants parameter. This invalidates all dependent assets,
        // and causes the next frame to be rendered.
        redef_dynamic!(
            viewport_constants_buf,
            upload_buffer(Constants {
                frame_idx,
                pad: [0; 3],
                viewport_constants,
            })
        );

        frame_idx += 1;

        // Finaly display the result.
        sharpened_tex
    });
}
