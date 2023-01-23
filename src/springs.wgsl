// Ce shader calcule toutes les forces des ressorts et les applique aux particules

struct Particle { // Attributs sont donnés individuellement à cause d'un problème d'alignement de mémoire (mais on peut les recomposer plus loin)
    pos_x: f32,
    pos_y: f32,
    pos_z: f32,
    velocity_x: f32,
    velocity_y: f32,
    velocity_z: f32,
}

struct ComputationData { // idem que dans le code rust
    // ajouter workgroup size ici dedans ?
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
// Idem pour workgroup
// Increase size of workgroup to have more particles
@compute @workgroup_size(64, 1, 1) 
fn main(@builtin(global_invocation_id) param: vec3<u32>) {
    if (param.x >= data.nb_instances) {
          return;
    }
    var sum_of_forces = vec3<f32>(0.0, 0.0, 0.0);
    // RESSORTS STRUCTURAUX ------------------------------------------------------------------------------------------------------------------
    // On sait que chaque particule a quatre liens structuraux (dont certains ne sont pas valides; voir plus bas)
    for (var i = 0u; i < 4u; i += 1u) {
        // récupérer les index
        var index1 = structural[param.x * 4u + i][0]; // param.x*4 permet de ne pas devoir itérer dans toute la liste
        var index2 = structural[param.x * 4u + i][1];
        // si le 2e index est plus grand que le nombre de particules, on ne tient pas compte du couple de points (on est en dehors du filet)
        if (u32(index2) <= data.nb_instances) {
            var part1 = particlesData[index1];
            var part2 = particlesData[index2];
            // trouver la position de ces particules
            var posn1 = vec3<f32>(part1.pos_x, part1.pos_y, part1.pos_z);
            var posn2 = vec3<f32>(part2.pos_x, part2.pos_y, part2.pos_z);
            // distance entre les deux particules
            var part_dist = length(posn1 - posn2);
            // directions de la force ( de l'une vers l'autre, le calcul dans l'autre sens se fera quand on traitera l'autre particule)
            var dir = normalize(posn1 - posn2);
            // force du ressort (deltadistance*k*direction)
            var struc_force = -dir * (part_dist - data.struc_rest) * data.struc_stiff;
            sum_of_forces += struc_force;
        }
    }
    // RESSORTS DE CISAILLEMENT --------------------------------------------------------------------------------------------------------------
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
    // RESSORTS DE FLEXION -------------------------------------------------------------------------------------------------------------------
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
    // GRAVITÉ --------------------------------------------------------------------------------------------------------------------------------
    var gravity = vec3<f32>(0.0, -9.81*data.part_mass, 0.0);
    sum_of_forces += gravity;

    // MISE À JOUR DE LA POSITION DE LA PARTICULE ----------------------------------------------------------------------------------------------
    // v = (F*deltatime)/m
    particlesData[param.x].velocity_x += ((sum_of_forces.x * data.delta_time) / data.part_mass);
    particlesData[param.x].velocity_y += ((sum_of_forces.y * data.delta_time) / data.part_mass);
    particlesData[param.x].velocity_z += ((sum_of_forces.z * data.delta_time) / data.part_mass);
}