mod rgb9e5;

#[macro_use]
extern crate static_assertions;

use bvh::{
    aabb::{Bounded, AABB},
    bounding_hierarchy::BHShape,
    bvh::{BVHNode, BVH},
};
use nalgebra as na;
use obj::raw::object::Polygon;
use obj::*;
use rendertoy::*;

type Point3 = na::Point3<f32>;
type Vector3 = na::Vector3<f32>;
type Matrix4 = na::Matrix4<f32>;
type Isometry3 = na::Isometry3<f32>;

pub struct Triangle {
    pub a: Point3,
    pub b: Point3,
    pub c: Point3,
    node_index: usize,
}

impl Triangle {
    pub fn new(a: Point3, b: Point3, c: Point3) -> Triangle {
        Triangle {
            a: a,
            b: b,
            c: c,
            node_index: 0,
        }
    }
}

impl Bounded for Triangle {
    fn aabb(&self) -> AABB {
        AABB::empty().grow(&self.a).grow(&self.b).grow(&self.c)
    }
}

impl BHShape for Triangle {
    fn set_bh_node_index(&mut self, index: usize) {
        self.node_index = index;
    }

    fn bh_node_index(&self) -> usize {
        self.node_index
    }
}

impl FromRawVertex for Triangle {
    fn process(
        vertices: Vec<(f32, f32, f32, f32)>,
        _: Vec<(f32, f32, f32)>,
        polygons: Vec<Polygon>,
    ) -> ObjResult<(Vec<Self>, Vec<u16>)> {
        // Convert the vertices to `Point3`s.
        let points = vertices
            .into_iter()
            .map(|v| Point3::new(v.0, v.1, v.2))
            .collect::<Vec<_>>();

        // Estimate for the number of triangles, assuming that each polygon is a triangle.
        let mut triangles = Vec::with_capacity(polygons.len());
        {
            let mut push_triangle = |indices: &Vec<usize>| {
                let mut indices_iter = indices.iter();
                let anchor = points[*indices_iter.next().unwrap()];
                let mut second = points[*indices_iter.next().unwrap()];
                for third_index in indices_iter {
                    let third = points[*third_index];
                    triangles.push(Triangle::new(anchor, second, third));
                    second = third;
                }
            };

            // Iterate over the polygons and populate the `Triangle`s vector.
            for polygon in polygons.into_iter() {
                match polygon {
                    Polygon::P(ref vec) => push_triangle(vec),
                    Polygon::PT(ref vec) | Polygon::PN(ref vec) => {
                        push_triangle(&vec.iter().map(|vertex| vertex.0).collect())
                    }
                    Polygon::PTN(ref vec) => {
                        push_triangle(&vec.iter().map(|vertex| vertex.0).collect())
                    }
                }
            }
        }
        Ok((triangles, Vec::new()))
    }
}

pub fn load_obj_scene(path: &str) -> Vec<Triangle> {
    use libflate::gzip::Decoder;
    use std::fs::File;
    use std::io::{BufRead, BufReader};
    use std::path::Path;

    let f = BufReader::new(File::open(path).expect("Failed to open scene file."));

    let f: Box<dyn BufRead> = if Path::new(path).extension().unwrap() == "gz" {
        let f = Decoder::new(f).unwrap();
        Box::new(std::io::BufReader::new(f))
    } else {
        Box::new(f)
    };

    let obj: Obj<Triangle> = load_obj(f).expect("Failed to decode .obj file data.");

    obj.vertices
}

#[derive(Clone, Copy)]
#[repr(C)]
struct Constants {
    clip_to_view: Matrix4,
    view_to_world: Matrix4,
    frame_idx: u32,
}

#[derive(Clone, Copy)]
#[repr(C)]
struct GpuBvhNode {
    packed: [u32; 4],
}

fn pack_gpu_bvh_node(node: BvhNode) -> GpuBvhNode {
    let bmin = (
        half::f16::from_f32(node.bbox_min.x),
        half::f16::from_f32(node.bbox_min.y),
        half::f16::from_f32(node.bbox_min.z),
    );

    let box_extent_packed = {
        // The fp16 was rounded-down, so extent will be larger than for fp32
        let extent =
            node.bbox_max - Vector3::new(bmin.0.to_f32(), bmin.1.to_f32(), bmin.2.to_f32());

        rgb9e5::pack_rgb9e5(extent.x, extent.y, extent.z)
    };

    assert!(node.exit_idx < (1u32 << 24));
    assert!(node.prim_idx == std::u32::MAX || node.prim_idx < (1u32 << 24));

    GpuBvhNode {
        packed: [
            box_extent_packed,
            ((bmin.0.to_bits() as u32) << 16) | (bmin.1.to_bits() as u32),
            ((bmin.2.to_bits() as u32) << 16) | ((node.prim_idx >> 8) & 0xffff),
            ((node.prim_idx & 0xff) << 24) | node.exit_idx,
        ],
    }
}

struct BvhNode {
    bbox_min: Point3,
    exit_idx: u32,
    bbox_max: Point3,
    prim_idx: u32,
}

impl BvhNode {
    fn new_leaf(bbox_min: Point3, bbox_max: Point3, prim_idx: usize) -> Self {
        Self {
            bbox_min,
            exit_idx: 0,
            bbox_max,
            prim_idx: prim_idx as u32,
        }
    }

    fn new_interior(bbox_min: Point3, bbox_max: Point3) -> Self {
        Self {
            bbox_min,
            exit_idx: 0,
            bbox_max,
            prim_idx: std::u32::MAX,
        }
    }

    fn set_exit_idx(&mut self, idx: usize) {
        self.exit_idx = idx as u32;
    }

    fn get_exit_idx(&mut self) -> usize {
        self.exit_idx as usize
    }
}

#[derive(Clone, Copy)]
#[repr(C)]
struct GpuTriangle {
    v: Point3,
    e0: Vector3,
    e1: Vector3,
}

assert_eq_size!(triangle_size_check; GpuTriangle, [u8; 9 * 4]);

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

    let distance = 180.0 * 5.0;
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

fn convert_bvh<BoxOrderFn>(
    node: usize,
    nbox: &AABB,
    nodes: &[BVHNode],
    are_boxes_correctly_ordered: &BoxOrderFn,
    res: &mut Vec<BvhNode>,
) where
    BoxOrderFn: Fn(&AABB, &AABB) -> bool,
{
    let initial_node_count = res.len();
    let n = &nodes[node];

    let node_res_idx = if node != 0 {
        res.push(if let BVHNode::Node { .. } = n {
            BvhNode::new_interior(nbox.min, nbox.max)
        } else {
            BvhNode::new_leaf(
                nbox.min,
                nbox.max,
                n.shape_index().expect("bvh leaf shape index"),
            )
        });
        Some(initial_node_count)
    } else {
        None
    };

    if let BVHNode::Node { .. } = n {
        let boxes = [&n.child_l_aabb(), &n.child_r_aabb()];
        let indices = [n.child_l(), n.child_r()];

        let (first, second) = if are_boxes_correctly_ordered(boxes[0], boxes[1]) {
            (0, 1)
        } else {
            (1, 0)
        };

        convert_bvh(
            indices[first],
            &boxes[first],
            nodes,
            are_boxes_correctly_ordered,
            res,
        );
        convert_bvh(
            indices[second],
            &boxes[second],
            nodes,
            are_boxes_correctly_ordered,
            res,
        );
    }

    if let Some(node_res_idx) = node_res_idx {
        let index_after_subtree = res.len();
        res[node_res_idx].set_exit_idx(index_after_subtree);
    } else {
        // We are back at the root node. Go and change exit pointers to be relative,
        for (i, node) in res.iter_mut().enumerate().skip(initial_node_count) {
            let idx = node.get_exit_idx();
            node.set_exit_idx(idx - i);
        }
    }
}

fn main() {
    let mut triangles = load_obj_scene("assets/meshes/flying_trabant.obj.gz");
    //let mut triangles = load_obj_scene("assets/meshes/lighthouse.obj.gz");
    let bvh = BVH::build(&mut triangles);
    bvh.flatten();

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

    let orderings = (
        |a: &AABB, b: &AABB| a.min.x + a.max.x < b.min.x + b.max.x,
        |a: &AABB, b: &AABB| a.min.x + a.max.x > b.min.x + b.max.x,
        |a: &AABB, b: &AABB| a.min.y + a.max.y < b.min.y + b.max.y,
        |a: &AABB, b: &AABB| a.min.y + a.max.y > b.min.y + b.max.y,
        |a: &AABB, b: &AABB| a.min.z + a.max.z < b.min.z + b.max.z,
        |a: &AABB, b: &AABB| a.min.z + a.max.z > b.min.z + b.max.z,
    );

    let mut bvh_nodes: Vec<BvhNode> = Vec::with_capacity(bvh.nodes.len() * 6);

    macro_rules! ordered_flatten_bvh {
        ($order: expr) => {{
            convert_bvh(
                0,
                &AABB::default(),
                bvh.nodes.as_slice(),
                &$order,
                &mut bvh_nodes,
            );
        }};
    }

    ordered_flatten_bvh!(orderings.0);
    ordered_flatten_bvh!(orderings.1);
    ordered_flatten_bvh!(orderings.2);
    ordered_flatten_bvh!(orderings.3);
    ordered_flatten_bvh!(orderings.4);
    ordered_flatten_bvh!(orderings.5);

    let gpu_bvh_nodes: Vec<_> = bvh_nodes.into_iter().map(pack_gpu_bvh_node).collect();

    let bvh_triangles = triangles
        .iter()
        .map(|t| GpuTriangle {
            v: t.a,
            e0: t.b - t.a,
            e1: t.c - t.a,
        })
        .collect::<Vec<_>>();

    let rt_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/raytrace.glsl")),
        shader_uniforms!(
            "constants": viewport_constants,
            "bvh_meta_buf": upload_buffer(to_byte_vec(vec![(gpu_bvh_nodes.len() / 6) as u32])),
            "bvh_nodes_buf": upload_buffer(to_byte_vec(gpu_bvh_nodes)),
            "bvh_triangles_buf": upload_buffer(to_byte_vec(bvh_triangles)),
        ),
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

    let mut gpu_time_ms = 0.0f64;
    let mut frame_idx = 0;
    let mut prev_mouse_pos_x = 0.0;

    const MAX_ACCUMULATED_FRAMES: u32 = 1024;

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

        draw_fullscreen_texture(&*snapshot.get(accum_rt_tex));

        let cur = frame_state.gpu_time_ms;
        let prev = gpu_time_ms.max(cur * 0.85).min(cur / 0.85);
        gpu_time_ms = prev * 0.95 + cur * 0.05;
        print!("Frame time: {:.2} ms           \r", gpu_time_ms);

        use std::io::Write;
        let _ = std::io::stdout().flush();

        frame_idx = (frame_idx + 1).min(MAX_ACCUMULATED_FRAMES);
    });
}
