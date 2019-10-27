use rand::{rngs::SmallRng, Rng, SeedableRng};
use rand_distr::StandardNormal;
use rendertoy::*;

#[allow(dead_code)]
#[derive(Clone, Copy)]
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

pub fn filter_ssao_temporally(
    input: SnoozyRef<Texture>,
    reprojection_tex: SnoozyRef<Texture>,
    tex_key: TextureKey,
) -> rtoy_samples::TemporalAccumulation {
    let temporal_blend = init_dynamic!(const_f32(1f32));
    let accum_tex = init_dynamic!(load_tex(asset!("rendertoy::images/black.png")));

    redef_dynamic!(
        accum_tex,
        compute_tex(
            tex_key,
            load_cs(asset!("shaders/ssao_temporal_filter.glsl")),
            shader_uniforms!(
                inputTex: input,
                historyTex: accum_tex.clone(),
                reprojectionTex: reprojection_tex,
            )
        )
    );

    rtoy_samples::TemporalAccumulation {
        tex: accum_tex,
        temporal_blend,
    }
}

fn main() {
    let mut rtoy = Rendertoy::new();
    let tex_key = TextureKey::fullscreen(&rtoy, gl::RGBA32F);

    let scene = load_gltf_scene(
        //asset!("meshes/flying_trabant_final_takeoff/scene.gltf"),
        asset!("meshes/the_lighthouse/scene.gltf"),
        1.0,
    );

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0));

    let ao_constants_buf = init_dynamic!(upload_buffer(0u32));
    let raster_constants_buf = init_dynamic!(upload_buffer(0u32));
    let reproj_constants = init_dynamic!(upload_buffer(0u32));

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

    let reprojection_tex = compute_tex(
        TextureKey {
            width: rtoy.width(),
            height: rtoy.height(),
            format: gl::RGBA16F,
        },
        load_cs(asset!("shaders/reproject.glsl")),
        shader_uniforms!(
            constants: reproj_constants.clone(),
            inputTex: gbuffer_tex.clone()
        ),
    );

    let depth_tex = compute_tex(
        tex_key.with_format(gl::R16F),
        load_cs(asset!("shaders/extract_gbuffer_depth.glsl")),
        shader_uniforms!(inputTex: gbuffer_tex.clone()),
    );

    let ao_tex = compute_tex(
        tex_key.with_format(gl::R16F),
        load_cs(asset!("shaders/ssao.glsl")),
        shader_uniforms!(
            constants: ao_constants_buf.clone(),
            inputTex: gbuffer_tex.clone(),
            depthTex: depth_tex.clone()
        ),
    );

    let normal_tex = compute_tex(
        tex_key.with_format(gl::R32UI),
        load_cs(asset!("shaders/extract_gbuffer_normal.glsl")),
        shader_uniforms!(inputTex: gbuffer_tex),
    );

    let ao_tex = compute_tex(
        tex_key.with_format(gl::R8),
        load_cs(asset!("shaders/ssao_spatial_filter.glsl")),
        shader_uniforms!(aoTex: ao_tex, depthTex: depth_tex, normalTex: normal_tex,),
    );

    let mut temporal_accum =
        filter_ssao_temporally(ao_tex, reprojection_tex, tex_key.with_format(gl::R16F));

    let out_tex = compute_tex!(
        "splat red to rgb",
        tex_key.with_format(gl::RGBA16F),
        #input: temporal_accum.tex.clone(),
        color.rgb = #@input.rrr
    );

    let out_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: out_tex,
            constants: init_dynamic!(upload_buffer(0.4f32)),
        ),
    );

    let mut frame_idx = 0;
    let mut prev_world_to_clip = Matrix4::identity();

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        temporal_accum.prepare_frame(frame_idx);

        // Jitter the image in a Gaussian kernel in order to anti-alias the result. This is why we have
        // a post-process sharpen too. The Gaussian kernel eliminates jaggies, and then the post
        // filter perceptually sharpens it whilst keeping the image alias-free.
        let mut rng = SmallRng::seed_from_u64(frame_idx as u64);
        let jitter = Vector2::new(
            0.5 * rng.sample::<f32, _>(StandardNormal),
            0.5 * rng.sample::<f32, _>(StandardNormal),
        );

        // Calculate the new viewport constants from the latest state
        let viewport_constants = ViewportConstants::build(&camera, tex_key.width, tex_key.height)
            .pixel_offset(jitter)
            .finish();

        redef_dynamic!(raster_constants_buf, upload_buffer(viewport_constants));

        redef_dynamic!(
            ao_constants_buf,
            upload_buffer(Constants {
                viewport_constants,
                frame_idx,
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
        out_tex.clone()
    });
}
