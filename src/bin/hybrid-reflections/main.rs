use rand::{rngs::SmallRng, Rng, SeedableRng};
use rand_distr::StandardNormal;
use rendertoy::*;
use rtoy_rt::*;

#[derive(Clone, Copy)]
#[repr(C)]
struct Constants {
    view_constants: ViewConstants,
    frame_idx: u32,
}

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: Format::R32G32B32A32_SFLOAT,
    };

    let mesh = load_gltf_scene(asset!("meshes/dredd/scene.gltf"), 5.0);
    let bvh = vec![
        (
            mesh.clone(),
            Vector3::new(-150.0, 0.0, 0.0),
            UnitQuaternion::from_axis_angle(&Vector3::y_axis(), 90.0f32.to_radians()),
        ),
        (
            mesh.clone(),
            Vector3::new(150.0, 0.0, 0.0),
            UnitQuaternion::identity(),
        ),
    ];

    let mut camera =
        CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0)));

    let mut constants_buf = upload_buffer(0u32).isolate();

    let gbuffer_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
        ]),
        vec![
            shader_uniform_bundle!(
                instance_transform: raster_mesh_transform(Vector3::new(-150.0, 0.0, 0.0), UnitQuaternion::from_axis_angle(&Vector3::y_axis(), 90.0f32.to_radians())),
                constants: constants_buf.clone(),
                :upload_raster_mesh(make_raster_mesh(mesh.clone()))
            ),
            shader_uniform_bundle!(
                instance_transform: raster_mesh_transform(Vector3::new(150.0, 0.0, 0.0), UnitQuaternion::identity()),
                constants: constants_buf.clone(),
                :upload_raster_mesh(make_raster_mesh(mesh.clone()))
            ),
        ],
    );

    let out_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/rt_hybrid_reflections.glsl")),
        shader_uniforms!(
            constants: constants_buf.clone(),
            inputTex: gbuffer_tex,
            :upload_raster_mesh(make_raster_mesh(mesh)),
            :upload_bvh(bvh),
        ),
    );

    let mut temporal_accum = rtoy_samples::accumulate_temporally(out_tex, tex_key);

    // Finally, chain a post-process sharpening effect to the output.
    let out_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: temporal_accum.tex.clone(),
            sharpen_amount: 0.4f32,
        ),
    );

    let mut frame_idx = 0u32;
    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        // If the camera is moving/rotating, reset image accumulation.
        if !camera.is_converged() {
            frame_idx = 0;
        }

        // Jitter the image in a Gaussian kernel in order to anti-alias the result. This is why we have
        // a post-process sharpen too. The Gaussian kernel eliminates jaggies, and then the post
        // filter perceptually sharpens it whilst keeping the image alias-free.
        let mut rng = SmallRng::seed_from_u64(frame_idx as u64);
        let jitter = Vector2::new(
            0.5 * rng.sample::<f32, _>(StandardNormal) as f32,
            0.5 * rng.sample::<f32, _>(StandardNormal) as f32,
        );

        // Calculate the new viewport constants from the latest state
        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height)
            .pixel_offset(jitter)
            .finish();

        temporal_accum.prepare_frame(&view_constants, frame_state, frame_idx);

        constants_buf.rebind(upload_buffer(Constants {
            view_constants,
            frame_idx,
        }));

        frame_idx += 1;
        out_tex.clone()
    });
}
