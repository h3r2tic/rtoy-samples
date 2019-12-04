use rand::{rngs::SmallRng, Rng, SeedableRng};
use rand_distr::StandardNormal;
use rendertoy::*;
use rtoy_rt::*;

#[derive(Clone, Copy)]
#[repr(C)]
struct Constants {
    frame_idx: u32,
    pad: [u32; 3],
    view_constants: ViewConstants,
}

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey::fullscreen(&rtoy, Format::R32G32B32A32_SFLOAT);

    let dredd = load_gltf_scene(asset!("meshes/dredd/scene.gltf"), 5.0);
    //let lighthouse = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);

    // Wrap a first person camera in a utility which enforces movement/rotation convergence by stopping it upon small deltas.
    // This comes in handy because the raytracer resets accumulation upon movement,
    // and the camera uses exponential smoothing.
    let mut camera =
        CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0)));

    let mut bvh = upload_bvh(vec![]).isolate();

    // Make a named slot for viewport constants. By giving it a unique name,
    // we can re-define it at runtime, and keep the lazy evaluation graph structure.
    let mut viewport_constants_buf = upload_buffer(0.0f32).isolate();

    // Define the raytrace output texture. Since it depends on viewport constants,
    // it will get re-generated whenever they change.
    let rt_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/raytrace.glsl")),
        shader_uniforms!(
            constants: viewport_constants_buf.clone(),
            :bvh.clone()
        ),
    );

    let mut temporal_accum = rtoy_samples::accumulate_temporally(rt_tex, tex_key);

    let mut sharpen_amount = const_f32(0.0f32).isolate();

    // Finally, chain a post-process sharpening effect to the output.
    let sharpened_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: temporal_accum.tex.clone(),
            sharpen_amount: sharpen_amount.clone()),
    );

    let mut frame_idx = 0;

    // Start the main loop
    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        // Animate so we get motion blur!
        let dredd_rot =
            na::UnitQuaternion::from_axis_angle(&Vector3::y_axis(), frame_idx as f32 * 0.05 * 0.0);
        //let dredd_pos = Vector3::new(150.0, 0.0, 0.0);

        /*let scene = vec![
            (dredd.clone(), dredd_pos, dredd_rot),
            (
                lighthouse.clone(),
                Vector3::new(-250.0, -50.0, -100.0),
                UnitQuaternion::identity(),
            ),
        ];*/

        let scene = (0..16 * 16)
            .map(|i| {
                (
                    dredd.clone(),
                    Vector3::new(
                        -300.0 * 8.0 + 300.0 * (i % 16) as f32,
                        600.0 * (((frame_idx * 0 + i * 1234567) % (314 * 2)) as f32 * 0.01).sin(),
                        -300.0 * 8.0 + 300.0 * (i / 16) as f32,
                    ),
                    //UnitQuaternion::identity(),
                    dredd_rot,
                )
            })
            .collect::<Vec<_>>();

        /*scene.push((
            lighthouse.clone(),
            Vector3::new(0.0, -50.0, -300.0),
            UnitQuaternion::identity(),
        ));*/

        // Build a BVH and acquire a bundle of GPU buffers.
        bvh.rebind(upload_bvh(scene));

        // If the camera is moving/rotating, reset image accumulation.
        if !camera.is_converged() {
            frame_idx = 0;
        }

        // Jitter the image in a Gaussian kernel in order to anti-alias the result. This is why we have
        // a post-process sharpen too. The Gaussian kernel eliminates jaggies, and then the post
        // filter perceptually sharpens it whilst keeping the image alias-free.
        let mut rng = SmallRng::seed_from_u64(frame_idx as u64);
        let jitter = Vector2::new(
            0.5 * rng.sample::<f32, _>(StandardNormal),
            0.5 * rng.sample::<f32, _>(StandardNormal),
        );

        // Calculate the new viewport constants from the latest state
        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height)
            .pixel_offset(jitter)
            .finish();

        temporal_accum.prepare_frame(&view_constants, frame_state, frame_idx);

        sharpen_amount.rebind(const_f32(((frame_idx as f32).sqrt() / 256.0).min(0.7)));

        // Redefine the viewport constants parameter. This invalidates all dependent assets,
        // and causes the next frame to be rendered.

        viewport_constants_buf.rebind(upload_buffer(Constants {
            frame_idx,
            pad: [0; 3],
            view_constants,
        }));

        frame_idx += 1;

        // Finaly display the result.
        sharpened_tex.clone()
    });
}
