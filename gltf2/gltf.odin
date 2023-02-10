package gltf2
// (cast(^Struct)(raw_data(bytes[from:to])))^
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"


GLB_MAGIC :: 0x46546c67
GLB_HEADER_SIZE :: size_of(GLB_Header)
GLTF_MIN_VERSION :: 2



/*
    Main library interface procedures
*/
@(require_results)
load_from_file :: proc(file_name: string, parse_uris := false, allocator := context.allocator) -> (data: ^Data, err: Error) {
    if !os.exists(file_name) do return nil, GLTF_Error{ type = .No_File, proc_name = #procedure, param = file_name }

    file_content, ok := os.read_entire_file(file_name, allocator)
    if !ok do return nil, GLTF_Error{ type = .Cant_Read_File, proc_name = #procedure, param = file_name }

    switch strings.to_lower(filepath.ext(file_name)) {
    case ".gltf":
        return parse(file_content, { parse_uris = parse_uris, delete_content = true })
    case ".glb":
        return parse(file_content, { is_glb = true, parse_uris = parse_uris, delete_content = true })
    case:
        return nil, GLTF_Error{ type = .Unknown_File_Type, proc_name = #procedure, param = file_name }
    }
}

@(require_results)
parse :: proc(file_content: []byte, opt := Options{}) -> (data: ^Data, err: Error) {
    defer if opt.delete_content do delete(file_content)
    defer if err != nil do unload(data)

    if len(file_content) < GLB_HEADER_SIZE {
        return data, GLTF_Error{ type = .Data_Too_Short, proc_name = #procedure }
    }

    data = new(Data)
    json_data := file_content
    content_index: u32

    if opt.is_glb {
        header := (cast(^GLB_Header)(raw_data(file_content[:GLB_HEADER_SIZE])))^
        content_index += GLB_HEADER_SIZE

        switch {
        case header.magic != GLB_MAGIC:
            return data, GLTF_Error{ type = .Bad_GLB_Magic, proc_name = #procedure }
        case header.version < GLTF_MIN_VERSION:
            return data, GLTF_Error{ type = .Unsupported_Version, proc_name = #procedure }
        }

        // TODO: Parse JSON chunk and other chunks
    }

    json_parser := json.make_parser(json_data)
    parsed_object, json_err := json.parse_object(&json_parser)
    defer if err == nil {
        free_json_value(parsed_object)
    } else {
        free_json_value(parsed_object, true)
    }
    if json_err != .None && json_err != .EOF {
        return data, JSON_Error{ type = json_err, parser = json_parser }
    }

    data.asset = asset_parse(parsed_object.(json.Object)) or_return
    data.accessors = accessors_parse(parsed_object.(json.Object)) or_return
    //data.animations = animations_parse(parsed_object.(json.Object)) or_return
    data.buffers = buffers_parse(parsed_object.(json.Object), opt.parse_uris) or_return
    data.buffer_views = buffer_views_parse(parsed_object.(json.Object)) or_return
    //data.cameras = cameras_parse(parsed_object.(json.Object)) or_return
    data.images = images_parse(parsed_object.(json.Object), opt.parse_uris) or_return
    data.materials = materials_parse(parsed_object.(json.Object)) or_return
    data.meshes = meshes_parse(parsed_object.(json.Object)) or_return
    data.nodes = nodes_parse(parsed_object.(json.Object)) or_return
    //data.samplers = samplers_parse(parsed_object.(json.Object)) or_return
    if scene, ok := parsed_object.(json.Object)[SCENE_KEY]; ok {
        data.scene = Integer(scene.(f64))
    }
    data.scenes = scenes_parse(parsed_object.(json.Object)) or_return
    //data.skins = skins_parse(parsed_object.(json.Object)) or_return
    //data.textures = textures_parse(parsed_object.(json.Object)) or_return
    data.extensions_used = extensions_names_parse(parsed_object.(json.Object), EXTENSIONS_USED_KEY)
    data.extensions_required = extensions_names_parse(parsed_object.(json.Object), EXTENSIONS_REQUIRED_KEY)
    if extensions, ok := parsed_object.(json.Object)[EXTENSIONS_KEY]; ok {
        data.extensions = extensions
    }
    if extras, ok := parsed_object.(json.Object)[EXTRAS_KEY]; ok {
        data.extras = extras
    }

    return data, nil
}

// It is safe to pass nil here
unload :: proc(data: ^Data) {
    if data == nil do return

    ext_free(data.asset)
    accessors_free(data.accessors)
    buffers_free(data.buffers)
    buffer_views_free(data.buffer_views)
    images_free(data.images)
    materials_free(data.materials)
    meshes_free(data.meshes)
    nodes_free(data.nodes)
    scenes_free(data.scenes)
    extensions_names_free(data.extensions_required)
    extensions_names_free(data.extensions_used)
    ext_free(data)
    free(data)
}

/*
    Utilitiy procedures
*/
// Free extensions and extras
ext_free :: proc(str: $T) {
    if str.extensions != nil do free_json_value(str.extensions, true)
    if str.extras != nil do free_json_value(str.extras, true)
}

free_json_value :: proc(value: json.Value, extensions_and_extras := false) {
    #partial switch val in value {
    case json.Array:
        for v in val do free_json_value(v, extensions_and_extras)
        delete(val)

    case json.Object:
        for k, v in val {
            if !extensions_and_extras && (k == EXTENSIONS_KEY || k == EXTRAS_KEY) do continue
            free_json_value(v, extensions_and_extras)
        }
        delete(val)
    }
}

@(require_results)
extensions_names_parse :: proc(object: json.Object, name: string) -> (res: []string) {
    if name not_in object do return

    name_array := object[name].(json.Array)
    res = make([]string, len(name_array))
    
    for n, i in name_array do res[i] = n.(string)

    return res
}

extensions_names_free :: proc(names: []string) {
    if len(names) == 0 do return
    delete(names)
}

@(require_results)
uri_parse :: proc(uri: Uri) -> Uri {
    if uri == nil do return uri
    if _, ok := uri.([]byte); ok do return uri

    str_data := uri.(string)
    type_idx := strings.index_rune(str_data, ':')
    if type_idx == -1 do return uri

    type := str_data[:type_idx]
    switch type {
    case "data":
        encoding_start_idx := strings.index_rune(str_data, ';') + 1
        if encoding_start_idx == 0 do return uri
        encoding_end_idx := strings.index_rune(str_data, ',')
        if encoding_end_idx == -1 do return uri

        encoding := str_data[encoding_start_idx:encoding_end_idx]

        switch encoding {
        case "base64":
            return base64.decode(str_data[encoding_end_idx+1:])
        }
    }

    return uri
}

uri_free :: proc(uri: Uri) {
    if data, ok := uri.([]byte); ok {
        delete(data)
    }
}

/*get_chunk :: proc(file_content: []byte, expected_type := Chunk_Type.Other) -> (ch: GLB_Chunk, ok: bool) {
    SIZE :: size_of(u32) * 2
    remaining_bytes := len(file_content) - int(data.content_index) - SIZE
    if remaining_bytes < 0 do return

    mem.copy(&ch, raw_data(data.file_content[data.content_index:]), SIZE)
    data.content_index += SIZE
    defer if !ok do data.content_index -= SIZE

    if ch.length > u32(remaining_bytes) do return
    if expected_type != .Other && ch.type != u32(expected_type) do return

    chunk_end_index := data.content_index + ch.length
    ch.data = data.file_content[data.content_index:chunk_end_index]
    data.content_index = chunk_end_index
    return ch, true
}*/

/*
    Asseet parsing
*/
@(require_results)
asset_parse :: proc(object: json.Object) -> (res: Asset, err: Error) {
    if ASSET_KEY not_in object do return res, GLTF_Error{ type = .JSON_Missing_Section, proc_name = #procedure, param = ASSET_KEY }

    version_found: bool

    for k, v in object[ASSET_KEY].(json.Object) {
        switch k {
        case "copyright":
            res.copyright = v.(string)

        case "generator":
            res.generator = v.(string)

        case "version": // Required
            version, ok := strconv.parse_f64(v.(string))
            if !ok do return res, GLTF_Error{ type = .Invalid_Type, proc_name = #procedure, param = "version" }
            res.version = Number(version)
            version_found = true

        case "minVersion":
            version, ok := strconv.parse_f64(v.(string))
            if !ok do continue
            res.min_version = Number(version)

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        }
    }

    if !version_found {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "version" }
    } else if res.version > GLTF_MIN_VERSION {
        return res, GLTF_Error{ type = .Unsupported_Version, proc_name = #procedure }
    }
    return res, nil
}

/*
    Accessors parsing
*/
@(require_results)
accessors_parse :: proc(object: json.Object) -> (res: []Accessor, err: Error) {
    if ACCESSORS_KEY not_in object do return

    accessor_array := object[ACCESSORS_KEY].(json.Array)
    res = make([]Accessor, len(accessor_array))

    for access, idx in accessor_array {
        component_type_set, count_set, type_set: bool

        for k, v in access.(json.Object){
            switch k {
            case "bufferView":
                res[idx].buffer_view = Integer(v.(f64))

            case "byteOffset":
                res[idx].byte_offset = Integer(v.(f64))

            case "componentType": // Required
                res[idx].component_type = Component_Type(v.(f64))
                component_type_set = true

            case "normalized":
                res[idx].normalized = v.(bool)

            case "count": // Required
                res[idx].count = Integer(v.(f64))
                count_set = true

            case "type": // Required
                switch v.(string) {
                case "SCALAR":
                    res[idx].type = .Scalar
                    type_set = true

                case "VEC2":
                    res[idx].type = .Vector2
                    type_set = true

                case "VEC3":
                    res[idx].type = .Vector3
                    type_set = true

                case "VEC4":
                    res[idx].type = .Vector4
                    type_set = true

                case "MAT2":
                    res[idx].type = .Matrix2
                    type_set = true

                case "MAT3":
                    res[idx].type = .Matrix3
                    type_set = true

                case "MAT4":
                    res[idx].type = .Matrix4
                    type_set = true

                case:
                    return res, GLTF_Error{ type = .Invalid_Type, proc_name = #procedure, param = v.(string) }
                }

            case "max":
                max: [16]Number
                for num, i in v.(json.Array) do max[i] = Number(num.(f64))
                res[idx].max = max

            case "min":
                min: [16]Number
                for num, i in v.(json.Array) do min[i] = Number(num.(f64))
                res[idx].min = min

            case "sparse":
                res[idx].sparse = accessor_sparse_parse(v.(json.Object)) or_return

            case "name":
                res[idx].name = v.(string)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v
            }
        }

        if !component_type_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "componentType" }
        }
        if !count_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "count" }
        }
        if !type_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "type" }
        }
    }

    return res, nil
}

accessors_free :: proc(accessors: []Accessor) {
    if len(accessors) == 0 do return
    for accessor in accessors do ext_free(accessor)
    delete(accessors)
}

@(require_results)
accessor_sparse_parse :: proc(object: json.Object) -> (res: Accessor_Sparse, err: Error) {
    unimplemented(#procedure)
}

/*
    Buffers parsing
*/
@(require_results)
buffers_parse :: proc(object: json.Object, parse_uri: bool) -> (res: []Buffer, err: Error) {
    if BUFFERS_KEY not_in object do return

    buffers_array := object[BUFFERS_KEY].(json.Array)
    res = make([]Buffer, len(buffers_array))

    for buffer, idx in buffers_array {
        byte_length_set: bool

        for k, v in buffer.(json.Object) {
            switch k {
            case "byteLength": // Required
                res[idx].byte_length = Integer(v.(f64))
                byte_length_set = true

            case "name":
                res[idx].name = v.(string)

            case "uri":
                res[idx].uri = parse_uri ? uri_parse(v.(string)) : Uri(v.(string))

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v
            }
        }

        if !byte_length_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "byteLength" }
        }
    }

    return res, nil
}

buffers_free :: proc(buffers: []Buffer) {
    if len(buffers) == 0 do return
    for buffer in buffers {
        uri_free(buffer.uri)
        ext_free(buffer)
    }
    delete(buffers)
}

/*
    Buffer Views parsing
*/
@(require_results)
buffer_views_parse :: proc(object: json.Object) -> (res: []Buffer_View, err: Error) {
    if BUFFER_VIEWS_KEY not_in object do return

    views_array := object[BUFFER_VIEWS_KEY].(json.Array)
    res = make([]Buffer_View, len(views_array))

    for view, idx in views_array {
        buffer_set, byte_length_set: bool

        for k, v in view.(json.Object) {
            switch k {
            case "buffer": // Required
                res[idx].buffer = Integer(v.(f64))
                buffer_set = true

            case "byteLength": // Required
                res[idx].byte_length = Integer(v.(f64))
                byte_length_set = true

            case "byteOffset":
                res[idx].byte_offset = Integer(v.(f64))

            case "byteStride":
                res[idx].byte_stride = Integer(v.(f64))

            case "name":
                res[idx].name = v.(string)

            case "target":
                res[idx].target = Buffer_Type_Hint(v.(f64))

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v
            }
        }

        if !buffer_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "buffer" }
        }
        if !byte_length_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "byteLength" }
        }
    }

    return res, nil
}

buffer_views_free :: proc(views: []Buffer_View) {
    if len(views) == 0 do return
    for view in views do ext_free(view)
    delete(views)
}

/*
    Images parsing
*/
@(require_results)
images_parse :: proc(object: json.Object, parse_uri: bool) -> (res: []Image, err: Error) {
    if IMAGES_KEY not_in object do return

    images_array := object[IMAGES_KEY].(json.Array)
    res = make([]Image, len(images_array))

    for image, idx in images_array {
        for k, v in image.(json.Object) {
            switch k {
            case "bufferView":
                res[idx].buffer_view = Integer(v.(f64))

            case "mimeType":
                switch v.(string) {
                case "image/jpeg":
                    res[idx].type = .JPEG
                case "image/png":
                    res[idx].type = .PNG
                case:
                    return res, GLTF_Error{ type = .Unknown_File_Type, proc_name = #procedure, param = v.(string) }
                }

            case "name":
                res[idx].name = v.(string)

            case "uri":
                res[idx].uri = parse_uri ? uri_parse(v.(string)) : Uri(v.(string))

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v
            }
        }
    }

    return res, nil
}

images_free :: proc(images: []Image) {
    if len(images) == 0 do return
    for image in images {
        uri_free(image.uri)
        ext_free(image)
    }
    delete(images)
}

/*
    Materials parsing
*/
@(require_results)
materials_parse :: proc(object: json.Object) -> (res: []Material, err: Error) {
    if MATERIALS_KEY not_in object do return

    materials_array := object[MATERIALS_KEY].(json.Array)
    res = make([]Material, len(materials_array))

    for material, idx in materials_array {
        res[idx].alpha_cutoff = 0.5

        for k, v in material.(json.Object) {
            switch k {
            case "alphaMode": // Default Opaque
                switch v.(string) {
                case "OPAQUE":
                    res[idx].alpha_mode = .Opaque
                case "MASK":
                    res[idx].alpha_mode = .Mask
                case "BLEND":
                    res[idx].alpha_mode = .Blend
                case:
                    return res, GLTF_Error{ type = .Invalid_Type, proc_name = #procedure, param = v.(string) }
                }

            case "alphaCutoff": // Default 0.5
                res[idx].alpha_cutoff = Number(v.(f64))

            case "doubleSided": // Default false
                res[idx].double_sided = v.(bool)

            case "emissiveFactor": // Default [0, 0, 0]
                for num, i in v.(json.Array) do res[idx].emissive_factor[i] = Number(num.(f64))

            case "emissiveTexture":
                res[idx].emissive_texture = texture_info_parse(v.(json.Object)) or_return

            case "name":
                res[idx].name = v.(string)

            case "normalTexture":
                res[idx].normal_texture = normal_texture_info_parse(v.(json.Object)) or_return

            case "occlusionTexture":
                res[idx].occlusion_texture = occlusion_texture_info_parse(v.(json.Object)) or_return

            case "pbrMetallicRoughness":
                res[idx].metallic_roughness = pbr_metallic_roughness_parse(v.(json.Object)) or_return

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v
            }
        }
    }
    return res, nil
}

materials_free :: proc(materials: []Material) {
    if len(materials) == 0 do return
    for material in materials {
        ext_free(material)
        if material.emissive_texture != nil do ext_free(material.emissive_texture.?)
        if material.normal_texture != nil do ext_free(material.normal_texture.?)
        if material.occlusion_texture != nil do ext_free(material.occlusion_texture.?)
        if material.metallic_roughness != nil {
            if material.metallic_roughness.?.base_color_texture != nil do ext_free(material.metallic_roughness.?.base_color_texture.?)
            if material.metallic_roughness.?.metallic_roughness_texture != nil do ext_free(material.metallic_roughness.?.metallic_roughness_texture.?)
            ext_free(material.metallic_roughness.?)
        }
    }
    delete(materials)
}

@(require_results)
normal_texture_info_parse :: proc(object: json.Object) -> (res: Material_Normal_Texture_Info, err: Error) {
    index_set: bool
    res.scale = 1

    for k, v in object {
        switch k {
        case "index": // Required
            res.index = Integer(v.(f64))
            index_set = true

        case "texCoord": // Default 0
            res.tex_coord = Integer(v.(f64))

        case "scale": // Default 1
            res.scale = Number(v.(f64))

        case EXTENSIONS_KEY:
            res.extras = v

        case EXTRAS_KEY:
            res.extras = v
        }
    }

    if !index_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "index" }
    }

    return res, nil
}

@(require_results)
occlusion_texture_info_parse :: proc(object: json.Object) -> (res: Material_Occlusion_Texture_Info, err: Error) {
    index_set: bool
    res.strength = 1

    for k, v in object {
        switch k {
        case "index": // Required
            res.index = Integer(v.(f64))
            index_set = true

        case "texCoord": // Default 0
            res.tex_coord = Integer(v.(f64))

        case "strength": // Default 1
            res.strength = Number(v.(f64))

        case EXTENSIONS_KEY:
            res.extras = v

        case EXTRAS_KEY:
            res.extras = v
        }
    }

    if !index_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "index" }
    }

    return res, nil
}

@(require_results)
pbr_metallic_roughness_parse :: proc(object: json.Object) -> (res: Material_Metallic_Roughness, err: Error) {
    res.base_color_factor = { 1, 1, 1, 1 }
    res.metallic_factor = 1
    res.roughness_factor = 1

    for k, v in object {
        switch k {
        case "baseColorFactor": // Default [ 1, 1, 1, 1 ]
            for num, i in v.(json.Array) do res.base_color_factor[i] = Number(num.(f64))

        case "baseColorTexture":
            res.base_color_texture = texture_info_parse(v.(json.Object)) or_return

        case "metallicFactor": // Default 1
            res.metallic_factor = Number(v.(f64))

        case "roughnessFactor": // Default 1
            res.roughness_factor = Number(v.(f64))

        case "metallicRoughnessTexture":
            res.metallic_roughness_texture = texture_info_parse(v.(json.Object)) or_return

        case EXTENSIONS_KEY:
            res.extras = v

        case EXTRAS_KEY:
            res.extras = v
        }
    }

    return res, nil
}

/*
    Meshes parsing
*/
@(require_results)
meshes_parse :: proc(object: json.Object) -> (res: []Mesh, err: Error) {
    if MESHES_KEY not_in object do return

    meshes_array := object[MESHES_KEY].(json.Array)
    res = make([]Mesh, len(meshes_array))

    for mesh, idx in meshes_array {
        for k, v in mesh.(json.Object) {
            switch k {
            case "name":
                res[idx].name = v.(string)

            case "primitives": // Required
                res[idx].primitives = mesh_primitives_parse(v.(json.Array)) or_return

            case "weights":
                res[idx].weights = make([]Number, len(v.(json.Array)))
                for num, i in v.(json.Array) do res[idx].weights[i] = Number(num.(f64))

            case EXTENSIONS_KEY:
                res[idx].extras = v

            case EXTRAS_KEY:
                res[idx].extras = v
            }
        }

        if len(res[idx].primitives) == 0 {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "primitives" }
        }
    }
    return res, nil
}

meshes_free :: proc(meshes: []Mesh) {
    if len(meshes) == 0 do return
    for mesh in meshes {
        if len(mesh.weights) > 0 do delete(mesh.weights)
        mesh_primitives_free(mesh.primitives)
        ext_free(mesh)
    }
    delete(meshes)
}

@(require_results)
mesh_primitives_parse :: proc(array: json.Array) -> (res: []Mesh_Primitive, err: Error) {
    res = make([]Mesh_Primitive, len(array))

    for primitive, idx in array {
        res[idx].mode = .Triangles

        for key, val in primitive.(json.Object) {
            switch key {
            case "attributes": // Required
                for k, v in val.(json.Object) do res[idx].attributes[k] = Integer(v.(f64))

            case "indices":
                res[idx].indices = Integer(val.(f64))

            case "material":
                res[idx].material = Integer(val.(f64))

            case "mode": // Default Triangles(4)
                res[idx].mode = Mesh_Primitive_Mode(val.(f64))

            case "targets":
                res[idx].targets = mesh_targets_parse(val.(json.Object)) or_return

            case EXTENSIONS_KEY:
                res[idx].extensions = val

            case EXTRAS_KEY:
                res[idx].extras = val
            }
        }

        if len(res[idx].attributes) == 0 {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "attributes" }
        }
    }

    return res, nil
}

mesh_primitives_free :: proc(primitives: []Mesh_Primitive) {
    if len(primitives) == 0 do return
    for primitive in primitives {
        if len(primitive.attributes) > 0 do delete(primitive.attributes)
        ext_free(primitive)
    }
    delete(primitives)
}

@(require_results)
mesh_targets_parse :: proc(object: json.Object) -> (res: []Mesh_Target, err: Error) {
    unimplemented(#procedure)
}

/*
    Nodes parsing
*/
@(require_results)
nodes_parse :: proc(object: json.Object) -> (res: []Node, err: Error) {
    if NODES_KEY not_in object do return

    nodes_array := object[NODES_KEY].(json.Array)
    res = make([]Node, len(nodes_array))

    for node, idx in nodes_array {
        res[idx].mat = Matrix4(1)
        res[idx].rotation = Quaternion(1)
        res[idx].scale = { 1, 1, 1 }

        for k, v in node.(json.Object) {
            switch k {
            case "camera":
                res[idx].camera = Integer(v.(f64))

            case "children":
                res[idx].children = make([]Integer, len(v.(json.Array)))
                for child, i in v.(json.Array) do res[idx].children[i] = Integer(child.(f64))

            case "matrix": // Default identity matrix
                // Matrices are stored in column-major order. Odin matrices are indexed like this [row, col]
                for num, i in v.(json.Array) do res[idx].mat[i % 4, i / 4] = Number(num.(f64))

            case "mesh":
                res[idx].mesh = Integer(v.(f64))

            case "name":
                res[idx].name = v.(string)

            case "scale": // Default [1, 1, 1]
                for num, i in v.(json.Array) do res[idx].scale[i] = Number(num.(f64))

            case "skin":
                res[idx].skin = Integer(v.(f64))

            case "rotation": // Default [0, 0, 0, 1]
                rotation: [4]Number
                for num, i in v.(json.Array) do rotation[i] = Number(num.(f64))
                mem.copy(&res[idx].rotation, &rotation, size_of(Quaternion))

            case "translation": // Defalt [0, 0, 0]
                for num, i in v.(json.Array) do res[idx].translation[i] = Number(num.(f64))

            case "weights":
                res[idx].weights = make([]Number, len(v.(json.Array)))
                for weight, i in v.(json.Array) do res[idx].weights[i] = Number(weight.(f64))

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v
            }
        }
    }
    return res, nil
}

nodes_free :: proc(nodes: []Node) {
    if len(nodes) == 0 do return
    for node in nodes {
        if len(node.children) > 0 do delete(node.children)
        if len(node.weights) > 0 do delete(node.weights)
        ext_free(node)
    }
    delete(nodes)
}

/*
    Scenes parsing
*/
@(require_results)
scenes_parse :: proc(object: json.Object) -> (res: []Scene, err: Error) {
    if SCENES_KEY not_in object do return

    scenes_array := object[SCENES_KEY].(json.Array)
    res = make([]Scene, len(scenes_array))

    for scene, idx in scenes_array {
        for k, v in scene.(json.Object) {
            switch k {
            case "nodes":
                res[idx].nodes = make([]Integer, len(v.(json.Array)))
                for node, i in v.(json.Array) do res[idx].nodes[i] = Integer(node.(f64))

            case "name":
                res[idx].name = v.(string)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v
            }
        }
    }

    return res, nil
}

scenes_free :: proc(scenes: []Scene) {
    if len(scenes) == 0 do return
    for scene in scenes {
        if len(scene.nodes) > 0 do delete(scene.nodes)
        ext_free(scene)
    }
    delete(scenes)
}

/*
    Textures parsing
*/
@(require_results)
texture_info_parse :: proc(object: json.Object) -> (res: Texture_Info, err: Error) {
    index_set: bool
    for k, v in object {
        switch k {
        case "index": //Required
            res.index = Integer(v.(f64))
            index_set = true

        case "texCoord": // Default 0
            res.tex_coord = Integer(v.(f64))

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v
        }
    }

    if !index_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "index" }
    }

    return res, nil
}
