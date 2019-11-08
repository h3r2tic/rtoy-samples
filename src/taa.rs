use rendertoy::*;

fn radical_inverse(mut n: u32, base: u32) -> f32 {
    let mut val = 0.0f32;
    let inv_base = 1.0f32 / base as f32;
    let mut inv_bi = inv_base;

    while n > 0 {
        let d_i = n % base;
        val += d_i as f32 * inv_bi;
        n = (n as f32 * inv_base) as u32;
        inv_bi *= inv_base;
    }

    val
}

pub struct Taa {
    taa_constants: SnoozyRef<Buffer>,
    temporal_accum: crate::TemporalAccumulation,
    reproj_constants: SnoozyRef<Buffer>,
    prev_world_to_clip: Matrix4,
    sub_passes: RenderPassList,
    tex_key: TextureKey,
    samples: Vec<Vector2>,
}

pub struct TaaInput {
    pub gbuffer_tex: SnoozyRef<Texture>,
    pub color_tex: SnoozyRef<Texture>,
}

impl Taa {
    pub fn new(
        tex_key: TextureKey,
        render_fn: impl FnOnce(&mut RenderPassList) -> TaaInput,
    ) -> Self {
        let mut sub_passes = Vec::new();

        let TaaInput {
            gbuffer_tex,
            color_tex,
        } = render_fn(&mut sub_passes);

        let taa_constants = upload_buffer(0u32).into_named();
        let reproj_constants = upload_buffer(0u32).into_named();

        let reprojection_tex = compute_tex(
            tex_key.with_format(gl::RGBA16F),
            load_cs(asset!("shaders/reproject.glsl")),
            shader_uniforms!(
                constants: reproj_constants.clone(),
                inputTex: gbuffer_tex.clone()
            ),
        );

        let temporal_blend = const_f32(1f32).into_named();

        let mut accum_tex = load_tex(asset!("rendertoy::images/black.png")).into_named();
        accum_tex.rebind(compute_tex(
            tex_key.with_format(gl::RGBA16F),
            load_cs(asset!("shaders/taa.glsl")),
            shader_uniforms!(
                inputTex: color_tex,
                historyTex: accum_tex.clone(),
                reprojectionTex: reprojection_tex,
                constants: taa_constants.clone(),
            ),
        ));

        let temporal_accum = crate::TemporalAccumulation {
            tex: accum_tex,
            temporal_blend,
        };

        let samples = (0..16)
            .map(|i| {
                Vector2::new(
                    radical_inverse(i % 16 + 1, 2) - 0.5,
                    radical_inverse(i % 16 + 1, 3) - 0.5,
                )
            })
            .collect();

        Self {
            taa_constants,
            temporal_accum,
            reproj_constants,
            prev_world_to_clip: Matrix4::identity(),
            sub_passes,
            tex_key,
            samples,
        }
    }

    pub fn get_output_tex(&self) -> SnoozyRef<Texture> {
        self.temporal_accum.tex.clone()
    }
}

impl RenderPass for Taa {
    fn prepare_frame(
        &mut self,
        view_constants: &ViewConstants,
        frame_state: &FrameState,
        frame_idx: u32,
    ) {
        // Re-shuffle the jitter sequence if we've just used it up
        if 0 == frame_idx % self.samples.len() as u32 {
            use rand::{prelude::*, seq::SliceRandom};
            let prev_sample = self.samples.last().copied();
            loop {
                // Will most likely shuffle only once. Re-shuffles if the first sample
                // in the new sequence is the same as the last sample in the last.
                self.samples.shuffle(&mut thread_rng());
                if self.samples.first().copied() != prev_sample {
                    break;
                }
            }
        }

        let jitter = self.samples[frame_idx as usize % self.samples.len()];
        //let jitter = Vector2::new(0.5, 0.5);

        let mut view_constants = *view_constants;
        view_constants.set_pixel_offset(jitter, self.tex_key.width, self.tex_key.height);

        for pass in self.sub_passes.iter_mut() {
            pass.prepare_frame(&view_constants, frame_state, frame_idx);
        }

        let jitter = view_constants.sample_offset_pixels;
        self.temporal_accum
            .prepare_frame(&view_constants, frame_state, frame_idx);

        #[derive(Clone, Copy)]
        #[repr(C)]
        struct TaaConstants {
            jitter: (f32, f32),
        }

        self.taa_constants.rebind(upload_buffer(TaaConstants {
            jitter: (jitter.x, jitter.y),
        }));

        #[derive(Clone, Copy)]
        #[repr(C)]
        struct ReprojConstants {
            view_constants: ViewConstants,
            prev_world_to_clip: Matrix4,
        }

        self.reproj_constants.rebind(upload_buffer(ReprojConstants {
            view_constants: view_constants,
            prev_world_to_clip: self.prev_world_to_clip,
        }));

        self.prev_world_to_clip = view_constants.view_to_clip * view_constants.world_to_view;
    }
}
