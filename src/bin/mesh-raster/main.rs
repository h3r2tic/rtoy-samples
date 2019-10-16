use rendertoy::*;

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    //let scene_file = "assets/meshes/lighthouse.obj.gz";
    //let scene_file = "assets/meshes/flying_trabant.obj.gz";
    let scene = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 5.0);

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0));

    let viewport_constants_buf = init_dynamic!(upload_buffer(0u32));

    let out_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_simple_ps.glsl")),
        ]),
        shader_uniforms!(
            "constants": viewport_constants_buf,
            "": upload_raster_mesh(make_raster_mesh(scene))
        ),
    );

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state, 1.0 / 60.0);

        let viewport_constants =
            ViewportConstants::build(&camera, tex_key.width, tex_key.height).finish();

        redef_dynamic!(viewport_constants_buf, upload_buffer(viewport_constants));

        out_tex
    });
}
