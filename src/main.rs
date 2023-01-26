/* 
TODOs:
- issue: https://github.com/gfx-rs/naga/issues/1490
- Add spring attenuation
- friction forces
- refactoring
*/

use cgmath::num_traits::pow;
use wgpu_bootstrap::{
    window::Window,
    frame::Frame,
    cgmath::{ self },
    application::Application,
    // texture::create_texture_bind_group,
    context::Context,
    camera::Camera,
    default::{ Vertex, Particle },
    computation::Computation,
    geometry::{ icosphere },
    wgpu,
};

/*
    Constants
*/

// To increase number of instances : increase NUM_INSTANCES_PER_ROW AND increase workgroup size in compute shader.
// Particles per line
const NUM_INSTANCES_PER_ROW: u32 = 31;

// Adjustment of the starting position of the partcules to center them and raise them
const INSTANCE_DISPLACEMENT: cgmath::Vector3<f32> = cgmath::Vector3::new(NUM_INSTANCES_PER_ROW as f32 - 1.0 , -35.0, NUM_INSTANCES_PER_ROW as f32 - 1.0);
const DIST_INTERVAL: f32 = 2.0; // distance between particules

// Sphere radius
const RADIUS: f32 = 25.0; 
const SPHERE_CENTER: cgmath::Vector3<f32> = cgmath::Vector3::new(0.0, 0.0, 0.0);

// Particles mass
const PART_MASS: f32 = 1.0; 

// Length of the springs
const STRUC_REST: f32 = DIST_INTERVAL;
const SHEAR_REST: f32 = DIST_INTERVAL * 1.41421356237;
const BEND_REST: f32 = DIST_INTERVAL * 2.0;

// spring stiffness constant
const STRUC_STIFF: f32 = 300.0;
const SHEAR_STIFF: f32 = 10.0;
const BEND_STIFF: f32 = 10.0;

// TODO
// spring damping constant
// const STRUC_DAMP: f32 = 1.0;
// const SHEAR_DAMP: f32 = 1.0;
// const BEND_DAMP: f32 = 1.0;


/* 
    Structs
*/

#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
struct ComputeData {
    delta_time: f32,        // interval between calculations
    nb_instances: u32,      // num particles
    sphere_center_x: f32,   
    sphere_center_y: f32,   
    sphere_center_z: f32,   
    radius: f32,            
    part_mass: f32,         
    struc_rest: f32,        // length structural springs
    shear_rest: f32,        // length shear springs
    bend_rest: f32,         // length bending springs
    struc_stiff: f32,       // stiffness constant structural springs
    shear_stiff: f32,       // stiffness constant shear springs
    bend_stiff: f32,        // stiffness constant bending springs
    // struc_damp: f32,     // damping constant structural springs
    // shear_damp: f32,     // attenuation constant shear springs
    // bend_damp: f32,      // attenuation constant shear springs
}

struct Net {
    // diffuse_bind_group: wgpu::BindGroup,
    camera_bind_group: wgpu::BindGroup,
    particle_pipeline: wgpu::RenderPipeline,
    sphere_pipeline: wgpu::RenderPipeline,      // line -> sphere
    compute_pipeline: wgpu::ComputePipeline,    // added!
    compute_springs_pipeline: wgpu::ComputePipeline,
    vertex_buffer: wgpu::Buffer,
    index_buffer: wgpu::Buffer,
    sphere_vertex_buffer: wgpu::Buffer,         // sphere
    sphere_index_buffer: wgpu::Buffer,          // sphere
    particles: Vec<Particle>,
    particle_buffer: wgpu::Buffer,
    compute_particles_bind_group: wgpu::BindGroup, // added
    compute_springs_bind_group: wgpu::BindGroup,
    compute_data_buffer: wgpu::Buffer,          // added
    compute_data_bind_group: wgpu::BindGroup,   // added
    indices: Vec<u16>,
    sphere_indices: Vec<u16>,                   // added for sphere
}

impl Net {
    fn new(context: &Context) -> Self {
        /*
            Camera
        */
        let camera = Camera {
            eye: (20.0, 40.0, 100.0).into(),
            target: (0.0, 0.0, 0.0).into(),
            up: cgmath::Vector3::unit_y(),
            aspect: context.get_aspect_ratio(),
            fovy: 45.0,
            znear: 0.1,
            zfar: 1200.0,
        };
        let (_camera_buffer, camera_bind_group) = camera.create_camera_bind_group(context);

        /*
            Particles pipeline (create)
        */

        let particle_pipeline = context.create_render_pipeline(
            "Particle pipeline",
            include_str!("red.wgsl"),
            &[Vertex::desc(), Particle::desc()],
            &[
                &context.camera_bind_group_layout,
            ],
            wgpu::PrimitiveTopology::TriangleList // every three vertices will correspond to one triangle.
        );

        // Generation of the "balls" which represent the particles
        let (vertices, indices) = icosphere(1);
        // Buffers for the balls 
        let vertex_buffer = context.create_buffer(vertices.as_slice(), wgpu::BufferUsages::VERTEX);
        let index_buffer = context.create_buffer(indices.as_slice(), wgpu::BufferUsages::INDEX);

        // Creation of the particles
        let particles = (0..NUM_INSTANCES_PER_ROW*NUM_INSTANCES_PER_ROW).map(|index| {
            let x = index % NUM_INSTANCES_PER_ROW;
            let z = index / NUM_INSTANCES_PER_ROW;
            // note: we multiply by DIST_INTERVAL so that the particles are spaced by the distance specified at the top
            let position = cgmath::Vector3 { x: x as f32*DIST_INTERVAL, y: 0.0, z: z as f32*DIST_INTERVAL } - INSTANCE_DISPLACEMENT;

            Particle {
                position: position.into(), 
                velocity: [0.0, 0.0, 0.0],
            }
        }).collect::<Vec<_>>();
        // buffer for particules
        let particle_buffer = context.create_buffer(particles.as_slice(), wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::STORAGE);
        
        /*
            Sphere pipeline
        */
        
        let sphere_pipeline = context.create_render_pipeline( // définit le pipeline pour le sphere
            "Sphere Pipeline",
            include_str!("blue.wgsl"),
            &[Vertex::desc()],
            &[
                &context.camera_bind_group_layout,
            ],
            wgpu::PrimitiveTopology::LineList,
        );
    
        // Cretion of the sphere
        let (mut sphere_vertices, sphere_indices) = icosphere(4);
        
        // enlarge the sphere
        for vertex in sphere_vertices.iter_mut() {
            let mut posn = cgmath::Vector3::from(vertex.position);
            posn *= RADIUS;
            vertex.position = posn.into()
        }
        
        // Buffers
        let sphere_vertex_buffer = context.create_buffer(&sphere_vertices, wgpu::BufferUsages::VERTEX);
        let sphere_index_buffer = context.create_buffer(&sphere_indices, wgpu::BufferUsages::INDEX);

        /*
            Compute pipeline: calculate displacement of the particles
        */
        
        let compute_pipeline = context.create_compute_pipeline("Compute Pipeline", include_str!("compute.wgsl"));

        // Bind group for particle calculation (uses particle buffer)
        let compute_particles_bind_group = context.create_bind_group(
            "Compute particles bind group", 
            &compute_pipeline.get_bind_group_layout(0),
            &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: particle_buffer.as_entire_binding()
                }
            ]
        );

        // defines compute data (parameters remain fixed)
        let compute_data = ComputeData {
            delta_time: 0.016,
            nb_instances: pow(NUM_INSTANCES_PER_ROW,2),
            sphere_center_x: SPHERE_CENTER.x,
            sphere_center_y: SPHERE_CENTER.y,
            sphere_center_z: SPHERE_CENTER.z,
            radius: RADIUS,
            part_mass: PART_MASS,
            struc_rest: STRUC_REST,
            shear_rest: SHEAR_REST,
            bend_rest: BEND_REST,
            struc_stiff: STRUC_STIFF,
            shear_stiff: SHEAR_STIFF,
            bend_stiff: BEND_STIFF,
            // struc_damp: STRUC_DAMP,
            // shear_damp: f32,
            // bend_damp: f32,
        };

        // buffer compute data
        let compute_data_buffer = context.create_buffer(&[compute_data], wgpu::BufferUsages::UNIFORM);

        // Bind group compute data
        let compute_data_bind_group = context.create_bind_group(
            "Compute data bind group", 
            &compute_pipeline.get_bind_group_layout(1), 
            &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: compute_data_buffer.as_entire_binding(),
                }
            ]
        );


        /*
            Springs Pipeline
        */
        let compute_springs_pipeline = context.create_compute_pipeline(
            "spring compute pipeline", 
            include_str!("springs.wgsl"));

        // spring lists
        let mut structural = Vec::new();
        let mut shear = Vec::new();
        let mut bend = Vec::new();

        for index in 0..particles.len() as i32 {
            // structural springs
            let row = index as u32 / NUM_INSTANCES_PER_ROW;
            let col = index as u32 % NUM_INSTANCES_PER_ROW;
            for offset in [-1,1] {
                // col -1 & +1
                if col as i32 + offset >= 0 && col as i32 + offset < NUM_INSTANCES_PER_ROW as i32 {
                    structural.push([index, index + offset]);
                } else {
                    structural.push([index, pow(NUM_INSTANCES_PER_ROW, 2) as i32 + 1]);
                }
                // row -1 & +1
                if row as i32 + offset >= 0 && row as i32 + offset < NUM_INSTANCES_PER_ROW as i32 {
                    structural.push([index, index + (offset * NUM_INSTANCES_PER_ROW as i32)]);
                } else {
                    structural.push([index, pow(NUM_INSTANCES_PER_ROW, 2) as i32 + 1]);
                }
            }
            // shear springs
            for offset1 in [-1,1] {
                for offset2 in [-1,1] {
                    if col as i32 + offset1 >= 0 && col as i32 + offset1 < NUM_INSTANCES_PER_ROW as i32 && row as i32 + offset2 >= 0 && row as i32 + offset2 < NUM_INSTANCES_PER_ROW as i32 {
                        shear.push([index, index + (offset2 * NUM_INSTANCES_PER_ROW as i32) + offset1]); 
                    } else {
                        shear.push([index, pow(NUM_INSTANCES_PER_ROW, 2) as i32 + 1]);
                    }
                }
            }
            // bend springs
            for offset in [-2,2] {
                // col -2 & +2
                if col as i32 + offset >= 0 && col as i32 + offset < NUM_INSTANCES_PER_ROW as i32 {
                    bend.push([index, index + offset]);
                } else {
                    bend.push([index, pow(NUM_INSTANCES_PER_ROW, 2) as i32 + 1]);
                }
                // row -2 & +2
                if row as i32 + offset >= 0 && row as i32 + offset < NUM_INSTANCES_PER_ROW as i32 {
                    bend.push([index, index + (offset * NUM_INSTANCES_PER_ROW as i32)]);
                } else {
                    bend.push([index, pow(NUM_INSTANCES_PER_ROW, 2) as i32 + 1]);
                }
            }
        }

        // buffer for structural springs
        let structural_index_buffer = context.create_buffer(structural.as_slice(), wgpu::BufferUsages::STORAGE);
        let shear_index_buffer = context.create_buffer(shear.as_slice(), wgpu::BufferUsages::STORAGE);
        let bend_index_buffer = context.create_buffer(bend.as_slice(), wgpu::BufferUsages::STORAGE);

        // Bind group springs
        let compute_springs_bind_group = context.create_bind_group(
            "Compute Springs Bind Group!", 
            &compute_pipeline.get_bind_group_layout(2),
            &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: structural_index_buffer.as_entire_binding()
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: shear_index_buffer.as_entire_binding()
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: bend_index_buffer.as_entire_binding()
                },
            ]
        );

        Self {
            // diffuse_bind_group,
            camera_bind_group,
            particle_pipeline,
            sphere_pipeline,
            compute_pipeline,
            compute_springs_pipeline,
            vertex_buffer,
            index_buffer,
            sphere_vertex_buffer,
            sphere_index_buffer,
            particles,
            particle_buffer,
            compute_particles_bind_group,
            compute_springs_bind_group,
            compute_data_buffer,
            compute_data_bind_group,
            indices, 
            sphere_indices,
        }
    }
}

// impl .. for syntax:
// adds previously defined methods (from the trait) to the type
// implements the trait Application for the struct Net
impl Application for Net {
    // inside render you USE the pipeline
    fn render(&self, context: &Context) -> Result<(), wgpu::SurfaceError> {
        let mut frame = Frame::new(context)?;

        {
            let mut render_pass = frame.begin_render_pass(wgpu::Color {r: 0.85, g: 0.85, b: 0.85, a: 1.0});
            
            // show particles
            render_pass.set_pipeline(&self.particle_pipeline); // pipeline (1)
            render_pass.set_bind_group(0, &self.camera_bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.vertex_buffer.slice(..)); // vertex buffer (icospheres)
            render_pass.set_vertex_buffer(1, self.particle_buffer.slice(..)); // vertex buffer (particules)
            render_pass.set_index_buffer(self.index_buffer.slice(..), wgpu::IndexFormat::Uint16);
            render_pass.draw_indexed(0..(self.indices.len() as u32), 0, 0..self.particles.len() as _);
            
            // show sphere
            render_pass.set_pipeline(&self.sphere_pipeline); // pipeline (2)
            render_pass.set_bind_group(0, &self.camera_bind_group, &[]);
            render_pass.set_vertex_buffer(0, self.sphere_vertex_buffer.slice(..));
            render_pass.set_index_buffer(self.sphere_index_buffer.slice(..), wgpu::IndexFormat::Uint16);
            render_pass.draw_indexed(0..self.sphere_indices.len() as u32, 0, 0..1);
        }

        frame.present();

        Ok(())
    }
    
    fn update(&mut self, context: &Context, _delta_time: f32) {
        let compute_data = ComputeData {
            delta_time: 0.016,
            nb_instances: pow(NUM_INSTANCES_PER_ROW,2),
            sphere_center_x: SPHERE_CENTER.x,
            sphere_center_y: SPHERE_CENTER.y,
            sphere_center_z: SPHERE_CENTER.z,
            radius: RADIUS,
            part_mass: PART_MASS,
            struc_rest: STRUC_REST,
            shear_rest: SHEAR_REST,
            bend_rest: BEND_REST,
            struc_stiff: STRUC_STIFF,
            shear_stiff: SHEAR_STIFF,
            bend_stiff: BEND_STIFF,
            // struc_damp: STRUC_DAMP,
            // shear_damp: f32,
            // bend_damp: f32,
        };
        context.update_buffer(&self.compute_data_buffer, &[compute_data]);

        // Update via the compute shader
        let mut computation = Computation::new(context);

        {
            let mut compute_pass = computation.begin_compute_pass();

            // Calculation of spring forces
            compute_pass.set_pipeline(&self.compute_springs_pipeline); // pipeline (3)
            compute_pass.set_bind_group(0, &self.compute_particles_bind_group, &[]);
            compute_pass.set_bind_group(1, &self.compute_data_bind_group, &[]);
            compute_pass.set_bind_group(2, &self.compute_springs_bind_group, &[]);
            compute_pass.dispatch_workgroups((pow(NUM_INSTANCES_PER_ROW,2) as f64/64.0).ceil() as u32, 1, 1);
            
            // Calculation of new positions
            compute_pass.set_pipeline(&self.compute_pipeline); // pipeline (4)
            compute_pass.set_bind_group(0, &self.compute_particles_bind_group, &[]);
            compute_pass.set_bind_group(1, &self.compute_data_bind_group, &[]);
            compute_pass.set_bind_group(2, &self.compute_springs_bind_group, &[]);
            compute_pass.dispatch_workgroups((pow(NUM_INSTANCES_PER_ROW,2) as f64/64.0).ceil() as u32, 1, 1);
        }

        computation.submit();

    }
}

fn main() {
    let window = Window::new();
    let context = window.get_context();
    let my_app = Net::new(context);
    window.run(my_app);
}
