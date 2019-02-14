use rendertoy::*;

#[derive(Clone, Copy)]
#[repr(C)]
struct Constants {
    viewport_constants: ViewportConstants,
}

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    //let scene_file = "assets/meshes/lighthouse.obj.gz";
    let scene_file = "assets/meshes/flying_trabant.obj.gz";

    let mut camera =
        CameraConvergenceEnforcer::new(FirstPersonCamera::new(Point3::new(0.0, 100.0, 500.0)));

    let viewport_constants_buf =
        init_named!("ViewportConstants", upload_buffer(to_byte_vec(vec![0])));

    let out_tex = raster_tex(
        tex_key,
        make_raster_pipeline(vec![
            load_vs(asset!("shaders/raster_simple_vs.glsl")),
            load_ps(asset!("shaders/raster_simple_ps.glsl")),
        ]),
        shader_uniforms!(
            "constants": viewport_constants_buf,
            "": make_raster_mesh(load_obj_scene(scene_file.to_string()))
        ),
    );

    rtoy.forever(|snapshot, frame_state| {
        camera.update(
            FirstPersonCameraInput::from_frame_state(&frame_state),
            1.0 / 60.0,
        );

        let camera_matrices = camera.calc_matrices();

        let viewport_constants =
            ViewportConstants::build(camera_matrices, tex_key.width, tex_key.height).finish();

        redef_named!(
            viewport_constants_buf,
            upload_buffer(to_byte_vec(vec![Constants { viewport_constants },]))
        );

        draw_fullscreen_texture(&*snapshot.get(out_tex), frame_state.window_size_pixels);
    });
}