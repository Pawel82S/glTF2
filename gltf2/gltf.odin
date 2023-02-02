package gltf2
// (cast(^Struct)(raw_data(bytes[from:to])))^
import "core:encoding/base64"
import "core:encoding/json"
import "core:fmt"
//import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"


GLB_MAGIC :: 0x46546c67
GLB_HEADER_SIZE :: size_of(GLB_Header)
GLTF_MIN_VERSION :: 2


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

// It is safe to pass nil here
unload :: proc(data: ^Data) {
    if data == nil do return

    ext_free(data.asset)
    ext_free(data)
    free(data)
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
    //data.images = images_parse(parsed_object.(json.Object)) or_return
    //data.materials = materials_parse(parsed_object.(json.Object)) or_return
    //data.meshes = meshes_parse(parsed_object.(json.Object)) or_return
    //data.nodes = nodes_parse(parsed_object.(json.Object)) or_return
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

@(private)
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

@(private, require_results)
asset_parse :: proc(object: json.Object) -> (res: Asset, err: Error) {
    if ASSET_KEY not_in object do return res, GLTF_Error{ type = .JSON_Missing_Section, proc_name = #procedure, param = ASSET_KEY }

    version_found: bool

    for k, v in object[ASSET_KEY].(json.Object) {
        switch {
        case k == "copyright":
            res.copyright = v.(string)

        case k == "generator":
            res.generator = v.(string)

        case k == "version": // Required
            version, ok := strconv.parse_f32(v.(string))
            if !ok {
                return res, GLTF_Error{ type = .Wrong_Parameter_Type, proc_name = #procedure, param = "version" }
            }
            res.version = Number(version)
            version_found = true

        case k == "minVersion":
            version, ok := strconv.parse_f32(v.(string))
            if !ok do continue
            res.min_version = version

        case k == EXTENSIONS_KEY:
            res.extensions = v

        case k == EXTRAS_KEY:
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

// Free extensions and extras
@(private)
ext_free :: proc(str: $T) {
    if str.extensions != nil do free_json_value(str.extensions, true)
    if str.extras != nil do free_json_value(str.extras, true)
}

@(private, require_results)
accessors_parse :: proc(object: json.Object) -> (res: []Accessor, err: Error) {
    if ACCESSORS_KEY not_in object do return

    accessor_array := object[ACCESSORS_KEY].(json.Array)
    array_len := len(accessor_array)
    res = make([]Accessor, array_len)
    defer if err != nil do delete(res)

    Required :: struct { component_type, count, type: bool }
    required := make([]Required, array_len)
    defer delete(required)

    for access, idx in accessor_array {
        for k, v in access.(json.Object){
            switch {
            case k == "bufferView":
                res[idx].buffer_view = Integer(v.(f64))

            case k == "byteOffset":
                res[idx].byte_offset = Integer(v.(f64))

            case k == "componentType": // Required
                res[idx].component_type = Component_Type(v.(f64))
                required[idx].component_type = true

            case k == "normalized":
                res[idx].normalized = v.(bool)

            case k == "count": // Required
                res[idx].count = Integer(v.(f64))
                required[idx].count = true

            case k == "type": // Required
                switch {
                case v.(string) == "SCALAR":
                    res[idx].type = .Scalar
                    required[idx].type = true

                case v.(string) == "VEC2":
                    res[idx].type = .Vector2
                    required[idx].type = true

                case v.(string) == "VEC3":
                    res[idx].type = .Vector3
                    required[idx].type = true

                case v.(string) == "VEC4":
                    res[idx].type = .Vector4
                    required[idx].type = true

                case v.(string) == "MAT2":
                    res[idx].type = .Matrix2
                    required[idx].type = true

                case v.(string) == "MAT3":
                    res[idx].type = .Matrix3
                    required[idx].type = true

                case v.(string) == "MAT4":
                    res[idx].type = .Matrix4
                    required[idx].type = true

                case: return res, GLTF_Error{ type = .Wrong_Parameter_Type, proc_name = #procedure, param = v.(string) }
                }

            case k == "max":
                max: [16]Number
                for num, i in v.(json.Array) {
                    max[i] = Number(num.(f64))
                }
                res[idx].max = max

            case k == "min":
                min: [16]Number
                for num, i in v.(json.Array) {
                    min[i] = Number(num.(f64))
                }
                res[idx].min = min

            case k == "sparse":
                res[idx].sparse = accessor_sparse_parse(v.(json.Object)) or_return

            case k == "name":
                res[idx].name = v.(string)

            case k == EXTENSIONS_KEY:
                res[idx].extensions = v

            case k == EXTRAS_KEY:
                res[idx].extras = v
            }
        }
    }

    has_requirements := true
    for req in required {
        has_requirements &&= req.component_type && req.count && req.type
    }
    if !has_requirements {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure }
    }
    return res, nil
}

@(private)
accessors_free :: proc(accessors: []Accessor) {
    if len(accessors) == 0 do return
    for accessor in accessors do ext_free(accessor)
    delete(accessors)
}

@(private, require_results)
accessor_sparse_parse :: proc(object: json.Object) -> (res: Accessor_Sparse, err: Error) {
    unimplemented(#procedure)
}

@(private, require_results)
buffers_parse :: proc(object: json.Object, parse_uri: bool) -> (res: []Buffer, err: Error) {
    if BUFFERS_KEY not_in object do return

    buffers_array := object[BUFFERS_KEY].(json.Array)
    array_len := len(buffers_array)
    res = make([]Buffer, array_len)
    defer if err != nil do delete(res)

    required_lengths := make([]bool, array_len)
    defer delete(required_lengths)

    for buffer, idx in buffers_array {
        for k, v in buffer.(json.Object) {
            switch {
            case k == "byteLength": // Required
                res[idx].byte_length = Integer(v.(f64))
                required_lengths[idx] = true

            case k == "name":
                res[idx].name = v.(string)

            case k == "uri":
                res[idx].uri = parse_uri ? uri_parse(v.(string)) : Uri(v.(string))

            case k == EXTENSIONS_KEY:
                res[idx].extensions = v

            case k == EXTRAS_KEY:
                res[idx].extras = v
            }
        }
    }

    has_requirements := true
    for req in required_lengths {
        has_requirements &&= req
    }
    if !has_requirements {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure, param = "byteLength" }
    }
    return res, nil
}

@(private)
buffers_free :: proc(buffers: []Buffer) {
    if len(buffers) == 0 do return
    for buffer in buffers {
        if bytes, ok := buffer.uri.([]byte); ok {
            delete(bytes)
        }
        ext_free(buffer)
    }
    delete(buffers)
}

@(require_results)
uri_parse :: proc(uri: Uri) -> Uri {
    if uri == nil do return uri
    if data, ok := uri.([]byte); ok do return uri

    str_data := uri.(string)
    type_idx := strings.index_rune(str_data, ':')
    if type_idx == -1 do return uri

    type := str_data[:type_idx]
    switch {
    case type == "data":
        encoding_start_idx := strings.index_rune(str_data, ';') + 1
        if encoding_start_idx == 0 do return uri
        encoding_end_idx := strings.index_rune(str_data, ',')
        if encoding_end_idx == -1 do return uri

        encoding := str_data[encoding_start_idx:encoding_end_idx]

        switch {
        case encoding == "base64":
            return base64.decode(str_data[encoding_end_idx+1:])
        }
    }

    return uri
}

uri_free :: proc(uri: ^Uri) {
    if data, ok := uri.([]byte); ok {
        delete(data)
        uri^ = nil
    }
}

@(private, require_results)
buffer_views_parse :: proc(object: json.Object) -> (res: []Buffer_View, err: Error) {
    if BUFFER_VIEWS_KEY not_in object do return

    views_array := object[BUFFER_VIEWS_KEY].(json.Array)
    array_len := len(views_array)
    res = make([]Buffer_View, array_len)
    defer if err != nil do delete(res)

    Required :: struct { buffer, byte_length: bool }
    required := make([]Required, array_len)
    defer delete(required)

    for view, idx in views_array {
        for k, v in view.(json.Object) {
            switch {
            case k == "buffer": // Required
                res[idx].buffer = Integer(v.(f64))
                required[idx].buffer = true

            case k == "byteLength": // Required
                res[idx].byte_length = Integer(v.(f64))
                required[idx].byte_length = true

            case k == "byteOffset":
                res[idx].byte_offset = Integer(v.(f64))

            case k == "byteStride":
                res[idx].byte_stride = Integer(v.(f64))

            case k == "name":
                res[idx].name = v.(string)

            case k == "target":
                res[idx].target = Buffer_Type_Hint(v.(f64))

            case k == EXTENSIONS_KEY:
                res[idx].extensions = v

            case k == EXTRAS_KEY:
                res[idx].extras = v
            }
        }
    }

    has_requirements := true
    for req in required {
        has_requirements &&= req.buffer && req.byte_length
    }
    if !has_requirements {
        return res, GLTF_Error{ type = .Missing_Required_Parameter, proc_name = #procedure }
    }
    return res, nil
}

@(private, require_results)
scenes_parse :: proc(object: json.Object) -> (res: []Scene, err: Error) {
    if SCENES_KEY not_in object do return

    scenes_array := object[SCENES_KEY].(json.Array)
    array_len := len(scenes_array)
    res = make([]Scene, array_len)
    defer if err != nil do delete(res)

    for scene, idx in scenes_array {
        for k, v in scene.(json.Object) {
            switch {
            case k == "nodes":
                res[idx].nodes = make([]Integer, len(v.(json.Array)))
                for node, i in v.(json.Array) {
                    res[idx].nodes[i] = Integer(node.(f64))
                }

            case k == "name":
                res[idx].name = v.(string)

            case k == EXTENSIONS_KEY:
                res[idx].extensions = v

            case k == EXTRAS_KEY:
                res[idx].extras = v
            }
        }
    }

    return res, nil
}

@(private)
scenes_free :: proc(scenes: []Scene) {
    if len(scenes) == 0 do return
    for scene in scenes {
        if len(scene.nodes) > 0 do delete(scene.nodes)
        ext_free(scene)
    }
    delete(scenes)
}

@(private, require_results)
extensions_names_parse :: proc(object: json.Object, name: string) -> (res: []string) {
    if name not_in object do return

    name_array := object[name].(json.Array)
    res = make([]string, len(name_array))
    
    for n, i in name_array do res[i] = n.(string)

    return res
}

@(private)
extensions_names_free :: proc(names: []string) {
    if len(names) == 0 do return
    delete(names)
}
