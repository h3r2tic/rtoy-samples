use rendertoy::*;
use rtoy_rt::*;
use rtoy_samples::{rt_shadows::*, taa::*};

fn spherical_to_cartesian(theta: f32, phi: f32) -> Vector3 {
    let x = phi.sin() * theta.cos();
    let y = phi.cos();
    let z = phi.sin() * theta.sin();
    Vector3::new(x, y, z)
}

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: 0,
    };

    let mesh = load_gltf_scene(
        asset!("meshes/pica_pica_-_mini_diorama_01/scene.gltf"),
        20.0,
    );
    let scene = vec![(mesh.clone(), Vector3::zeros(), UnitQuaternion::identity())];
    let bvh = upload_bvh(scene.clone());

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0));
    camera.aspect = rtoy.width() as f32 / rtoy.height() as f32;
    //camera.fov = 55.0;
    let mut camera = CameraConvergenceEnforcer::new(camera);

    let light_controller = Rc::new(Cell::new(DirectionalLightState::new(*Vector3::x_axis())));
    //let mut light_angle = 1.0f32;

    let mut sky_constants = upload_buffer(0u32).into_named();
    let sky_tex = compute_tex(
        TextureKey {
            width: 128,
            height: 128,
            format: gl::RGBA16F,
        },
        load_cs(asset!("shaders/sky_octamap.glsl")),
        shader_uniforms!(constants: sky_constants.clone()),
    );

    let sky_lambert_tex = compute_tex(
        TextureKey {
            width: 128,
            height: 128,
            format: gl::RGBA16F,
        },
        load_cs(asset!("shaders/lambert_convolve_octamap.glsl")),
        shader_uniforms!(input_tex: sky_tex),
    );

    let mut taa = Taa::new(tex_key, |sub_passes| {
        let mut prev_world_to_clip = Matrix4::identity();

        let mut raster_constants_buf = upload_buffer(0u32).into_named();
        let mut merge_constants_buf = upload_buffer(0u32).into_named();
        let mut reproj_constants = upload_buffer(0u32).into_named();

        let gbuffer_tex = raster_tex(
            tex_key.with_format(gl::RGBA32F),
            make_raster_pipeline(vec![
                load_vs(asset!("shaders/raster_simple_vs.glsl")),
                load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
            ]),
            shader_uniforms!(
                constants: raster_constants_buf.clone(),
                :upload_raster_scene(&scene)
            ),
        );

        let mut ao_constants_buf = upload_buffer(0u32).into_named();

        let depth_tex = compute_tex(
            tex_key.with_format(gl::R16F),
            load_cs(asset!("shaders/extract_gbuffer_depth.glsl")),
            shader_uniforms!(inputTex: gbuffer_tex.clone()),
        );

        let mut lighting_tex = load_tex(asset!("rendertoy::images/black.png")).into_named();

        let reprojection_tex = compute_tex(
            tex_key.with_format(gl::RGBA16F),
            load_cs(asset!("shaders/reproject.glsl")),
            shader_uniforms!(
                constants: reproj_constants.clone(),
                inputTex: gbuffer_tex.clone()
            ),
        );

        let ssgi_tex = compute_tex(
            tex_key.with_format(gl::RGBA16F),
            load_cs(asset!("shaders/ssgi/ssgi.glsl")),
            shader_uniforms!(
                constants: ao_constants_buf.clone(),
                inputTex: gbuffer_tex.clone(),
                lightingTex: lighting_tex.clone(),
                depthTex: depth_tex.clone(),
                reprojectionTex: reprojection_tex.clone(),
                :bvh.clone(),
            ),
        );

        let normal_tex = compute_tex(
            tex_key.with_format(gl::R32UI),
            load_cs(asset!("shaders/extract_gbuffer_normal.glsl")),
            shader_uniforms!(inputTex: gbuffer_tex.clone()),
        );

        let ssgi_tex = compute_tex(
            tex_key.with_format(gl::RGBA16F),
            load_cs(asset!("shaders/ssgi/spatial_filter.glsl")),
            shader_uniforms!(
                ssgiTex: ssgi_tex,
                depthTex: depth_tex,
                normalTex: normal_tex,
            ),
        );

        let temporal_accum =
            filter_ssgi_temporally(ssgi_tex, reprojection_tex, tex_key.with_format(gl::RGBA16F));

        let ssgi_tex = temporal_accum.tex.clone();

        let rt_shadows_tex = sub_passes
            .add(RtShadows::new(
                tex_key,
                gbuffer_tex.clone(),
                bvh,
                light_controller.clone(),
            ))
            .get_output_tex();

        lighting_tex.rebind(compute_tex(
            tex_key.with_format(gl::R11F_G11F_B10F),
            load_cs(asset!("shaders/ssgi/merge.glsl")),
            shader_uniforms!(
            aoTex: ssgi_tex.clone(),
            shadowsTex: rt_shadows_tex,
            gbuffer: gbuffer_tex.clone(),
            skyTex: sky_lambert_tex,
            constants: merge_constants_buf.clone()),
        ));

        let out_tex = compute_tex(
            tex_key.with_format(gl::R11F_G11F_B10F),
            load_cs(asset!("shaders/ssgi/debug.glsl")),
            shader_uniforms!(
                    finalTex: lighting_tex.clone(),
                    ssgiTex: ssgi_tex.clone(),
            ),
        );

        let light_controller = light_controller.clone();

        sub_passes.add(
            move |view_constants: &ViewConstants, _frame_state: &FrameState, frame_idx: u32| {
                let view_constants = *view_constants; // TODO
                raster_constants_buf.rebind(upload_buffer(view_constants));

                #[allow(dead_code)]
                #[derive(Clone, Copy)]
                struct SsgiConstants {
                    view_constants: ViewConstants,
                    frame_idx: u32,
                }

                ao_constants_buf.rebind(upload_buffer(SsgiConstants {
                    view_constants,
                    frame_idx,
                }));

                #[allow(dead_code)]
                #[derive(Clone, Copy)]
                #[repr(C)]
                struct MergeConstants {
                    view_constants: ViewConstants,
                    light_dir: Vector4,
                    frame_idx: u32,
                }

                merge_constants_buf.rebind(upload_buffer(MergeConstants {
                    view_constants: view_constants,
                    light_dir: light_controller.get().direction.to_homogeneous(),
                    frame_idx,
                }));

                #[derive(Clone, Copy)]
                #[repr(C)]
                struct ReprojConstants {
                    view_constants: ViewConstants,
                    prev_world_to_clip: Matrix4,
                }

                reproj_constants.rebind(upload_buffer(ReprojConstants {
                    view_constants: view_constants,
                    prev_world_to_clip: prev_world_to_clip,
                }));

                prev_world_to_clip = view_constants.view_to_clip * view_constants.world_to_view;
            },
        );

        TaaInput {
            gbuffer_tex,
            color_tex: out_tex,
        }
    });

    let out_tex = compute_tex(
        tex_key.with_format(gl::R11F_G11F_B10F),
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: taa.get_output_tex(),
            sharpen_amount: 0.4f32,
        ),
    );

    let mut frame_idx = 0;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);
        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height).finish();

        let theta = (frame_state.mouse.pos.x / frame_state.window_size_pixels.0 as f32)
            * std::f32::consts::PI
            * -2.0;
        let phi = (frame_state.mouse.pos.y / frame_state.window_size_pixels.1 as f32)
            * std::f32::consts::PI
            * 0.5;
        let light_dir = spherical_to_cartesian(theta, phi);

        light_controller.set(DirectionalLightState::new(light_dir));

        taa.prepare_frame(&view_constants, frame_state, frame_idx);

        sky_constants.rebind(upload_buffer(light_dir));

        frame_idx += 1;
        out_tex.clone()
    });
}

fn filter_ssgi_temporally(
    input: SnoozyRef<Texture>,
    reprojection_tex: SnoozyRef<Texture>,
    tex_key: TextureKey,
) -> rtoy_samples::TemporalAccumulation {
    let temporal_blend = const_f32(1f32).into_named();
    let mut accum_tex = load_tex(asset!("rendertoy::images/black.png")).into_named();
    accum_tex.rebind(compute_tex(
        tex_key,
        load_cs(asset!("shaders/ssgi/temporal_filter.glsl")),
        shader_uniforms!(
            inputTex: input,
            historyTex: accum_tex.clone(),
            reprojectionTex: reprojection_tex,
        ),
    ));

    rtoy_samples::TemporalAccumulation {
        tex: accum_tex,
        temporal_blend,
    }
}