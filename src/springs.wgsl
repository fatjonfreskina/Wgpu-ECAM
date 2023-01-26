// This shader calculates all the forces of the springs and applies them to the particles

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
    var sum_of_forces = vec3<f32>(0.0, 0.0, 0.0);
    
    /* 
        Structural Springs
    */
    for (var i = 0u; i < 4u; i += 1u) {
        // We know that each particle has four structural links (some of which are invalid; see below)    for (var i = 0u; i < 4u; i += 1u) {
        // Get the index
        var index1 = structural[param.x * 4u + i][0]; // param.x*4 allows not to iterate through the whole list
        var index2 = structural[param.x * 4u + i][1];
        // if the 2nd index is greater than the number of particles, the pair of points is not taken into account (we are outside the net)
        if (u32(index2) <= data.nb_instances) {
            var part1 = particlesData[index1];
            var part2 = particlesData[index2];
            // Find pos of particles
            var posn1 = vec3<f32>(part1.pos_x, part1.pos_y, part1.pos_z);
            var posn2 = vec3<f32>(part2.pos_x, part2.pos_y, part2.pos_z);
            // Distance between particles
            var part_dist = length(posn1 - posn2);
            // directions of the force (from one to the other, the calculation in the other direction will be done when we treat the other particle)
            var dir = normalize(posn1 - posn2);
            // spring force (deltadistance*k*direction)
            var struc_force = -dir * (part_dist - data.struc_rest) * data.struc_stiff;
            sum_of_forces += struc_force;
        }
    }
    /*
        Shear springs
    */
    for (var i = 0u; i < 4u; i += 1u) {
        var index1 = shear[param.x * 4u + i][0];
        var index2 = shear[param.x * 4u + i][1];
        if (u32(index2) <= data.nb_instances) {
            var part1 = particlesData[index1];
            var part2 = particlesData[index2];
            var posn1 = vec3<f32>(part1.pos_x, part1.pos_y, part1.pos_z);
            var posn2 = vec3<f32>(part2.pos_x, part2.pos_y, part2.pos_z);
            var part_dist = length(posn1 - posn2);
            var dir = normalize(posn1 - posn2);
            var shear_force = -dir * (part_dist - data.shear_rest) * data.shear_stiff;
            sum_of_forces += shear_force;
        }
    }
    /* 
        Bend springs
    */
    for (var i = 0u; i < 4u; i += 1u) {
        var index1 = bend[param.x * 4u + i][0];
        var index2 = bend[param.x * 4u + i][1];
        if (u32(index2) <= data.nb_instances) {
            var part1 = particlesData[index1];
            var part2 = particlesData[index2];
            var posn1 = vec3<f32>(part1.pos_x, part1.pos_y, part1.pos_z);
            var posn2 = vec3<f32>(part2.pos_x, part2.pos_y, part2.pos_z);
            var part_dist = length(posn1 - posn2);
            var dir = normalize(posn1 - posn2);
            var bend_force = -dir * (part_dist - data.bend_rest) * data.bend_stiff;
            sum_of_forces += bend_force;
        }
    }
    /*
        Gravity
    */
    var gravity = vec3<f32>(0.0, -9.81*data.part_mass, 0.0);
    sum_of_forces += gravity;

    // Update position particles
    // v = (F*deltatime)/m
    particlesData[param.x].velocity_x += ((sum_of_forces.x * data.delta_time) / data.part_mass);
    particlesData[param.x].velocity_y += ((sum_of_forces.y * data.delta_time) / data.part_mass);
    particlesData[param.x].velocity_z += ((sum_of_forces.z * data.delta_time) / data.part_mass);
}