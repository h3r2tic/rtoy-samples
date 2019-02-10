//const RGB9E5_EXPONENT_BITS: u32 = 5;
const RGB9E5_MANTISSA_BITS: u32 = 9;
const RGB9E5_EXP_BIAS: i32 = 15;
const RGB9E5_MAX_VALID_BIASED_EXP: i32 = 31;

const MAX_RGB9E5_EXP: i32 = RGB9E5_MAX_VALID_BIASED_EXP - RGB9E5_EXP_BIAS;
const RGB9E5_MANTISSA_VALUES: i32 = (1 << RGB9E5_MANTISSA_BITS);
const MAX_RGB9E5_MANTISSA: i32 = (RGB9E5_MANTISSA_VALUES - 1);
const MAX_RGB9E5: f32 =
    ((MAX_RGB9E5_MANTISSA as f32) / RGB9E5_MANTISSA_VALUES as f32 * (1 << MAX_RGB9E5_EXP) as f32);
//const EPSILON_RGB9E5: f32 = ((1.0 / RGB9E5_MANTISSA_VALUES as f32) / (1 << RGB9E5_EXP_BIAS) as f32);

fn clamp_range_for_rgb9e5(x: f32) -> f32 {
    if x > 0.0 {
        if x >= MAX_RGB9E5 {
            MAX_RGB9E5
        } else {
            x
        }
    } else {
        /* NaN gets here too since comparisons with NaN always fail! */
        return 0.0;
    }
}

// https://www.khronos.org/registry/OpenGL/extensions/EXT/EXT_texture_shared_exponent.txt
fn floor_log2(x: f32) -> i32 {
    let f: u32 = unsafe { std::mem::transmute(x) };
    let biasedexponent = (f & 0x7F800000u32) >> 23;
    biasedexponent as i32 - 127
}

// https://www.khronos.org/registry/OpenGL/extensions/EXT/EXT_texture_shared_exponent.txt
pub fn pack_rgb9e5(r: f32, g: f32, b: f32) -> u32 {
    let rc = clamp_range_for_rgb9e5(r);
    let gc = clamp_range_for_rgb9e5(g);
    let bc = clamp_range_for_rgb9e5(b);

    let maxrgb = rc.max(gc).max(bc);
    let mut exp_shared = (-RGB9E5_EXP_BIAS - 1).max(floor_log2(maxrgb)) + 1 + RGB9E5_EXP_BIAS;
    assert!(exp_shared <= RGB9E5_MAX_VALID_BIASED_EXP);
    assert!(exp_shared >= 0);

    // This pow function could be replaced by a table.
    let mut denom = 2.0f64.powi(exp_shared - RGB9E5_EXP_BIAS - RGB9E5_MANTISSA_BITS as i32);

    let maxm = (maxrgb as f64 / denom + 0.5).floor() as i32;
    if maxm == MAX_RGB9E5_MANTISSA + 1 {
        denom *= 2.0;
        exp_shared += 1;
        assert!(exp_shared <= RGB9E5_MAX_VALID_BIASED_EXP);
    } else {
        assert!(maxm <= MAX_RGB9E5_MANTISSA);
    }

    let rm = (rc as f64 / denom + 0.5).floor() as i32;
    let gm = (gc as f64 / denom + 0.5).floor() as i32;
    let bm = (bc as f64 / denom + 0.5).floor() as i32;

    assert!(rm <= MAX_RGB9E5_MANTISSA);
    assert!(gm <= MAX_RGB9E5_MANTISSA);
    assert!(bm <= MAX_RGB9E5_MANTISSA);
    assert!(rm >= 0);
    assert!(gm >= 0);
    assert!(bm >= 0);

    ((rm as u32) << (32 - 9))
        | ((gm as u32) << (32 - 9 * 2))
        | ((bm as u32) << (32 - 9 * 3))
        | (exp_shared as u32)
}
