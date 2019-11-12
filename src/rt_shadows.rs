use rendertoy::*;
pub use std::cell::Cell;
pub use std::rc::Rc;

#[derive(Clone, Copy)]
pub struct DirectionalLightState {
    pub direction: Vector3,
}

impl DirectionalLightState {
    pub fn new(direction: Vector3) -> Self {
        Self { direction }
    }
}

pub struct RtShadows {
    rt_constants_buf: SnoozyRef<Buffer>,
    shadow_tex: SnoozyRef<Texture>,
    light_controller: Rc<Cell<DirectionalLightState>>,
}

impl RtShadows {
    pub fn new(
        tex_key: TextureKey,
        gbuffer_tex: SnoozyRef<Texture>,
        gpu_bvh: SnoozyRef<ShaderUniformBundle>,
        light_controller: Rc<Cell<DirectionalLightState>>,
    ) -> Self {
        let rt_constants_buf = upload_buffer(0u32).make_unique();
        let halfres_shadow_tex = compute_tex(
            tex_key.half_res().with_format(gl::R8),
            load_cs(asset!(
                "shaders/hybrid-adaptive-shadows/halfres_shadows.glsl"
            )),
            shader_uniforms!(
                constants: rt_constants_buf.clone(),
                gbufferTex: gbuffer_tex.clone(),
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
                gbufferTex: gbuffer_tex.clone(),
                tileAllocOffsetTex: tile_prefix_tex.clone(),
                rtPixelLocationTex: rt_pixel_location_tex.clone(),
                :gpu_bvh.clone(),
            ),
        );

        // Merge half-res and sparse shadows
        let shadow_tex = compute_tex(
            tex_key.with_format(gl::R8),
            load_cs(asset!("shaders/hybrid-adaptive-shadows/merge_shadows.glsl")),
            shader_uniforms!(
                constants: rt_constants_buf.clone(),
                //gbufferTex: gbuffer_tex.clone(),
                halfresShadowsTex: halfres_shadow_tex.clone(),
                discontinuityTex: discontinuity_tex.clone(),
                sparseShadowsTex: sparse_shadow_tex.clone(),
                :gpu_bvh.clone(),
            ),
        );

        Self {
            rt_constants_buf,
            shadow_tex,
            light_controller,
        }
    }

    pub fn get_output_tex(&self) -> SnoozyRef<Texture> {
        self.shadow_tex.clone()
    }
}

impl RenderPass for RtShadows {
    fn prepare_frame(
        &mut self,
        view_constants: &ViewConstants,
        _frame_state: &FrameState,
        _frame_idx: u32,
    ) {
        #[allow(dead_code)]
        #[derive(Clone, Copy)]
        #[repr(C)]
        struct Constants {
            view_constants: ViewConstants,
            light_dir: Vector4,
        }

        self.rt_constants_buf.rebind(upload_buffer(Constants {
            view_constants: *view_constants,
            light_dir: self.light_controller.get().direction.to_homogeneous(),
        }));
    }
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
