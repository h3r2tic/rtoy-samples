use rendertoy::*;
use rtoy_rt::*;

fn calculate_view_consants(width: u32, height: u32, yaw: f32, frame_idx: u32) -> Constants {
    use rand::{distributions::StandardNormal, rngs::SmallRng, Rng, SeedableRng};

    let mut rng = SmallRng::seed_from_u64(frame_idx as u64);

    let view_to_clip = {
        let fov = 35.0f32.to_radians();
        let znear = 0.01;

        let h = (0.5 * fov).cos() / (0.5 * fov).sin();
        let w = h * (height as f32 / width as f32);

        let mut m = Matrix4::zeros();
        m.m11 = w;
        m.m22 = h;
        m.m34 = znear;
        m.m43 = -1.0;

        // Temporal jitter
        m.m13 = (1.0 * rng.sample(StandardNormal)) as f32 / width as f32;
        m.m23 = (1.0 * rng.sample(StandardNormal)) as f32 / height as f32;

        m
    };
    let clip_to_view = view_to_clip.try_inverse().unwrap();

    let distance = 170.0 * 5.0;
    let look_at_height = 30.0 * 5.0;

    //let view_to_world = Matrix4::new_translation(&Vector3::new(0.0, 0.0, -2.0));
    let world_to_view = Isometry3::look_at_rh(
        &Point3::new(
            yaw.cos() * distance,
            look_at_height + distance * 0.1,
            yaw.sin() * distance,
        ),
        &Point3::new(0.0, look_at_height, 0.0),
        &Vector3::y(),
    );
    let view_to_world: Matrix4 = world_to_view.inverse().into();
    let _world_to_view: Matrix4 = world_to_view.into();

    Constants {
        clip_to_view,
        view_to_world,
        frame_idx,
    }
}

#[derive(Clone, Copy)]
#[repr(C)]
struct Constants {
    clip_to_view: Matrix4,
    view_to_world: Matrix4,
    frame_idx: u32,
}

fn main() {
    let scene_file = "assets/meshes/flying_trabant.obj.gz";
    //let scene_file = "assets/meshes/lighthouse.obj.gz";

    let bvh = build_gpu_bvh(load_obj_scene(scene_file.to_string()));

    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    let viewport_constants = init_named!(
        "ViewportConstants",
        upload_buffer(to_byte_vec(vec![calculate_view_consants(
            tex_key.width,
            tex_key.height,
            4.5,
            0
        )]))
    );

    let rt_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/raytrace.glsl")),
        shader_uniforms!("constants": viewport_constants, "": bvh),
    );

    let accum_rt_tex = init_named!(
        "Accum rt texture",
        load_tex(asset!("rendertoy::images/black.png"))
    );

    let temporal_blend = init_named!("Temporal blend", const_f32(1f32));

    redef_named!(
        accum_rt_tex,
        compute_tex(
            tex_key,
            load_cs(asset!("shaders/blend.glsl")),
            shader_uniforms!(
                "inputTex1": accum_rt_tex,
                "inputTex2": rt_tex,
                "blendAmount": temporal_blend,
            )
        )
    );

    let sharpened_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/adaptive_sharpen.glsl")),
        shader_uniforms!("inputTex": accum_rt_tex),
    );

    let mut gpu_time_ms = 0.0f64;
    let mut frame_idx = 0;
    let mut prev_mouse_pos_x = 0.0;

    const MAX_ACCUMULATED_FRAMES: u32 = 32 * 1024;

    rtoy.forever(|snapshot, frame_state| {
        if prev_mouse_pos_x != frame_state.mouse_pos.x {
            frame_idx = 0;
            prev_mouse_pos_x = frame_state.mouse_pos.x;
        }

        redef_named!(temporal_blend, const_f32(1.0 / (frame_idx as f32 + 1.0)));

        redef_named!(
            viewport_constants,
            upload_buffer(to_byte_vec(vec![calculate_view_consants(
                tex_key.width,
                tex_key.height,
                3.5 + frame_state.mouse_pos.x.to_radians() * 0.2,
                frame_idx
            )]))
        );

        draw_fullscreen_texture(&*snapshot.get(sharpened_tex));

        let cur = frame_state.gpu_time_ms;
        let prev = gpu_time_ms.max(cur * 0.85).min(cur / 0.85);
        gpu_time_ms = prev * 0.95 + cur * 0.05;
        print!("Frame time: {:.2} ms           \r", gpu_time_ms);

        use std::io::Write;
        let _ = std::io::stdout().flush();

        frame_idx = (frame_idx + 1).min(MAX_ACCUMULATED_FRAMES);
    });
}
