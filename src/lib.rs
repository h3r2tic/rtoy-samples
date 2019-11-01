use rendertoy::*;
pub mod rt_shadows;
pub mod ssao;
pub struct TemporalAccumulation {
    pub tex: SnoozyRef<Texture>,
    pub temporal_blend: SnoozyRef<f32>,
}

impl TemporalAccumulation {
    pub fn prepare_frame(&mut self, frame_idx: u32) {
        // Set the new blend factor such that we calculate a uniform average of all the traced frames.
        self.temporal_blend
            .rebind(const_f32(1.0 / (frame_idx as f32 + 1.0)));
    }
}

pub fn accumulate_temporally(tex: SnoozyRef<Texture>, tex_key: TextureKey) -> TemporalAccumulation {
    // We temporally accumulate raytraced images. The blend factor gets re-defined every frame.
    let temporal_blend = const_f32(1f32).into_dynamic();

    // Need a valid value for the accumulation history. Black will do.
    let mut accum_tex = load_tex(asset!("rendertoy::images/black.png")).into_dynamic();

    // Re-define the resource with a cycle upon itself -- every time it gets evaluated,
    // it will use its previous value for "history", and produce a new value.
    accum_tex.rebind(compute_tex(
        tex_key,
        load_cs(asset!("shaders/blend.glsl")),
        shader_uniforms!(
            inputTex1: accum_tex.clone(),
            inputTex2: tex,
            blendAmount: temporal_blend.clone(),
        ),
    ));

    TemporalAccumulation {
        tex: accum_tex,
        temporal_blend,
    }
}

pub fn accumulate_reproject_temporally(
    input: SnoozyRef<Texture>,
    reprojection_tex: SnoozyRef<Texture>,
    tex_key: TextureKey,
) -> TemporalAccumulation {
    let temporal_blend = const_f32(1f32).into_dynamic();
    let mut accum_tex = load_tex(asset!("rendertoy::images/black.png")).into_dynamic();
    accum_tex.rebind(compute_tex(
        tex_key,
        load_cs(asset!("shaders/taa.glsl")),
        shader_uniforms!(
            inputTex: input,
            historyTex: accum_tex.clone(),
            reprojectionTex: reprojection_tex,
        ),
    ));

    TemporalAccumulation {
        tex: accum_tex,
        temporal_blend,
    }
}
