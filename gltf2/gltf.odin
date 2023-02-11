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

    options := Options{ parse_uris = parse_uris, delete_content = true }
    switch strings.to_lower(filepath.ext(file_name), context.temp_allocator) {
    case ".gltf":
        return parse(file_content, options, allocator)
    case ".glb":
        options.is_glb = true
        return parse(file_content, options, allocator)
    case:
        return nil, GLTF_Error{ type = .Unknown_File_Type, proc_name = #procedure, param = file_name }
    }
}

@(require_results)
parse :: proc(file_content: []byte, opt := Options{}, allocator := context.allocator) -> (data: ^Data, err: Error) {
    defer if opt.delete_content do delete(file_content)

    if len(file_content) < GLB_HEADER_SIZE {
        return data, GLTF_Error{ type = .Data_Too_Short, proc_name = #procedure }
    }

    context.allocator = allocator
    data = new(Data)
    defer if err != nil do unload(data)

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
    data.json_value = parsed_object
    if json_err != .None && json_err != .EOF {
        return data, JSON_Error{ type = json_err, parser = json_parser }
    }

    data.asset = asset_parse(parsed_object.(json.Object)) or_return
    data.accessors = accessors_parse(parsed_object.(json.Object)) or_return
    //data.animations = animations_parse(parsed_object.(json.Object)) or_return
    data.buffers = buffers_parse(parsed_object.(json.Object), opt.parse_uris) or_return
    data.buffer_views = buffer_views_parse(parsed_object.(json.Object)) or_return
    data.cameras = cameras_parse(parsed_object.(json.Object)) or_return
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

    json.destroy_value(data.json_value)
    accessors_free(data.accessors)
    animations_free(data.animations)
    buffers_free(data.buffers)
    buffer_views_free(data.buffer_views)
    cameras_free(data.cameras)
    images_free(data.images)
    materials_free(data.materials)
    meshes_free(data.meshes)
    nodes_free(data.nodes)
    scenes_free(data.scenes)
    extensions_names_free(data.extensions_required)
    extensions_names_free(data.extensions_used)
    free(data)
}

/*
    Utilitiy procedures
*/
// Free extensions and extras
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

@(private)
warning_unexpected_data :: proc(proc_name, key: string, val: json.Value, idx := 0) {
    fmt.printf("WARINING: Unexpected data in proc: %v at index: %v\nKey: %v, valalue: %v\n", proc_name, idx, key, val)
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

        case: warning_unexpected_data(#procedure, k, v)
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

            case: warning_unexpected_data(#procedure, k, v, idx)
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
    delete(accessors)
}

@(require_results)
accessor_sparse_parse :: proc(object: json.Object) -> (res: Accessor_Sparse, err: Error) {
    unimplemented(#procedure)
}

/*
    Animations parsing
*/
@(require_results)
animations_parse :: proc(object: json.Object) -> (res: []Animation, err: Error) {
    if ANIMATIONS_KEY not_in object do return

    animations_array := object[ANIMATIONS_KEY].(json.Array)
    res = make([]Animation, len(animations_array))

    for animation, idx in animations_array {
        for k, v in animation.(json.Object) {
            switch k {
            case "channels": // Required
                res[idx].channels = animation_channels_parse(v.(json.Array)) or_return

            case "samplers": // Required
                res[idx].samplers = animation_samplers_parse(v.(json.Array)) or_return

            case "name":
                res[idx].name = v.(string)

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case: warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if len(res[idx].channels) == 0 {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "channels" }
        }
        if len(res[idx].samplers) == 0 {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "samplers" }
        }
    }
    return res, nil
}

animations_free :: proc(animations: []Animation) {
    if len(animations) == 0 do return
    for animation in animations {
        if len(animation.channels) > 0 do delete(animation.channels)
        if len(animation.samplers) > 0 do delete(animation.samplers)
    }
    delete(animations)
}

@(require_results)
animation_channels_parse :: proc(array: json.Array) -> (res: []Animation_Channel, err: Error) {
    res = make([]Animation_Channel, len(array))

    for channel, idx in array {
        sampler_set, target_set: bool

        for k, v in channel.(json.Object) {
            switch k {
            case "sampler": // Required
                res[idx].sampler = Integer(v.(f64))
                sampler_set = true

            case "target": // Required
                res[idx].target = animation_channel_target_parse(v.(json.Object)) or_return
                target_set = true

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case: warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if !sampler_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "sampler" }
        }
        if !target_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "target" }
        }
    }

    return res, nil
}

@(require_results)
animation_channel_target_parse :: proc(object: json.Object) -> (res: Animation_Channel_Target, err: Error) {
    path_set: bool

    for k, v in object {
        switch k {
        case "node":
            res.node = Integer(v.(f64))

        case "path": // Required
            res.path = v.(string)
            path_set = true

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        case: warning_unexpected_data(#procedure, k, v)
        }
    }

    if !path_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "path" }
    }

    return res, nil
}

@(require_results)
animation_samplers_parse :: proc(array: json.Array) -> (res: []Animation_Sampler, err: Error) {
    res = make([]Animation_Sampler, len(array))

    for sampler, idx in array {
        input_set, output_set: bool

        for k, v in sampler.(json.Object) {
            switch k {
            case "input": // Required
                res[idx].input = Integer(v.(f64))
                input_set = true

            case "interpolation": // Defalt Linear(0)
                res[idx].interpolation = Interpolation_Algorithm(v.(f64))

            case "output": // Required
                res[idx].output = Integer(v.(f64))
                output_set = true

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case: warning_unexpected_data(#procedure, k, v)
            }
        }

        if !input_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "input" }
        }
        if !output_set {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "output" }
        }
    }
    return res, nil
}

/*
    Cameras parsing
*/
@(require_results)
cameras_parse :: proc(object: json.Object) -> (res: []Camera, err: Error) {
    if CAMERAS_KEY not_in object do return

    cameras_array := object[CAMERAS_KEY].(json.Array)
    res = make([]Camera, len(cameras_array))

    for camera, idx in cameras_array {
        for k, v in camera.(json.Object) {
            switch k {
            case "name":
                res[idx].name = v.(string)

            case "type": // Required and not used here. Camera.type is union that can contain only:
                        // Orthographic_Camera or Perspective_Camera struct
            case "orthographic":
                res[idx].type = orthographic_camera_parse(v.(json.Object)) or_return

            case "perspective":
                res[idx].type = perspective_camera_parse(v.(json.Object)) or_return

            case EXTENSIONS_KEY:
                res[idx].extensions = v

            case EXTRAS_KEY:
                res[idx].extras = v

            case: warning_unexpected_data(#procedure, k, v, idx)
            }
        }

        if res[idx].type == nil {
            return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "type" }
        }
    }

    return res, nil
}

cameras_free :: proc(cameras: []Camera) {
    if len(cameras) == 0 do return
    delete(cameras)
}

@(require_results)
orthographic_camera_parse :: proc(object: json.Object) -> (res: Orthographic_Camera, err: Error) {
    xmag_set, ymag_set, zfar_set, znear_set: bool

    for k, v in object {
        switch k {
        case "xmag": // Required
            res.xmag = Number(v.(f64))
            xmag_set = true

        case "ymag": // Required
            res.ymag = Number(v.(f64))
            ymag_set = true

        case "zfar": // Required
            res.zfar = Number(v.(f64))
            zfar_set = true

        case "znear": // Required
            res.znear = Number(v.(f64))
            znear_set = true

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        case: warning_unexpected_data(#procedure, k, v)
        }
    }

    if !xmag_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "xmag" }
    }
    if !ymag_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "ymag" }
    }
    if !zfar_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "zfar" }
    }
    if !znear_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "znear" }
    }

    return res, nil
}

@(require_results)
perspective_camera_parse :: proc(object: json.Object) -> (res: Perspective_Camera, err: Error) {
    yfov_set, znear_set: bool

    for k, v in object {
        switch k {
        case "aspectRatio":
            res.aspect_ratio = Number(v.(f64))

        case "yfov": // Required
            res.yfov = Number(v.(f64))
            yfov_set = true

        case "zfar":
            res.zfar = Number(v.(f64))

        case "znear": // Required
            res.znear = Number(v.(f64))
            znear_set = true

        case EXTENSIONS_KEY:
            res.extensions = v

        case EXTRAS_KEY:
            res.extras = v

        case: warning_unexpected_data(#procedure, k, v)
        }
    }

    if !yfov_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "yfov" }
    }
    if !znear_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "znear" }
    }

    return res, nil
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

            case: warning_unexpected_data(#procedure, k, v, idx)
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
    for buffer in buffers do uri_free(buffer.uri)
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

            case: warning_unexpected_data(#procedure, k, v, idx)
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

            case: warning_unexpected_data(#procedure, k, v, idx)
            }
        }
    }

    return res, nil
}

images_free :: proc(images: []Image) {
    if len(images) == 0 do return
    for image in images do uri_free(image.uri)
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

            case: warning_unexpected_data(#procedure, k, v, idx)
            }
        }
    }
    return res, nil
}

materials_free :: proc(materials: []Material) {
    if len(materials) == 0 do return
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

        case: warning_unexpected_data(#procedure, k, v)
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

        case: warning_unexpected_data(#procedure, k, v)
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

        case: warning_unexpected_data(#procedure, k, v)
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

            case: warning_unexpected_data(#procedure, k, v, idx)
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

            case: warning_unexpected_data(#procedure, key, val, idx)
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

            case: warning_unexpected_data(#procedure, k, v, idx)
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

            case: warning_unexpected_data(#procedure, k, v, idx)
            }
        }
    }

    return res, nil
}

scenes_free :: proc(scenes: []Scene) {
    if len(scenes) == 0 do return
    for scene in scenes do if len(scene.nodes) > 0 do delete(scene.nodes)
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

        case: warning_unexpected_data(#procedure, k, v)
        }
    }

    if !index_set {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "index" }
    }

    return res, nil
}
