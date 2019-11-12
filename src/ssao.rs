use rendertoy::*;

fn filter_ssao_temporally(
    input: SnoozyRef<Texture>,
    reprojection_tex: SnoozyRef<Texture>,
    tex_key: TextureKey,
) -> crate::TemporalAccumulation {
    let temporal_blend = const_f32(1f32).isolate();
    let mut accum_tex = load_tex(asset!("rendertoy::images/black.png")).isolate();
    accum_tex.rebind(compute_tex(
        tex_key,
        load_cs(asset!("shaders/ssao_temporal_filter.glsl")),
        shader_uniforms!(
            inputTex: input,
            historyTex: accum_tex.clone(),
            reprojectionTex: reprojection_tex,
        ),
    ));

    crate::TemporalAccumulation {
        tex: accum_tex,
        temporal_blend,
    }
}

pub struct Ssao {
    temporal_accum: crate::TemporalAccumulation,
    ao_constants_buf: SnoozyRef<Buffer>,
    reproj_constants: SnoozyRef<Buffer>,
    prev_world_to_clip: Matrix4,
}

impl Ssao {
    pub fn new(tex_key: TextureKey, gbuffer_tex: SnoozyRef<Texture>) -> Self {
        let ao_constants_buf = upload_buffer(0u32).isolate();
        let reproj_constants = upload_buffer(0u32).isolate();

        let reprojection_tex = compute_tex(
            tex_key.with_format(gl::RGBA16F),
            load_cs(asset!("shaders/reproject.glsl")),
            shader_uniforms!(
                constants: reproj_constants.clone(),
                inputTex: gbuffer_tex.clone()
            ),
        );

        let depth_tex = compute_tex(
            tex_key.with_format(gl::R16F),
            load_cs(asset!("shaders/extract_gbuffer_depth.glsl")),
            shader_uniforms!(inputTex: gbuffer_tex.clone()),
        );

        let ao_tex = compute_tex(
            tex_key.with_format(gl::R16F),
            load_cs(asset!("shaders/ssao.glsl")),
            shader_uniforms!(
                constants: ao_constants_buf.clone(),
                inputTex: gbuffer_tex.clone(),
                depthTex: depth_tex.clone()
            ),
        );

        let normal_tex = compute_tex(
            tex_key.with_format(gl::R32UI),
            load_cs(asset!("shaders/extract_gbuffer_normal.glsl")),
            shader_uniforms!(inputTex: gbuffer_tex),
        );

        let ao_tex = compute_tex(
            tex_key.with_format(gl::R8),
            load_cs(asset!("shaders/ssao_spatial_filter.glsl")),
            shader_uniforms!(aoTex: ao_tex, depthTex: depth_tex, normalTex: normal_tex,),
        );

        let temporal_accum =
            filter_ssao_temporally(ao_tex, reprojection_tex, tex_key.with_format(gl::R16F));

        Self {
            temporal_accum,
            ao_constants_buf,
            reproj_constants,
            prev_world_to_clip: Matrix4::identity(),
        }
    }

    pub fn get_output_tex(&self) -> SnoozyRef<Texture> {
        self.temporal_accum.tex.clone()
    }
}

impl RenderPass for Ssao {
    fn prepare_frame(
        &mut self,
        view_constants: &ViewConstants,
        frame_state: &FrameState,
        frame_idx: u32,
    ) {
        self.temporal_accum
            .prepare_frame(view_constants, frame_state, frame_idx);

        #[allow(dead_code)]
        #[derive(Clone, Copy)]
        struct Constants {
            view_constants: ViewConstants,
            frame_idx: u32,
        }

        self.ao_constants_buf.rebind(upload_buffer(Constants {
            view_constants: *view_constants,
            frame_idx,
        }));

        #[derive(Clone, Copy)]
        #[repr(C)]
        struct ReprojConstants {
            view_constants: ViewConstants,
            prev_world_to_clip: Matrix4,
        }

        self.reproj_constants.rebind(upload_buffer(ReprojConstants {
            view_constants: *view_constants,
            prev_world_to_clip: self.prev_world_to_clip,
        }));

        self.prev_world_to_clip = view_constants.view_to_clip * view_constants.world_to_view;
    }
}
