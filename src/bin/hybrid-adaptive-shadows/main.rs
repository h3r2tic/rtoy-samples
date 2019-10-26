use rendertoy::*;
use rtoy_rt::*;

#[allow(dead_code)]
#[derive(Clone, Copy)]
struct Constants {
    viewport_constants: ViewportConstants,
    light_dir: Vector4,
}

fn prefix_scan_2d(tex: SnoozyRef<Texture>, tex_key: &TextureKey) -> SnoozyRef<Texture> {
    let tex_prefix_horiz = compute_tex(
        tex_key.padded(1, 0),
        load_cs(asset!(
            "shaders/hybrid-adaptive-shadows/prefix_scan_2d_horizontal.glsl"
        )),
        shader_uniforms!(inputTex: tex),
    );

    let tex_prefix_vert = compute_tex(
        tex_key.with_width(1).padded(0, 1),
        load_cs(asset!(
            "shaders/hybrid-adaptive-shadows/prefix_scan_2d_vertical.glsl"
        )),
        shader_uniforms!(inputTex: tex_prefix_horiz.clone()),
    );

    compute_tex(
        tex_key.padded(1, 0),
        load_cs(asset!(
            "shaders/hybrid-adaptive-shadows/prefix_scan_2d_merge.glsl"
        )),
        shader_uniforms!(
            horizontalInputTex: tex_prefix_horiz,
            verticalInputTex: tex_prefix_vert
        ),
    )
}

fn main() {
    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: rtoy.width(),
        height: rtoy.height(),
        format: gl::RGBA32F,
    };

    //let scene_file = "assets/meshes/lighthouse.obj.gz";
    let scene = load_gltf_scene(asset!("meshes/the_lighthouse/scene.gltf"), 1.0);
    let bvh = vec![(
        scene.clone(),
        Vector3::new(0.0, 0.0, 0.0),
        UnitQuaternion::identity(),
    )];
    let gpu_bvh = upload_bvh(bvh);

    let mut camera = FirstPersonCamera::new(Point3::new(0.0, 200.0, 800.0));

    let rt_constants_buf = init_dynamic!(upload_buffer(0u32));
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

    let halfres_shadow_tex = compute_tex(
        tex_key.half_res().with_format(gl::R8),
        load_cs(asset!(
            "shaders/hybrid-adaptive-shadows/halfres_shadows.glsl"
        )),
        shader_uniforms!(
            constants: rt_constants_buf.clone(),
            inputTex: gbuffer_tex.clone(),
            :gpu_bvh.clone(),
        ),
    );

    let discontinuity_tex_key = tex_key.half_res().with_format(gl::R8);

    // Calculate a half-res discontinuity map
    let discontinuity_tex = compute_tex(
        discontinuity_tex_key,
        load_cs(asset!(
            "shaders/hybrid-adaptive-shadows/discontinuity_detect.glsl"
        )),
        shader_uniforms!(inputTex: halfres_shadow_tex.clone(),),
    );

    let tile_tex_key = discontinuity_tex_key
        .res_div_round_up(8, 8)
        .with_format(gl::R32F);

    // Reduce the discontinuity map 8x into tiles of discontinuity counts
    let discontinuity_tile_tex = compute_tex(
        tile_tex_key,
        load_cs(asset!(
            "shaders/hybrid-adaptive-shadows/discontinuity_tile_reduce.glsl"
        )),
        shader_uniforms!(inputTex: discontinuity_tex.clone()),
    );

    // Run a prefix scan over tiles to allocate space
    let tile_prefix_tex = prefix_scan_2d(discontinuity_tile_tex, &tile_tex_key);

    // Allocate individual pixels within tile space
    let rt_pixel_location_tex = compute_tex(
        tex_key.half_res().with_format(gl::RG32F),
        load_cs(asset!(
            "shaders/hybrid-adaptive-shadows/alloc_rt_pixel_locations.glsl"
        )),
        shader_uniforms!(
            discontinuityTex: discontinuity_tex.clone(),
            tileAllocOffsetTex: tile_prefix_tex.clone(),
        ),
    );

    // Calculate the sparse shadows
    let sparse_shadow_tex = compute_tex(
        tex_key.with_format(gl::R8),
        load_cs(asset!(
            "shaders/hybrid-adaptive-shadows/sparse_shadows_trace.glsl"
        )),
        shader_uniforms!(
            constants: rt_constants_buf.clone(),
            inputTex: gbuffer_tex.clone(),
            discontinuityTex: discontinuity_tex.clone(),
            tileAllocOffsetTex: tile_prefix_tex.clone(),
            rtPixelLocationTex: rt_pixel_location_tex.clone(),
            :gpu_bvh.clone(),
        ),
    );

    // Merge half-res and sparse shadows
    let shadow_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/hybrid-adaptive-shadows/merge_shadows.glsl")),
        shader_uniforms!(
            constants: rt_constants_buf.clone(),
            inputTex: gbuffer_tex.clone(),
            halfresShadowsTex: halfres_shadow_tex.clone(),
            discontinuityTex: discontinuity_tex.clone(),
            sparseShadowsTex: sparse_shadow_tex.clone(),
            :gpu_bvh.clone(),
        ),
    );

    let mut light_angle = 1.0f32;

    rtoy.draw_forever(|frame_state| {
        camera.update(frame_state);

        let viewport_constants =
            ViewportConstants::build(&camera, tex_key.width, tex_key.height).finish();

        redef_dynamic!(raster_constants_buf, upload_buffer(viewport_constants));

        redef_dynamic!(
            rt_constants_buf,
            upload_buffer(Constants {
                viewport_constants,
                light_dir: Vector4::new(light_angle.cos(), 0.5, light_angle.sin(), 0.0)
            })
        );

        light_angle += 0.01;

        shadow_tex.clone()
    });
}
