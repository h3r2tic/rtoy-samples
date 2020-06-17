use rendertoy::*;
use rtoy_rt::*;
use rtoy_samples::{rt_shadows::*, ssao::*, taa::*};

fn main() {
    let rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: 0,
    };

    let mesh = load_gltf_scene(
        asset!("meshes/flying_trabant_final_takeoff/scene.gltf"),
        1.0,
    );
    //let mesh = load_gltf_scene(asset!("meshes/honda_scrambler/scene.gltf"), 10.0);
    //let mesh = load_gltf_scene(asset!("meshes/helmetconcept/scene.gltf"), 100.0);
    //let mesh = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);
    let scene = vec![(mesh.clone(), Vec3::zero(), Quat::identity())];

    let mut camera = FirstPersonCamera::new(Vec3::new(0.0, 200.0, 800.0));
    camera.aspect = rtoy.width() as f32 / rtoy.height() as f32;
    camera.fov = 55.0;

    let light_controller = Rc::new(Cell::new(DirectionalLightState::new(Vec3::unit_x())));

    let mut taa = Taa::new(tex_key);
    taa.setup(|sub_passes| {
        let mut raster_constants_buf = upload_buffer(0u32).isolate();
        let mut merge_constants_buf = upload_buffer(0u32).isolate();

        let gbuffer_tex = raster_tex(
            tex_key.with_format(Format::R32G32B32A32_SFLOAT),
            make_raster_pipeline(vec![
                load_vs(asset!("shaders/raster_simple_vs.glsl")),
                load_ps(asset!("shaders/raster_gbuffer_ps.glsl")),
            ]),
            shader_uniforms!(
                constants: raster_constants_buf.clone(),
                :upload_raster_scene(&scene)
            ),
        );

        let ao_tex = sub_passes
            .add(Ssao::new(tex_key, gbuffer_tex.clone()))
            .get_output_tex();

        let rt_shadows_tex = sub_passes
            .add(RtShadows::new(
                tex_key,
                gbuffer_tex.clone(),
                upload_bvh(scene),
                light_controller.clone(),
            ))
            .get_output_tex();

        let lighting_tex = compute_tex(
            tex_key.with_format(Format::B10G11R11_UFLOAT_PACK32),
            load_cs(asset!("shaders/hybrid-render/merge.glsl")),
            shader_uniforms!(
            aoTex: ao_tex,
            shadowsTex: rt_shadows_tex,
            gbuffer: gbuffer_tex.clone(),
            constants: merge_constants_buf.clone()),
        );

        let light_controller = light_controller.clone();

        sub_passes.add(
            move |view_constants: &ViewConstants, _frame_state: &FrameState, frame_idx: u32| {
                raster_constants_buf.rebind(upload_buffer(*view_constants));

                #[allow(dead_code)]
                #[derive(Clone, Copy)]
                #[repr(C)]
                struct MergeConstants {
                    view_constants: ViewConstants,
                    light_dir: Vec4,
                    frame_idx: u32,
                }

                merge_constants_buf.rebind(upload_buffer(MergeConstants {
                    view_constants: *view_constants,
                    light_dir: light_controller.get().direction.extend(0.0),
                    frame_idx,
                }));
            },
        );

        TaaInput {
            gbuffer_tex,
            color_tex: lighting_tex,
        }
    });

    let out_tex = compute_tex(
        tex_key.with_format(Format::B10G11R11_UFLOAT_PACK32),
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: taa.get_output_tex(),
            sharpen_amount: 0.4f32,
        ),
    );

    let mut frame_idx = 0;
    //let mut light_angle = 1.7f32;

    #[allow(unused_mut)]
    let mut light_angle = 0.0f32;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);
        let view_constants = ViewConstants::build(&camera, tex_key.width, tex_key.height).build();

        taa.prepare_frame(&view_constants, frame_state, frame_idx);

        //light_angle += 0.01;
        light_controller.set(DirectionalLightState::new(
            Vec3::new(
                light_angle.cos(),
                //1.0 - frame_state.mouse.pos.y / frame_state.window_size_pixels.1 as f32,
                0.025,
                light_angle.sin(),
            )
            .normalize(),
        ));
        frame_idx += 1;

        out_tex.clone()
    });
}
