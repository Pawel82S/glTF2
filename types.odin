package gltf2

import "core:encoding/json"

// odinfmt: disable
@(private) ACCESSORS_KEY :: "accessors"
@(private) ANIMATIONS_KEY :: "animations"
@(private) ASSET_KEY :: "asset"
@(private) BUFFERS_KEY :: "buffers"
@(private) BUFFER_VIEWS_KEY :: "bufferViews"
@(private) CAMERAS_KEY :: "cameras"
@(private) IMAGES_KEY :: "images"
@(private) MATERIALS_KEY :: "materials"
@(private) MESHES_KEY :: "meshes"
@(private) NODES_KEY :: "nodes"
@(private) SAMPLERS_KEY :: "samplers"
@(private) SCENE_KEY :: "scene"
@(private) SCENES_KEY :: "scenes"
@(private) SKINS_KEY :: "skins"
@(private) TEXTURES_KEY :: "textures"
@(private) EXTENSIONS_KEY :: "extensions"
@(private) EXTENSIONS_REQUIRED_KEY :: "extensionsRequired"
@(private) EXTENSIONS_USED_KEY :: "extensionsUsed"
@(private) EXTRAS_KEY :: "extras"
// odinfmt: enable

/*
Add following line when compiling to change type of `Number` from f32 to f64:
    -define:GLTF_DOUBLE_PRECISION=true
*/
GLTF_DOUBLE_PRECISION :: #config(GLTF_DOUBLE_PRECISION, false)

Integer :: u32
Number :: f64 when GLTF_DOUBLE_PRECISION else f32
Matrix4 :: matrix[4, 4]Number
Quaternion :: quaternion256 when GLTF_DOUBLE_PRECISION else quaternion128

Options :: struct {
    is_glb, delete_content: bool,
    gltf_dir:               string,
}

GLB_Header :: struct {
    magic, version, length: u32le,
}

CHUNK_TYPE_BIN :: 0x004e4942
CHUNK_TYPE_JSON :: 0x4e4f534a

GLB_Chunk_Header :: struct {
    length, type: u32le,
}


Data :: struct {
    asset:               Asset,
    accessors:           []Accessor,
    animations:          []Animation,
    buffers:             []Buffer,
    buffer_views:        []Buffer_View,
    cameras:             []Camera,
    images:              []Image,
    materials:           []Material,
    meshes:              []Mesh,
    nodes:               []Node,
    samplers:            []Sampler,
    scene:               Maybe(Integer),
    scenes:              []Scene,
    skins:               []Skin,
    textures:            []Texture,
    extensions_used:     []string,
    extensions_required: []string,
    extensions:          Extensions,
    extras:              Extras,
    json_value:          json.Value,
}

Error :: union {
    JSON_Error,
    GLTF_Error,
}

JSON_Error :: struct {
    type:   json.Error,
    parser: json.Parser,
}

GLTF_Error :: struct {
    type:      Error_Type,
    proc_name: string,
    param:     GLTF_Param_Error,
}

GLTF_Param_Error :: struct {
    name:  string,
    index: int,
}

Error_Type :: enum {
    Bad_GLB_Magic,
    Cant_Read_File,
    Data_Too_Short,
    Missing_Required_Parameter,
    No_File,
    Invalid_Type,
    JSON_Missing_Section,
    Unknown_File_Type,
    Unsupported_Version,
    Wrong_Chunk_Type,
}


/*
    Asset data structure
*/
Asset :: struct {
    version:              Number, // Required
    min_version:          Maybe(Number),
    copyright, generator: Maybe(string),
    extensions:           Extensions,
    extras:               Extras,
}


/*
    Other data structures
*/
Component_Type :: enum u16 {
    Byte = 5120,
    Unsigned_Byte,
    Short,
    Unsigned_Short,
    Unsigned_Int = 5125,
    Float,
}

Extensions :: json.Value
Extras :: json.Value

Uri :: union {
    string,
    []byte,
}


/*
    Accessor related data structures
*/
Accessor :: struct {
    byte_offset:    Integer,
    component_type: Component_Type, // Required
    normalized:     bool,
    count:          Integer, // Required
    type:           Accessor_Type, // Required
    buffer_view:    Maybe(Integer),
    max, min:       Maybe([16]Number),
    name:           Maybe(string),
    sparse:         Maybe(Accessor_Sparse),
    extensions:     Extensions,
    extras:         Extras,
}

Accessor_Type :: enum {
    Scalar,
    Vector2,
    Vector3,
    Vector4,
    Matrix2,
    Matrix3,
    Matrix4,
}

Accessor_Sparse :: struct {
    //count: Integer, // Required
    indices:    []Accessor_Sparse_Indices, // Required
    values:     []Accessor_Sparse_Values, // Required
    extensions: Extensions,
    extras:     Extras,
}

Accessor_Sparse_Indices :: struct {
    buffer_view:    Integer, // Required
    byte_offset:    Integer,
    component_type: Component_Type, // Required
    extensions:     Extensions,
    extras:         Extras,
}

Accessor_Sparse_Values :: struct {
    buffer_view: Integer, // Required
    byte_offset: Integer,
    extensions:  Extensions,
    extras:      Extras,
}


/*
    Animation related data structurs
*/
Animation :: struct {
    channels:   []Animation_Channel, // Required
    samplers:   []Animation_Sampler, // Required
    name:       Maybe(string),
    extensions: Extensions,
    extras:     Extras,
}

Animation_Channel :: struct {
    sampler:    Integer, // Required
    target:     Animation_Channel_Target, // Required
    extensions: Extensions,
    extras:     Extras,
}

Animation_Channel_Target :: struct {
    path:       Animation_Channel_Path, // Required
    node:       Maybe(Integer),
    extensions: Extensions,
    extras:     Extras,
}

Animation_Sampler :: struct {
    input, output: Integer, // Required
    interpolation: Interpolation_Algorithm, // Default: Linear
    extensions:    Extensions,
    extras:        Extras,
}

Interpolation_Algorithm :: enum {
    Linear = 0, // Default
    Step,
    Cubic_Spline,
}

Animation_Channel_Path :: enum {
    Translation,
    Rotation,
    Scale,
    Weights,
}

/*
    Buffer related data structures
*/
Buffer :: struct {
    byte_length: Integer,
    name:        Maybe(string),
    uri:         Uri,
    extensions:  Extensions,
    extras:      Extras,
}

Buffer_View :: struct {
    buffer, byte_offset, byte_length: Integer,
    byte_stride:                      Maybe(Integer),
    target:                           Maybe(Buffer_Type_Hint),
    name:                             Maybe(string),
    extensions:                       Extensions,
    extras:                           Extras,
}

Buffer_Type_Hint :: enum u16 {
    Array = 34962,
    Element_Array,
}


/*
    Camera related data structures
*/
Camera :: struct {
    type:       union {
        Perspective_Camera,
        Orthographic_Camera,
    },
    name:       Maybe(string),
    extensions: Extensions,
    extras:     Extras,
}

Perspective_Camera :: struct {
    yfov, znear:        Number,
    aspect_ratio, zfar: Maybe(Number),
    extensions:         Extensions,
    extras:             Extras,
}

Orthographic_Camera :: struct {
    xmag, ymag:  Number,
    zfar, znear: Number,
    extensions:  Extensions,
    extras:      Extras,
}


/*
    Image related data structures
*/
Image :: struct {
    name:        Maybe(string),
    uri:         Uri,
    type:        Maybe(Image_Type),
    buffer_view: Maybe(Integer),
    extensions:  Extensions,
    extras:      Extras,
}

Image_Type :: enum {
    JPEG,
    PNG,
}


/*
    Material related data structures
*/
Material :: struct {
    emissive_factor:    [3]Number,
    alpha_mode:         Material_Alpha_Mode,
    alpha_cutoff:       Number, // Default 0.5
    double_sided:       bool,
    name:               Maybe(string),
    emissive_texture:   Maybe(Texture_Info),
    metallic_roughness: Maybe(Material_Metallic_Roughness),
    normal_texture:     Maybe(Material_Normal_Texture_Info),
    occlusion_texture:  Maybe(Material_Occlusion_Texture_Info),
    extensions:         Extensions,
    extras:             Extras,
}

Material_Alpha_Mode :: enum {
    Opaque, // Default
    Mask,
    Alpha_Cutoff,
    Blend,
}

Material_Metallic_Roughness :: struct {
    base_color_factor:                              [4]Number, // Default [1, 1, 1, 1]
    metallic_factor, roughness_factor:              Number, // Default 1
    base_color_texture, metallic_roughness_texture: Maybe(Texture_Info),
    extensions:                                     Extensions,
    extras:                                         Extras,
}

Material_Normal_Texture_Info :: struct {
    index, tex_coord: Integer,
    scale:            Number, // Default 1
    extensions:       Extensions,
    extras:           Extras,
}

Material_Occlusion_Texture_Info :: struct {
    index, tex_coord: Integer,
    strength:         Number, // Default 1
    extensions:       Extensions,
    extras:           Extras,
}


/*
    Mesh related data structures
*/
Mesh :: struct {
    primitives: []Mesh_Primitive,
    weights:    []Number,
    name:       Maybe(string),
    extensions: Extensions,
    extras:     Extras,
}

Mesh_Primitive :: struct {
    attributes:        map[string]Integer, // Required
    mode:              Mesh_Primitive_Mode, // Default Triangles(4)
    indices, material: Maybe(Integer),
    targets:           []Mesh_Target,
    extensions:        Extensions,
    extras:            Extras,
}

Mesh_Primitive_Mode :: enum {
    Points,
    Lines,
    Line_Loop,
    Line_Strip,
    Triangles, // Default
    Triangle_Strip,
    Triangle_Fan,
}

// TODO: Verify if this is correct
Mesh_Target :: struct {
    type:  Mesh_Target_Type,
    index: Integer,
    data:  Accessor,
    name:  string,
}

// TODO: Verify if this is correct
Mesh_Target_Type :: enum {
    Invalid,
    Position,
    Normal,
    Tangent,
    TexCoord,
    Color,
    Joints,
    Weights,
    Custom,
}


/*
    Node data structure
*/
Node :: struct {
    mat:                Matrix4, // Default Identity Matrix
    rotation:           Quaternion, // Default [x = 0, y = 0, z = 0, w = 1]
    scale:              [3]Number, // Default [1, 1, 1]
    translation:        [3]Number,
    camera, mesh, skin: Maybe(Integer),
    children:           []Integer,
    name:               Maybe(string),
    weights:            []Number,
    extensions:         Extensions,
    extras:             Extras,
}


/*
    Sampler data structure
*/
Sampler :: struct {
    wrapS, wrapT: Wrap_Mode, // Default Repeat(10497)
    name:         Maybe(string),
    mag_filter:   Maybe(Magnification_Filter),
    min_filter:   Maybe(Minification_Filter),
    extensions:   Extensions,
    extras:       Extras,
}

Wrap_Mode :: enum u16 {
    Repeat          = 10497, // Default
    Clamp_To_Edge   = 33071,
    Mirrored_Repeat = 33648,
}

Magnification_Filter :: enum u16 {
    Nearest = 9728,
    Linear,
}

Minification_Filter :: enum u16 {
    Nearest = 9728,
    Linear,
    Nearest_MipMap_Nearest = 9984,
    Linear_MipMap_Nearest,
    Nearest_MipMap_Linear,
    Linear_MipMap_Linear,
}


/*
    Scene data structure
*/
Scene :: struct {
    nodes:      []Integer,
    name:       Maybe(string),
    extensions: Extensions,
    extras:     Extras,
}


/*
    Skin data structure
*/
Skin :: struct {
    joints:                          []Integer, // Required
    inverse_bind_matrices, skeleton: Maybe(Integer),
    name:                            Maybe(string),
    extensions:                      Extensions,
    extras:                          Extras,
}


/*
    Texture related data structures
*/
Texture :: struct {
    sampler, source: Maybe(Integer),
    name:            Maybe(string),
    extensions:      Extensions,
    extras:          Extras,
}

Texture_Info :: struct {
    index, tex_coord: Integer,
    extensions:       Extensions,
    extras:           Extras,
}
