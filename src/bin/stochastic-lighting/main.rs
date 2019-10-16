use rand::{distributions::StandardNormal, rngs::SmallRng, Rng, SeedableRng};
use rendertoy::*;
use rtoy_rt::*;

#[derive(Clone, Copy)]
#[repr(C)]
struct Constants {
    viewport_constants: ViewportConstants,
    frame_idx: u32,
}

#[derive(Clone, Copy)]
#[repr(C)]
struct ReprojConstants {
    viewport_constants: ViewportConstants,
    prev_world_to_clip: Matrix4,
}

/*fn temporal_accumulate(
    input: SnoozyRef<Texture>,
    tex_key: TextureKey,
) -> (SnoozyRef<f32>, SnoozyRef<Texture>) {
    let temporal_blend = init_dynamic!(const_f32(1f32));

    let accum_tex = init_dynamic!(load_tex(asset!("rendertoy::images/black.png")));

    redef_dynamic!(
        accum_tex,
        compute_tex(
            tex_key,
            load_cs(asset!("shaders/blend.glsl")),
            shader_uniforms!(
                "inputTex1": accum_tex,
                "inputTex2": input,
                "blendAmount": temporal_blend,
            )
        )
    );

    (temporal_blend, accum_tex)
}*/

fn temporal_accumulate(
    input: SnoozyRef<Texture>,
    reprojection_tex: SnoozyRef<Texture>,
    tex_key: TextureKey,
) -> (SnoozyRef<f32>, SnoozyRef<Texture>) {
    let temporal_blend = init_dynamic!(const_f32(1f32));
    let accum_tex = init_dynamic!(load_tex(asset!("rendertoy::images/black.png")));

    redef_dynamic!(
        accum_tex,
        compute_tex(
            tex_key,
            load_cs(asset!("shaders/taa.glsl")),
            shader_uniforms!(
                "inputTex": input,
                "historyTex": accum_tex,
                "reprojectionTex": reprojection_tex,
            )
        )
    );

    (temporal_blend, accum_tex)
}

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    //let scene_file = "assets/meshes/flying_trabant.obj.gz";
    //let scene_file = "assets/meshes/veach-mis-scaled.obj";
    //let scene = load_obj_scene(scene_file.to_string());

    //let scene = load_gltf_scene(asset!("meshes/flying_trabant_final_takeoff/scene.gltf"), 1.0);
    //let scene = load_gltf_scene(asset!("meshes/helmetconcept/scene.gltf"), 100.0);
    //let scene = load_gltf_scene(asset!("meshes/knight_final/scene.gltf"), 100.0);
    //let scene = load_gltf_scene(asset!("meshes/ori/scene.gltf"), 0.1);
    //let scene = load_gltf_scene(asset!("meshes/panhard_ebr_75_mle1954/scene.gltf"), 100.0);
    //let scene = load_gltf_scene(asset!("meshes/dieselpunk_hovercraft/scene.gltf"), 1.0);
    let scene = load_gltf_scene(asset!("meshes/dredd/scene.gltf"), 5.0);
    //let scene = load_gltf_scene(asset!("meshes/skull_salazar_downloadable/scene.gltf"), 100.0);
    //let scene = load_gltf_scene(asset!("meshes/squid_ink_bottle/scene.gltf"), 20.0);
    //let scene = load_gltf_scene(asset!("meshes/wild_west_motorcycle/scene.gltf"), 1.0);

    let bvh = build_gpu_bvh(scene);

    //let mut camera =
    //    CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0)));
    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0));
    camera.move_smoothness = 3.0;
    camera.look_smoothness = 3.0;

    let constants_buf = init_dynamic!(upload_buffer(0u32));
    let reproj_constants = init_dynamic!(upload_buffer(0u32));

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

    let reprojection_tex = compute_tex(
        TextureKey {
            width: rtoy.width(),
            height: rtoy.height(),
            format: gl::RGBA16F,
        },
        load_cs(asset!("shaders/reproject.glsl")),
        shader_uniforms!("constants": reproj_constants, "inputTex": gbuffer_tex,),
    );

    let out_tex = if false {
        compute_tex(
            tex_key,
            load_cs(asset!("shaders/rt_stochastic_lighting.glsl")),
            shader_uniforms!(
                "constants": constants_buf,
                "inputTex": gbuffer_tex,
                "": upload_raster_mesh(make_raster_mesh(scene)),
                "": upload_bvh(bvh),
            ),
        )
    } else {
        let out_tex = compute_tex(
            tex_key,
            load_cs(asset!("shaders/rt_stochastic_light_sampling.glsl")),
            shader_uniforms!(
                "constants": constants_buf,
                "inputTex": gbuffer_tex,
                "": upload_raster_mesh(make_raster_mesh(scene)),
                "": upload_bvh(bvh),
            ),
        );

        let variance_estimate = init_dynamic!(load_tex(asset!("rendertoy::images/black.png")));
        redef_dynamic!(
            variance_estimate,
            compute_tex(
                tex_key,
                load_cs(asset!("shaders/stochastic_light_variance_estimate.glsl")),
                shader_uniforms!(
                    "g_primaryVisTex": gbuffer_tex,
                    "inputTex": out_tex,
                    "historyTex": variance_estimate,
                    "reprojectionTex": reprojection_tex,
                )
            )
        );

        compute_tex(
            tex_key,
            load_cs(asset!("shaders/stochastic_light_filter.glsl")),
            shader_uniforms!(
                //"g_frameIndex": frame_index,
                //"g_mouseX": mouse_x,
                "constants": constants_buf,
                "g_primaryVisTex": gbuffer_tex,
                "g_lightSamplesTex": out_tex,
                "g_varianceEstimate": variance_estimate,
            ),
        )
    };

    let (temporal_blend, out_tex) = temporal_accumulate(out_tex, reprojection_tex, tex_key);

    // Finally, chain a post-process sharpening effect to the output.
    let out_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/adaptive_sharpen.glsl")),
        shader_uniforms!(
            "inputTex": out_tex,
            "constants": init_dynamic!(upload_buffer(0.4f32)),
        ),
    );

    let mut frame_idx = 0u32;
    let mut prev_world_to_clip = Matrix4::identity();

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state, 1.0 / 60.0);

        // If the camera is moving/rotating, reset image accumulation.
        /*if !camera.is_converged() {
            frame_idx = 0;
        }

        // Set the new blend factor such that we calculate a uniform average of all the traced frames.
        redef_dynamic!(temporal_blend, const_f32(1.0 / (frame_idx as f32 + 1.0)));*/

        redef_dynamic!(temporal_blend, const_f32(0.1));

        // Jitter the image in a Gaussian kernel in order to anti-alias the result. This is why we have
        // a post-process sharpen too. The Gaussian kernel eliminates jaggies, and then the post
        // filter perceptually sharpens it whilst keeping the image alias-free.
        let mut rng = SmallRng::seed_from_u64(frame_idx as u64);
        let jitter = Vector2::new(
            0.333 * rng.sample(StandardNormal) as f32,
            0.333 * rng.sample(StandardNormal) as f32,
        );

        // Calculate the new viewport constants from the latest state
        let viewport_constants = ViewportConstants::build(&camera, tex_key.width, tex_key.height)
            .pixel_offset(jitter)
            .finish();

        redef_dynamic!(
            constants_buf,
            upload_buffer(Constants {
                viewport_constants,
                frame_idx
            })
        );

        redef_dynamic!(
            reproj_constants,
            upload_buffer(ReprojConstants {
                viewport_constants: ViewportConstants::build(
                    &camera,
                    tex_key.width,
                    tex_key.height
                )
                .finish(),
                prev_world_to_clip
            })
        );

        let m = camera.calc_matrices();
        prev_world_to_clip = m.view_to_clip * m.world_to_view;

        frame_idx += 1;
        out_tex
    });
}