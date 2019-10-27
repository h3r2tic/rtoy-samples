use rand::{rngs::SmallRng, Rng, SeedableRng};
use rand_distr::StandardNormal;
use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();
    let tex_key = TextureKey::fullscreen(&rtoy, gl::RGBA32F);

    let scene = load_gltf_scene(
        //asset!("meshes/flying_trabant_final_takeoff/scene.gltf"),
        asset!("meshes/the_lighthouse/scene.gltf"),
        1.0,
    );

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0));

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
            :upload_raster_mesh(make_raster_mesh(scene))
        ),
    );

    let mut ssao = rtoy_samples::ssao::Ssao::new(tex_key, gbuffer_tex);

    let out_tex = compute_tex!(
        "splat red to rgb",
        tex_key.with_format(gl::R11F_G11F_B10F),
        #input: ssao.get_output_tex(),
        .rgb = @input.rrr
    );

    let out_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/tonemap_sharpen.glsl")),
        shader_uniforms!(
            inputTex: out_tex,
            sharpen_amount: 0.4f32,
        ),
    );

    let mut frame_idx = 0;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        ssao.prepare_frame(
            frame_idx,
            ViewportConstants::build(&camera, tex_key.width, tex_key.height).finish(),
        );

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

        frame_idx += 1;
        out_tex.clone()
    });
}
