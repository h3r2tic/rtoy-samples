#[macro_use]
extern crate snoozy_macros;

use rendertoy::*;
// use snoozy::*;
use std::sync::Arc;

#[snoozy]
pub async fn raster_oit_snoozy(
    mut ctx: Context,
    key: &TextureKey,
    raster_pipe: &SnoozyRef<RasterPipeline>,
    uniforms: &Vec<ShaderUniformHolder>,
    rwtex: &SnoozyRef<Texture>,
    rwtex2: &SnoozyRef<Texture>,
) -> Result<(Texture, Texture)> {
    let output_tex = create_texture(*key);
    let rwtex = (*ctx.get(rwtex).await?).clone();
    let rwtex2 = (*ctx.get(rwtex2).await?).clone();
    //let rwtex = create_texture(key.with_format(Format::R32G32B32A32_SFLOAT));

    let mut uniforms = resolve_uniforms(ctx.clone(), uniforms.clone()).await?;

    uniforms.push(ResolvedShaderUniformHolder {
        name: "outputTex".to_owned(),
        payload: ResolvedShaderUniformPayload {
            value: ResolvedShaderUniformValue::RwTexture(output_tex.clone()),
            warn_if_unreferenced: false,
        },
    });

    uniforms.push(ResolvedShaderUniformHolder {
        name: "rwtex".to_owned(),
        payload: ResolvedShaderUniformPayload {
            value: ResolvedShaderUniformValue::RwTexture(rwtex.clone()),
            warn_if_unreferenced: true,
        },
    });

    uniforms.push(ResolvedShaderUniformHolder {
        name: "rwtex2".to_owned(),
        payload: ResolvedShaderUniformPayload {
            value: ResolvedShaderUniformValue::RwTexture(rwtex2.clone()),
            warn_if_unreferenced: true,
        },
    });

    raster_tex_common(
        ctx,
        output_tex,
        raster_pipe,
        uniforms,
        [1.0, 1.0, 1.0, 1.0],
        &[
            ShaderOutput::mutate_texture(&rwtex),
            ShaderOutput::mutate_texture(&rwtex2),
        ],
    )
    .await?;

    Ok((rwtex, rwtex2))
}

#[snoozy]
pub async fn snoozy_map_snoozy<
    In: 'static + Send + Sync,
    Out: 'static + Send + Sync,
    F: (Fn(Arc<In>) -> Out) + 'static + Send + Sync,
>(
    mut ctx: Context,
    val: &SnoozyRef<In>,
    f: &F,
) -> Result<Out> {
    let val = ctx.get(val).await?;
    Ok(f(val))
}

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey::new(rtoy.width(), rtoy.height(), Format::R32G32B32A32_SFLOAT);

    let mut scene = Vec::new();
    for i in 0..5 {
        scene.push((
            load_gltf_scene(asset!("meshes/xyz_rgb_dragon/scene.gltf"), 3.0),
            Vec3::new(-800.0 + i as f32 * -400.0, 50.0, 0.0),
            Quat::from_rotation_y(-0.4),
        ));
    }
    scene.append(&mut vec![
        (
            //load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0),
            load_gltf_scene(
                asset!("meshes/flying_trabant_final_takeoff/scene.gltf"),
                1.0,
            ),
            Vec3::new(-300.0, 0.0, 0.0),
            Quat::identity(),
        ),
        (
            load_gltf_scene(asset!("meshes/dredd/scene.gltf"), 5.0),
            Vec3::new(000.0, 0.0, 0.0),
            Quat::identity(),
        ),
        (
            load_gltf_scene(asset!("meshes/knight_artorias/scene.gltf"), 0.1),
            Vec3::new(300.0, 0.0, 0.0),
            Quat::identity(),
        ),
    ]);

    let mut scene_bundle = upload_dynamic_raster_scene(scene.clone()).isolate();

    let mut use_reservoir = false;
    let mut camera = FirstPersonCamera::new(Vec3::new(0.0, 100.0, 500.0));
    //camera.move_smoothness *= 30.0;
    //camera.look_smoothness *= 30.0;

    let mut viewport_constants_buf = upload_buffer(0u32).isolate();
    let mut frag_constants = upload_buffer(0u32).isolate();
    let mut frag_constants2 = upload_buffer(0u32).isolate();

    let rwtex = compute_tex(
        tex_key.with_format(Format::R32G32B32A32_UINT),
        load_cs(asset!("shaders/stochastic_transparency_init.glsl")),
        shader_uniforms!(),
    )
    .isolate()
    .evaluate();

    let rwtex2 = compute_tex(
        tex_key.with_format(Format::R32G32B32A32_UINT),
        load_cs(asset!("shaders/stochastic_transparency_init.glsl")),
        shader_uniforms!(),
    )
    .isolate()
    .evaluate();

    let reservoir_out = raster_oit(
        tex_key,
        make_raster_pipeline(
            vec![
                load_vs(asset!("shaders/raster_simple_vs.glsl")),
                load_ps(asset!("shaders/raster_reservoir_oit_ps.glsl")),
            ],
            RasterPipelineOptions::new().face_cull(false),
        ),
        shader_uniforms!(
            constants: viewport_constants_buf.clone(),
            frag_constants: frag_constants.clone(),
            blue_noise_tex: load_tex_with_params(
                asset!("images/bluenoise/256_256/LDR_RGBA_0.png"), TexParams {
                gamma: TexGamma::Linear,
            }),
            :scene_bundle.clone(),
        ),
        rwtex.clone(),
        rwtex2.clone(),
    );

    let reservoir_out_tex = snoozy_map(reservoir_out.clone(), |t: Arc<(Texture, Texture)>| {
        (*t).0.clone()
    });
    let reservoir_out2_tex = snoozy_map(reservoir_out.clone(), |t: Arc<(Texture, Texture)>| {
        (*t).1.clone()
    });

    let reservoir_out_tex = compute_tex(
        tex_key.with_format(Format::B10G11R11_UFLOAT_PACK32),
        load_cs(asset!("shaders/stochastic_transparency_finish.glsl")),
        shader_uniforms!(inputTex: reservoir_out_tex, inputTex2: reservoir_out2_tex,),
    );

    let mut reservoir_out_accum_tex = load_tex(asset!("rendertoy::images/black.png")).isolate();
    reservoir_out_accum_tex.rebind(compute_tex(
        tex_key,
        load_cs(asset!("shaders/blend.glsl")),
        shader_uniforms!(
            inputTex1: reservoir_out_accum_tex.prev(),
            inputTex2: reservoir_out_tex,
            blendAmount: 0.2f32,
        ),
    ));

    let regular_out_tex = raster_tex(
        tex_key,
        make_raster_pipeline(
            vec![
                load_vs(asset!("shaders/raster_simple_vs.glsl")),
                load_ps(asset!("shaders/raster_stochastic_transparency_ps.glsl")),
            ],
            RasterPipelineOptions::new().face_cull(false),
        ),
        [0.9, 0.9, 0.9, 1.0],
        shader_uniforms!(
            constants: viewport_constants_buf.clone(),
            frag_constants: frag_constants.clone(),
            blue_noise_tex: load_tex_with_params(
                asset!("images/bluenoise/256_256/LDR_RGBA_0.png"), TexParams {
                gamma: TexGamma::Linear,
            }),
            :scene_bundle.clone(),
        ),
    );

    let regular_out_tex2 = raster_tex(
        tex_key,
        make_raster_pipeline(
            vec![
                load_vs(asset!("shaders/raster_simple_vs.glsl")),
                load_ps(asset!("shaders/raster_stochastic_transparency_ps.glsl")),
            ],
            RasterPipelineOptions::new().face_cull(false),
        ),
        [0.9, 0.9, 0.9, 1.0],
        shader_uniforms!(
            constants: viewport_constants_buf.clone(),
            frag_constants: frag_constants2.clone(),
            blue_noise_tex: load_tex_with_params(
                asset!("images/bluenoise/256_256/LDR_RGBA_0.png"), TexParams {
                gamma: TexGamma::Linear,
            }),
            :scene_bundle.clone(),
        ),
    );

    let regular_out_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/avg.glsl")),
        shader_uniforms!(inputTex1: regular_out_tex, inputTex2: regular_out_tex2,),
    );

    let mut regular_out_accum_tex = load_tex(asset!("rendertoy::images/black.png")).isolate();
    regular_out_accum_tex.rebind(compute_tex(
        tex_key,
        load_cs(asset!("shaders/blend.glsl")),
        shader_uniforms!(
            inputTex1: regular_out_accum_tex.prev(),
            inputTex2: regular_out_tex,
            blendAmount: 0.2f32,
        ),
    ));

    let mut frame_idx = 0u32;

    rtoy.draw_forever(move |frame_state| {
        camera.update(frame_state);

        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height).build();
        viewport_constants_buf.rebind(upload_buffer(view_constants));

        if frame_state.keys.was_just_pressed(VirtualKeyCode::Space) {
            use_reservoir = !use_reservoir;
        }

        let mut scene_modified = false;

        if frame_state.keys.is_down(VirtualKeyCode::Back) {
            for (_, _, rot) in scene.iter_mut() {
                *rot *= Quat::from_rotation_y(frame_state.dt);
            }
            scene_modified = true;
        }

        if frame_state.keys.is_down(VirtualKeyCode::Return) {
            use rand::seq::SliceRandom;
            use rand::thread_rng;
            scene.shuffle(&mut thread_rng());
            scene_modified = true;
        }

        if scene_modified {
            scene_bundle.rebind(upload_dynamic_raster_scene(scene.clone()));
        }

        frame_idx += 1;

        #[derive(Clone, Copy)]
        #[repr(C)]
        struct FragConsts {
            view_constants: ViewConstants,
            frame_idx: u32,
        }

        frag_constants.rebind(upload_buffer(FragConsts {
            view_constants,
            frame_idx,
        }));

        frag_constants2.rebind(upload_buffer(FragConsts {
            view_constants,
            frame_idx: frame_idx + 16,
        }));

        if use_reservoir {
            rwtex.invalidate();
            rwtex2.invalidate();
            reservoir_out_accum_tex.clone()
        } else {
            regular_out_accum_tex.clone()
        }
    });
}
