// Ce shader calcule la position et la vélocité de chaque particule en fonction de la gravité et de la collision avec la sphère

struct Particle {
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

// Demander (ou trouver) une explication du concept de groupe (WGPU?)
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
    //  MISE A JOUR DE LA POSITION ET DE LA VÉLOCITÉ DE CHAQUE PARTICULE ---------------------------------------------------------------

    // Déclaration inutile mais nécessaire pour que structural soit utilisé; sans ça, le shader ne compile pas
    var struc_spring = structural[param.x];
    var shear_spring = shear[param.x];
    var bend_spring = bend[param.x];
    
    // "particle" est une référence vers la particule en cours de traitement, particlesData[param.x] est la particule elle-même, 
    var particle = particlesData[param.x];

    // On ajoute la vélocité à la position pour déplacer la particule
    particlesData[param.x].pos_x += particle.velocity_x * data.delta_time;
    particlesData[param.x].pos_y += particle.velocity_y * data.delta_time;
    particlesData[param.x].pos_z += particle.velocity_z * data.delta_time;
    
    // COLLISION AVEC LA SPHERE --------------------------------------------------------------------------------------------------------

    // On recompose les centre, position et velocité en vecteurs pour plus de facilité
    var center = vec3<f32>(data.sphere_center_x, data.sphere_center_y, data.sphere_center_z);
    var posn = vec3<f32>(particle.pos_x, particle.pos_y, particle.pos_z);
    var velocity = vec3<f32>(particle.velocity_x, particle.velocity_y, particle.velocity_z);

    // pour savoir si la particule est dans la sphere, on compare la distance de cette particule au centre avec le rayon
    var distance_to_origin = posn - center;
    // si cette distance est plus petite que le rayon, elle est dedans et il faut la faire rebondir
    if length(distance_to_origin) < data.radius {
        var direction = normalize(distance_to_origin); //on caclcule la normale pour déterminer dans 
        // quelle direction renvoyer la particule
        // pour éviter que la particule ne rentre dans la sphere (le temps que le calcul se fasse), on la renvoie directement vers son 
        // rebond en la mettant à 101% du rayon depuis le centre (un peu en dehors, en gros)
        posn = center + direction * (data.radius * 1.01);
        
        // on applique la nouvelle position 
        particlesData[param.x].pos_x = posn.x;
        particlesData[param.x].pos_y = posn.y;
        particlesData[param.x].pos_z = posn.z;

        //On applique la nouvelle vitesse
        particlesData[param.x].velocity_x = 0.0; // velocity.x;
        particlesData[param.x].velocity_y = 0.0; // velocity.y;
        particlesData[param.x].velocity_z = 0.0; // velocity.z;
    }
}
