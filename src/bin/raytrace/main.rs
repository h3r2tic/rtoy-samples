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

pub fn load_obj_scene() -> (Vec<Triangle>, AABB) {
    use std::fs::File;
    use std::io::BufReader;

    let file_input =
        BufReader::new(File::open("assets/meshes/teapot.obj").expect("Failed to open .obj file."));
    let obj: Obj<Triangle> = load_obj(file_input).expect("Failed to decode .obj file data.");
    let triangles = obj.vertices;

    let mut bounds = AABB::empty();
    for triangle in &triangles {
        bounds.join_mut(&triangle.aabb());
    }

    (triangles, bounds)
}

#[derive(Clone, Copy)]
#[repr(C)]
struct Constants {
    clip_to_view: Matrix4,
    view_to_world: Matrix4,
}

#[derive(Clone, Copy)]
#[repr(C)]
struct BvhNode {
    box_min: (f32, f32, f32, u32),
    box_max: (f32, f32, f32, u32),
}

impl BvhNode {
    fn set_exit_idx(&mut self, idx: usize) {
        self.box_min.3 = idx as u32;
    }

    fn get_exit_idx(&mut self) -> usize {
        self.box_min.3 as usize
    }

    fn set_is_leaf(&mut self, value: bool) {
        self.box_max.3 = if value { 1 } else { 0 };
    }
}

fn calculate_view_consants(width: u32, height: u32, yaw: f32) -> Constants {
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
        m
    };
    let clip_to_view = view_to_clip.try_inverse().unwrap();

    let distance = 200.0;
    let look_at_height = 35.0;

    //let view_to_world = Matrix4::new_translation(&Vector3::new(0.0, 0.0, -2.0));
    let world_to_view = Isometry3::look_at_rh(
        &Point3::new(
            yaw.cos() * distance,
            look_at_height + distance * 0.2,
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

    let node_res_idx = if node != 0 {
        res.push(BvhNode {
            box_min: (nbox.min.x, nbox.min.y, nbox.min.z, 0),
            box_max: (nbox.max.x, nbox.max.y, nbox.max.z, 0),
        });
        Some(initial_node_count)
    } else {
        None
    };

    let n = &nodes[node];

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
    } else {
        if let Some(node_res_idx) = node_res_idx {
            res[node_res_idx].set_is_leaf(true);
        }
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
    let (mut triangles, _) = load_obj_scene();
    let bvh = BVH::build(&mut triangles);
    bvh.flatten();

    let mut rtoy = Rendertoy::new();

    let tex_key = TextureKey {
        width: 320,
        height: 240,
        format: gl::RGBA16F,
    };

    let viewport_constants = init_named!(
        "ViewportConstants",
        upload_buffer(to_byte_vec(vec![calculate_view_consants(
            tex_key.width,
            tex_key.height,
            0.0
        )]))
    );

    let orderings = (
        |a: &AABB, b: &AABB| a.min.x + a.max.x < b.min.x + b.max.x,
        |a: &AABB, b: &AABB| a.min.x + a.max.x > b.min.x + b.max.x,
        |a: &AABB, b: &AABB| a.min.y + a.max.y < b.min.y + b.max.y,
        |a: &AABB, b: &AABB| a.min.y + a.max.y > b.min.y + b.max.y,
        |a: &AABB, b: &AABB| a.min.z + a.max.z < b.min.z + b.max.z,
        |a: &AABB, b: &AABB| a.min.z + a.max.z > b.min.z + b.max.z,
        /*
        |a: &AABB, b: &AABB| a.min.x < b.min.x,
        |a: &AABB, b: &AABB| a.max.x > b.max.x,
        |a: &AABB, b: &AABB| a.min.y < b.min.y,
        |a: &AABB, b: &AABB| a.max.y > b.max.y,
        |a: &AABB, b: &AABB| a.min.z < b.min.z,
        |a: &AABB, b: &AABB| a.max.z > b.max.z,
        */
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

    let rt_tex = compute_tex(
        tex_key,
        load_cs(asset!("shaders/raytrace.glsl")),
        shader_uniforms!(
            "constants": viewport_constants,
            "bvh_meta": upload_buffer(to_byte_vec(vec![(bvh_nodes.len() / 6) as u32])),
            "bvh": upload_buffer(to_byte_vec(bvh_nodes)),
        ),
    );

    rtoy.forever(|snapshot, frame_state| {
        draw_fullscreen_texture(&*snapshot.get(rt_tex));

        redef_named!(
            viewport_constants,
            upload_buffer(to_byte_vec(vec![calculate_view_consants(
                tex_key.width,
                tex_key.height,
                frame_state.mouse_pos.x.to_radians() * 0.2
            )]))
        );
    });
}
