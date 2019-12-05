#[macro_use]
extern crate snoozy_macros;

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

#[derive(Clone, Copy)]
#[repr(C)]
struct ReprojConstants {
    view_constants: ViewConstants,
    prev_world_to_clip: Matrix4,
}

#[snoozy]
async fn build_light_gpu_data(
    ctx: Context,
    mesh: &SnoozyRef<TriangleMesh>,
) -> Result<ShaderUniformBundle> {
    let mesh = ctx.get(mesh).await?;

    let mut tris: Vec<([[f32; 3]; 3], [f32; 3])> = Vec::with_capacity(mesh.indices.len() / 3);
    let mut weights: Vec<f64> = Vec::with_capacity(mesh.indices.len() / 3);

    for tri in mesh.indices.chunks(3) {
        let mat_id = mesh.material_ids[tri[0] as usize];
        let mat = &mesh.materials[mat_id as usize];

        if mat.emissive != [0.0, 0.0, 0.0] {
            let p0 = Point3::from(mesh.positions[tri[0] as usize]);
            let p1 = Point3::from(mesh.positions[tri[1] as usize]);
            let p2 = Point3::from(mesh.positions[tri[2] as usize]);

            let area = (p1 - p0).cross(&(p2 - p0)).norm() * 0.5;
            weights.push(area as f64);

            tris.push((
                [
                    mesh.positions[tri[0] as usize],
                    mesh.positions[tri[1] as usize],
                    mesh.positions[tri[2] as usize],
                ],
                mat.emissive,
            ));
        }
    }

    if let Ok(alias_table) = aliasmethod::new_alias_table(&weights) {
        let tbl = alias_table
            .prob
            .iter()
            .enumerate()
            .map(|(i, p)| (*p as f32, alias_table.alias[i] as u32))
            .collect::<Vec<_>>();

        let count = tbl.len() as u32;
        dbg!(count);

        Ok(shader_uniforms!(
            light_triangles_buf: upload_array_buffer(Box::new(tris)),
            light_alias_buf: upload_array_buffer(Box::new(tbl)),
            light_count_buf: upload_buffer(count),
        ))
    } else {
        unimplemented!();
    }
}

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey::fullscreen(&rtoy, Format::R32G32B32A32_SFLOAT);

    //let scene_file = "assets/meshes/flying_trabant.obj.gz";
    //let scene_file = "assets/meshes/veach-mis-scaled.obj";
    //let scene = load_obj_scene(scene_file.to_string());

    let scene = load_gltf_scene(
        asset!("meshes/flying_trabant_final_takeoff/scene.gltf"),
        1.0,
    );
    //let scene = load_gltf_scene(asset!("meshes/helmetconcept/scene.gltf"), 100.0);
    //let scene = load_gltf_scene(asset!("meshes/knight_final/scene.gltf"), 100.0);
    //let scene = load_gltf_scene(asset!("meshes/panhard_ebr_75_mle1954/scene.gltf"), 100.0);
    //let scene = load_gltf_scene(asset!("meshes/dieselpunk_hovercraft/scene.gltf"), 1.0);
    //let scene = load_gltf_scene(asset!("meshes/skull_salazar/scene.gltf"), 100.0);
    //let scene = load_gltf_scene(asset!("meshes/squid_ink_bottle/scene.gltf"), 20.0);
    //let scene = load_gltf_scene(asset!("meshes/wild_west_motorcycle/scene.gltf"), 1.0);
    //let scene = load_gltf_scene(asset!("meshes/knight_artorias/scene.gltf"), 0.1);
    //let scene = load_gltf_scene(asset!("meshes/dreadroamer/scene.gltf"), 1.0);

    //let scene = load_gltf_scene(asset!("meshes/ori/scene.gltf"), 0.1);
    //let scene = load_gltf_scene(asset!("meshes/dredd/scene.gltf"), 5.0);

    //let lights = build_light_gpu_data(scene);
    let bvh = vec![(
        scene.clone(),
        Vector3::new(0.0, 0.0, 0.0),
        UnitQuaternion::identity(),
    )];

    let mut time = const_f32(0f32).isolate();

    //let mut camera =
    //    CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0)));
    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0));
    camera.move_smoothness = 3.0;
    camera.look_smoothness = 3.0;

    let mut constants_buf = upload_buffer(0u32).isolate();
    let mut reproj_constants = upload_buffer(0u32).isolate();

    let gbuffer_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
        ]),
        shader_uniforms!(
            constants: constants_buf.clone(),
            instance_transform: raster_mesh_transform(Vector3::zeros(), UnitQuaternion::identity()),
            :upload_raster_mesh(make_raster_mesh(scene.clone()))
        ),
    );

    let reprojection_tex = compute_tex(
        tex_key.with_format(Format::R16G16B16A16_SFLOAT),
        load_cs(asset!("shaders/reproject.glsl")),
        shader_uniforms!(constants: reproj_constants.clone(), inputTex: gbuffer_tex.clone(),),
    );

    let out_tex = if false {
        compute_tex(
            tex_key,
            load_cs(asset!("shaders/rt_stochastic_lighting.glsl")),
            shader_uniforms!(
                constants: constants_buf.clone(),
                time_seconds: time.clone(),
                inputTex: gbuffer_tex.clone(),
                :upload_raster_mesh(make_raster_mesh(scene.clone())),
                :upload_bvh(bvh.clone()),
            ),
        )
    } else {
        let out_tex = compute_tex(
            tex_key,
            load_cs(asset!("shaders/rt_stochastic_light_sampling.glsl")),
            shader_uniforms!(
                constants: constants_buf.clone(),
                time_seconds: time.clone(),
                inputTex: gbuffer_tex.clone(),
                :upload_raster_mesh(make_raster_mesh(scene.clone())),
                :upload_bvh(bvh.clone()),
                blue_noise_tex: load_tex_with_params(
                    //asset!("rendertoy::images/noise/blue_noise_2d_toroidal_64.png"), TexParams {
                        asset!("images/bluenoise/256_256/LDR_RGBA_0.png"), TexParams {
                        gamma: TexGamma::Linear,
                    }),
            ),
        );

        let mut variance_estimate = load_tex(asset!("rendertoy::images/black.png")).isolate();
        variance_estimate.rebind(compute_tex(
            tex_key,
            load_cs(asset!("shaders/stochastic_light_variance_estimate.glsl")),
            shader_uniforms!(
                constants: constants_buf.clone(),
                g_primaryVisTex: gbuffer_tex.clone(),
                inputTex: out_tex.clone(),
                historyTex: variance_estimate.clone(),
                reprojectionTex: reprojection_tex.clone(),
            ),
        ));

        compute_tex(
            tex_key,
            load_cs(asset!("shaders/stochastic_light_filter.glsl")),
            shader_uniforms!(
                //"g_frameIndex": frame_index,
                //"g_mouseX": mouse_x,
                constants: constants_buf.clone(),
                time_seconds: time.clone(),
                g_primaryVisTex: gbuffer_tex,
                g_lightSamplesTex: out_tex,
                g_varianceEstimate: variance_estimate,
            ),
        )
    };

    let mut variance_estimate2 = load_tex(asset!("rendertoy::images/black.png")).isolate();

    variance_estimate2.rebind(compute_tex(
        tex_key,
        load_cs(asset!("shaders/variance_estimate.glsl")),
        shader_uniforms!(
            inputTex: out_tex.clone(),
            historyTex: variance_estimate2.clone(),
            reprojectionTex: reprojection_tex.clone(),
        ),
    ));

    let out_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/steerable_bilateral.glsl")),
        shader_uniforms!(inputTex: out_tex, varianceTex: variance_estimate2,),
    );

    let mut taa_constants = upload_buffer(Vector2::new(0.0, 0.0)).isolate();
    let mut temporal_accum = rtoy_samples::accumulate_reproject_temporally(
        out_tex,
        reprojection_tex,
        tex_key,
        taa_constants.clone(),
    );

    // Finally, chain a post-process sharpening effect to the output.
    let out_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: temporal_accum.tex.clone(),
            sharpen_amount: 0.0f32,
        ),
    );

    let mut frame_idx = 0u32;
    let mut t = 0.0f32;
    let mut prev_world_to_clip = Matrix4::identity();

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        // If the camera is moving/rotating, reset image accumulation.
        /*if !camera.is_converged() {
            frame_idx = 0;
        }

        // Set the new blend factor such that we calculate a uniform average of all the traced frames.
        temporal_blend.rebind(const_f32(1.0 / (frame_idx as f32 + 1.0)));*/

        temporal_accum.temporal_blend.rebind(const_f32(0.1));

        // Jitter the image in a Gaussian kernel in order to anti-alias the result. This is why we have
        // a post-process sharpen too. The Gaussian kernel eliminates jaggies, and then the post
        // filter perceptually sharpens it whilst keeping the image alias-free.
        let mut rng = SmallRng::seed_from_u64(frame_idx as u64);
        let jitter = Vector2::new(
            0.333 * rng.sample::<f32, _>(StandardNormal),
            0.333 * rng.sample::<f32, _>(StandardNormal),
        );
        taa_constants.rebind(upload_buffer(jitter));

        // Calculate the new viewport constants from the latest state
        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height)
            .pixel_offset(jitter)
            .finish();

        constants_buf.rebind(upload_buffer(Constants {
            view_constants,
            frame_idx,
        }));

        reproj_constants.rebind(upload_buffer(ReprojConstants {
            view_constants: ViewConstants::build(&camera, tex_key.width, tex_key.height).finish(),
            prev_world_to_clip,
        }));

        t += frame_state.dt;
        time.rebind(const_f32(t));

        let m = camera.calc_matrices();
        prev_world_to_clip = m.view_to_clip * m.world_to_view;

        frame_idx += 1;
        out_tex.clone()
    });
}
