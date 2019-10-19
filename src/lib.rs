use rendertoy::*;

pub struct TemporalAccumulation {
    pub tex: SnoozyRef<Texture>,
    pub temporal_blend: SnoozyRef<f32>,
}

impl TemporalAccumulation {
    pub fn prepare_frame(&mut self, frame_idx: u32) {
        // Set the new blend factor such that we calculate a uniform average of all the traced frames.
        redef_dynamic!(
            self.temporal_blend,
            const_f32(1.0 / (frame_idx as f32 + 1.0))
        );
    }
}

pub fn accumulate_temporally(tex: SnoozyRef<Texture>, tex_key: TextureKey) -> TemporalAccumulation {
    // We temporally accumulate raytraced images. The blend factor gets re-defined every frame.
    let temporal_blend = init_dynamic!(const_f32(1f32));

    // Need a valid value for the accumulation history. Black will do.
    let accum_tex = init_dynamic!(load_tex(asset!("rendertoy::images/black.png")));

    // Re-define the resource with a cycle upon itself -- every time it gets evaluated,
    // it will use its previous value for "history", and produce a new value.
    redef_dynamic!(
        accum_tex,
        compute_tex(
            tex_key,
            load_cs(asset!("shaders/blend.glsl")),
            shader_uniforms!(
                "inputTex1": accum_tex,
                "inputTex2": tex,
                "blendAmount": temporal_blend,
            )
        )
    );

    TemporalAccumulation {
        tex: accum_tex,
        temporal_blend,
    }
}
