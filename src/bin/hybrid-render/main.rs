use rendertoy::*;
use rtoy_rt::*;

#[allow(dead_code)]
#[derive(Clone, Copy)]
struct MergeConstants {
    viewport_constants: ViewportConstants,
    light_dir: Vector4,
}

#[derive(Clone, Copy)]
#[repr(C)]
struct ReprojConstants {
    viewport_constants: ViewportConstants,
    prev_world_to_clip: Matrix4,
}

fn radical_inverse(mut n: u32, base: u32) -> f32 {
    let mut val = 0.0f32;
    let inv_base = 1.0f32 / base as f32;
    let mut inv_bi = inv_base;

    while n > 0 {
        let d_i = n % base;
        val += d_i as f32 * inv_bi;
        n = (n as f32 * inv_base) as u32;
        inv_bi *= inv_base;
    }

    val
}

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    let reproj_constants = init_dynamic!(upload_buffer(0u32));

    //let scene_file = "assets/meshes/lighthouse.obj.gz";
    let scene = load_gltf_scene(asset!("meshes/helmetconcept/scene.gltf"), 100.0);
    let bvh = vec![(
        scene.clone(),
        Vector3::new(0.0, 0.0, 0.0),
        UnitQuaternion::identity(),
    )];
    let gpu_bvh = upload_bvh(bvh);

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0));
    camera.aspect = rtoy.width() as f32 / rtoy.height() as f32;

    let raster_constants_buf = init_dynamic!(upload_buffer(0u32));

    let gbuffer_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
        ]),
        shader_uniforms!(
            constants: raster_constants_buf.clone(),
            instance_transform: raster_mesh_transform(Vector3::zeros(), UnitQuaternion::identity()),
            :upload_raster_mesh(make_raster_mesh(scene.clone()))
        ),
    );

    let mut ssao = rtoy_samples::ssao::Ssao::new(tex_key, gbuffer_tex.clone());
    let mut rt_shadows =
        rtoy_samples::rt_shadows::RtShadows::new(tex_key, gbuffer_tex.clone(), gpu_bvh);

    let merge_constants_buf = init_dynamic!(upload_buffer(0u32));
    let lighting_tex = compute_tex(
        tex_key.with_format(gl::R11F_G11F_B10F),
        load_cs(asset!("shaders/hybrid-render/merge.glsl")),
        shader_uniforms!(
            aoTex: ssao.get_output_tex(),
            shadowsTex: rt_shadows.get_output_tex(),
            gbuffer: gbuffer_tex.clone(),
            constants: merge_constants_buf.clone()),
    );

    let reprojection_tex = compute_tex(
        TextureKey {
            width: rtoy.width(),
            height: rtoy.height(),
            format: gl::RGBA16F,
        },
        load_cs(asset!("shaders/reproject.glsl")),
        shader_uniforms!(constants: reproj_constants.clone(), inputTex: gbuffer_tex.clone(),),
    );

    let temporal_accum =
        rtoy_samples::accumulate_reproject_temporally(lighting_tex, reprojection_tex, tex_key);

    let out_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: temporal_accum.tex.clone(),
            sharpen_amount: 0.4f32,
        ),
    );

    let mut light_angle = 2.5f32;
    let mut frame_idx = 0;

    let mut prev_world_to_clip = Matrix4::identity();

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        let jitter = Vector2::new(
            radical_inverse(frame_idx % 16, 2) - 0.5,
            radical_inverse(frame_idx % 16, 3) - 0.5,
        );

        let viewport_constants_no_jitter =
            ViewportConstants::build(&camera, tex_key.width, tex_key.height).finish();

        let viewport_constants = ViewportConstants::build(&camera, tex_key.width, tex_key.height)
            .pixel_offset(jitter)
            .finish();

        redef_dynamic!(raster_constants_buf, upload_buffer(viewport_constants));
        ssao.prepare_frame(viewport_constants_no_jitter, frame_idx);

        let light_dir = Vector3::new(light_angle.cos(), 0.5, light_angle.sin());
        rt_shadows.prepare_frame(viewport_constants, light_dir);

        redef_dynamic!(
            merge_constants_buf,
            upload_buffer(MergeConstants {
                viewport_constants: viewport_constants_no_jitter,
                light_dir: light_dir.to_homogeneous(),
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

        //light_angle += 0.01;
        frame_idx += 1;

        let m = camera.calc_matrices();
        prev_world_to_clip = m.view_to_clip * m.world_to_view;

        out_tex.clone()
    });
}
