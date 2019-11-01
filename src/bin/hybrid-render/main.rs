use rendertoy::*;
use rtoy_rt::*;

#[allow(dead_code)]
#[derive(Clone, Copy)]
struct MergeConstants {
    viewport_constants: ViewportConstants,
    light_dir: Vector4,
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

struct Taa {
    taa_constants: SnoozyRef<Buffer>,
    temporal_accum: rtoy_samples::TemporalAccumulation,
    reproj_constants: SnoozyRef<Buffer>,
    prev_world_to_clip: Matrix4,
}

impl Taa {
    pub fn new(
        tex_key: TextureKey,
        gbuffer_tex: SnoozyRef<Texture>,
        color_tex: SnoozyRef<Texture>,
    ) -> Self {
        let taa_constants = upload_buffer(0u32).into_dynamic();
        let reproj_constants = upload_buffer(0u32).into_dynamic();

        let reprojection_tex = compute_tex(
            //tex_key.with_format(gl::RGBA16F),
            tex_key.with_format(gl::RGBA32F),
            load_cs(asset!("shaders/reproject.glsl")),
            shader_uniforms!(
                constants: reproj_constants.clone(),
                inputTex: gbuffer_tex.clone()
            ),
        );

        /*let temporal_accum = rtoy_samples::accumulate_reproject_temporally(
            color_tex,
            reprojection_tex,
            tex_key.with_format(gl::R11F_G11F_B10F),
        );*/
        let temporal_blend = const_f32(1f32).into_dynamic();

        let mut accum_tex = load_tex(asset!("rendertoy::images/black.png")).into_dynamic();
        accum_tex.rebind(compute_tex(
            //tex_key.with_format(gl::RGBA16F),
            tex_key.with_format(gl::RGBA32F),
            load_cs(asset!("shaders/taa.glsl")),
            shader_uniforms!(
                inputTex: color_tex,
                historyTex: accum_tex.clone(),
                reprojectionTex: reprojection_tex,
                constants: taa_constants.clone(),
            ),
        ));

        let temporal_accum = rtoy_samples::TemporalAccumulation {
            tex: accum_tex,
            temporal_blend,
        };

        Self {
            taa_constants,
            temporal_accum,
            reproj_constants,
            prev_world_to_clip: Matrix4::identity(),
        }
    }

    pub fn prepare_frame(
        &mut self,
        viewport_constants: ViewportConstants,
        frame_idx: u32,
        jitter: Vector2,
    ) {
        self.temporal_accum.prepare_frame(frame_idx);

        #[derive(Clone, Copy)]
        #[repr(C)]
        struct TaaConstants {
            jitter: (f32, f32),
        }

        self.taa_constants.rebind(upload_buffer(TaaConstants {
            jitter: (jitter.x, jitter.y),
        }));

        #[derive(Clone, Copy)]
        #[repr(C)]
        struct ReprojConstants {
            viewport_constants: ViewportConstants,
            prev_world_to_clip: Matrix4,
        }

        self.reproj_constants.rebind(upload_buffer(ReprojConstants {
            viewport_constants,
            prev_world_to_clip: self.prev_world_to_clip,
        }));

        self.prev_world_to_clip =
            viewport_constants.view_to_clip * viewport_constants.world_to_view;
    }

    pub fn get_output_tex(&self) -> SnoozyRef<Texture> {
        self.temporal_accum.tex.clone()
    }
}

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    let scene = load_gltf_scene(asset!("meshes/honda_scrambler/scene.gltf"), 10.0);
    //let scene = load_gltf_scene(asset!("meshes/helmetconcept/scene.gltf"), 100.0);
    //let scene = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);
    let bvh = vec![(
        scene.clone(),
        Vector3::new(0.0, 0.0, 0.0),
        UnitQuaternion::identity(),
    )];
    let gpu_bvh = upload_bvh(bvh);

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0));
    camera.aspect = rtoy.width() as f32 / rtoy.height() as f32;

    let mut raster_constants_buf = upload_buffer(0u32).into_dynamic();

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

    let mut merge_constants_buf = upload_buffer(0u32).into_dynamic();
    let lighting_tex = compute_tex(
        tex_key.with_format(gl::R11F_G11F_B10F),
        load_cs(asset!("shaders/hybrid-render/merge.glsl")),
        shader_uniforms!(
            aoTex: ssao.get_output_tex(),
            shadowsTex: rt_shadows.get_output_tex(),
            gbuffer: gbuffer_tex.clone(),
            constants: merge_constants_buf.clone()),
    );

    let mut taa = Taa::new(tex_key, gbuffer_tex, lighting_tex);

    let out_tex = compute_tex(
        tex_key.with_format(gl::R11F_G11F_B10F),
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: taa.get_output_tex(),
            sharpen_amount: 0.4f32,
            //sharpen_amount: 0.0f32,
        ),
    );

    //let mut light_angle = 1.7f32;
    let light_angle = 0.5f32;
    let mut frame_idx = 0;

    let poisson = vec![
        Vector2::new(-0.9135136592216178, -0.40462640701835195),
        Vector2::new(0.082167225654306, 0.980453017993303),
        Vector2::new(0.0721876140306982, -0.9945465264125127),
        Vector2::new(0.9752658681929658, -0.21056028303849572),
        Vector2::new(-0.7624083502300749, 0.6404811449040694),
        Vector2::new(0.8305562106591965, 0.5558133679523944),
        Vector2::new(0.4879528508829686, -0.49916506376489883),
        Vector2::new(-0.3378654109721166, -0.5580551154567451),
        Vector2::new(-0.5626647624924962, -0.0033572372653002283),
        Vector2::new(0.30261393847514306, 0.4682954578988519),
        Vector2::new(0.5521055408091617, 0.04806767993661225),
        Vector2::new(-0.11066519414731835, 0.5221220330664509),
        Vector2::new(0.10316202363615408, -0.41685718418903095),
        Vector2::new(-0.36318095192575917, 0.8589552754682322),
        Vector2::new(-0.9683057185504641, 0.16482264428421214),
        Vector2::new(-0.45610322605475107, 0.4070447233948135),
        Vector2::new(0.4934005858104175, 0.8485539011139696),
        Vector2::new(0.9552155171421254, 0.18143592265706823),
        Vector2::new(-0.3293469161752369, -0.9136951084651815),
        Vector2::new(0.3494539960865413, -0.8319063858893272),
        Vector2::new(0.616075913899782, 0.3476312772330385),
        Vector2::new(-0.2861479029680008, -0.23010553043954424),
        Vector2::new(0.3120249999841332, -0.12208179967965951),
        Vector2::new(0.8388781829227475, -0.5256032052802209),
        Vector2::new(-0.6309926114050529, -0.746963777599633),
        Vector2::new(-0.584692585892695, -0.33884453413279914),
        Vector2::new(-0.060330027511877625, -0.707601265763343),
        Vector2::new(-0.19914839439519164, 0.19243890589468077),
        Vector2::new(-0.815199930667029, 0.3759363252279692),
        Vector2::new(-0.8920618153449156, -0.12331721138773649),
        Vector2::new(0.21366746949323107, 0.17085573918730404),
    ];

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        /*let scramble: u32 = rand::random();
        let jitter = Vector2::new(
            radical_inverse(scramble % 64 + 1, 2) - 0.5,
            radical_inverse(scramble % 64 + 1, 3) - 0.5,
        );*/
        let jitter = poisson[frame_idx as usize % 31] * 0.5;
        //let jitter = Vector2::new(0.0, 0.0);

        let viewport_constants_no_jitter =
            ViewportConstants::build(&camera, tex_key.width, tex_key.height).finish();

        let viewport_constants = ViewportConstants::build(&camera, tex_key.width, tex_key.height)
            .pixel_offset(jitter)
            .finish();

        raster_constants_buf.rebind(upload_buffer(viewport_constants));
        ssao.prepare_frame(viewport_constants_no_jitter, frame_idx);

        let light_dir = Vector3::new(light_angle.cos(), 0.5, light_angle.sin());
        rt_shadows.prepare_frame(viewport_constants, light_dir);

        taa.prepare_frame(viewport_constants_no_jitter, frame_idx, jitter);

        merge_constants_buf.rebind(upload_buffer(MergeConstants {
            viewport_constants: viewport_constants_no_jitter,
            light_dir: light_dir.to_homogeneous(),
        }));

        //light_angle += 0.01;
        frame_idx += 1;

        out_tex.clone()
    });
}
