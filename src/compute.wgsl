// This shader calculates the position and velocity of each particle according 
// to the gravity and the collision with the sphere
struct Particle {
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    velocity_x: f32,
    velocity_y: f32,
    velocity_z: f32,
}

struct ComputationData {
    delta_time: f32,
    nb_instances: u32,
    sphere_center_x: f32,
    sphere_center_y: f32,
    sphere_center_z: f32,
    radius: f32,
    part_mass: f32,
    struc_rest: f32,
    shear_rest: f32,
    bend_rest: f32,
    struc_stiff: f32,
    shear_stiff: f32,
    bend_stiff: f32,
    // struc_damp: f32,
    // shear_damp: f32,
    // bend_damp: f32,
}

// group(0) corresponds to the 1st parameter in set_bind_group()
// binding(n) relates to the binding specified when we created the BindGroupLayout and BindGroup
@group(0) @binding(0) var<storage, read_write> particlesData: array<Particle>;
@group(1) @binding(0) var<uniform> data: ComputationData;
@group(2) @binding(0) var<storage> structural: array<vec2<i32>>;
@group(2) @binding(1) var<storage> shear: array<vec2<i32>>;
@group(2) @binding(2) var<storage> bend: array<vec2<i32>>;
// Increase size of workgroup to have more particles
@compute @workgroup_size(64, 1, 1) 
fn main(@builtin(global_invocation_id) param: vec3<u32>) {
    if (param.x >= data.nb_instances) {
          return;
    }
    
    /* 
        Update pos and vel of each particle
    */

    var struc_spring = structural[param.x];
    var shear_spring = shear[param.x];
    var bend_spring = bend[param.x];
    
    // "particle" is a reference to the particle being processed, particlesData[param.x] is the particle itself   
    var particle = particlesData[param.x];

    // We add the velocity to the position to move the particle
    particlesData[param.x].pos_x += particle.velocity_x * data.delta_time;
    particlesData[param.x].pos_y += particle.velocity_y * data.delta_time;
    particlesData[param.x].pos_z += particle.velocity_z * data.delta_time;
    
    /*
        Collision with sphere
    */ 

    // We recompose the center, position and velocity in vectors for more ease
    var center = vec3<f32>(data.sphere_center_x, data.sphere_center_y, data.sphere_center_z);
    var posn = vec3<f32>(particle.pos_x, particle.pos_y, particle.pos_z);
    var velocity = vec3<f32>(particle.velocity_x, particle.velocity_y, particle.velocity_z);

    // to know if the particle is in the sphere, we compare the distance of this particle to the center with the radius
    var distance_to_origin = posn - center;
    // if this distance is smaller than the radius, it is inside and must be bounced
    if length(distance_to_origin) < data.radius {
        var direction = normalize(distance_to_origin); 
        // the normal is calculated to determine in which direction 
        // which direction to send the particle
        // to avoid that the particle enters the sphere (while the calculation is being done), we send it back directly to its 
        // bounce by putting it at 101% of the radius from the center (a bit outside, roughly speaking)
        posn = center + direction * (data.radius * 1.01);
        
        // Apply new pos
        particlesData[param.x].pos_x = posn.x;
        particlesData[param.x].pos_y = posn.y;
        particlesData[param.x].pos_z = posn.z;

        // Apply new speed
        particlesData[param.x].velocity_x = 0.0; // velocity.x;
        particlesData[param.x].velocity_y = 0.0; // velocity.y;
        particlesData[param.x].velocity_z = 0.0; // velocity.z;
    }
}
